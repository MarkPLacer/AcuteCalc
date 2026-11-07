import Foundation
import Testing
@testable import AcuteCore

// MARK: Audit 2026-11-07: long evaluations stop when their task is cancelled

/// concurrency:3 and concurrency:4: the app cancels a live evaluation that newer input superseded, but AcuteCore never
/// checked for it, so the stale work ran to its end on a second core. Swift's cancellation is cooperative
/// (https://developer.apple.com/documentation/swift/task): Σ, Π and series check every 4096 terms, integrals once per
/// Kronrod panel, and integrals and limits before they start.
@Suite struct EvaluationCancellationTests {
    /// Cancels the task this runs in. `cancel()` is also part of `Task`, so it is safe to call
    /// (https://developer.apple.com/documentation/swift/unsafecurrenttask); in a synchronous function only the
    /// synchronous `withUnsafeCurrentTask` applies.
    static func cancelCurrentTask() {
        withUnsafeCurrentTask { task in
            guard let task else { return }
            task.cancel()
        }
    }

    /// `work` in a task that is cancelled before the work starts, like a live evaluation that newer input superseded.
    static func inCancelledTask<Value: Sendable>(_ work: @escaping @Sendable () -> Value) async -> Value {
        await Task.detached {
            Self.cancelCurrentTask()
            return work()
        }.value
    }

    /// Deterministic noise in [0, 1) from the last bits of x: no Kronrod panel of it converges.
    static func noise(_ x: Double) -> Double {
        Double(x.bitPattern % 1009) / 1009
    }

    @Test func cancelledEvaluationsStopAtTheirFirstCheck() async throws {
        // The longest Σ and Π allowed (5·10⁶ terms and 10⁶ factors), a series, an integral and a limit: each ran all
        // its terms or samples although its result was thrown away.
        let exprs = try ["sum(1/n^2, n, 1, 5000000)", "prod(1 + 1/n^2, n, 1, 1000000)", "sum(1/n^2, n, 1, inf)",
                         "integral(x^2, x, 0, 1)"].map(parse)
        let body = try parse("sin(x)/x")
        let outcomes = await Self.inCancelledTask { () -> [Result<Double, MathError>] in
            var results = exprs.map { e in Result { () throws(MathError) -> Double in try RealEvaluator.evaluate(e) } }
            results.append(Result { () throws(MathError) -> Double in
                try LimitEvaluator.limit(body, variable: "x", at: 0, direction: .both, context: EvaluationContext())
            })
            return results
        }
        let expected = [Result<Double, MathError>](repeating: .failure(.cancelled), count: 5)
        #expect(outcomes == expected)
    }

    @Test func seriesStopsWithinFourThousandTermsOfTheCancellation() async {
        // The term cancels the task at its 5000th call, 1000 terms into the second pass (the first pass takes 4000);
        // the next check is 4096 terms into that pass. Uncancelled, Σ 1/n² takes 4000 + 2¹⁹ terms.
        let (outcome, calls) = await Task.detached { () -> (Result<Double, MathError>, Int) in
            var terms = 0
            let series = Result { () throws(MathError) -> Double in
                try SeriesSummation.sum(from: 1) { n in
                    terms += 1
                    if terms == 5000 { Self.cancelCurrentTask() }
                    return 1 / (Double(n) * Double(n))
                }
            }
            return (series, terms)
        }.value
        #expect(outcome == .failure(.cancelled))
        #expect(calls < 10_000)
    }

    @Test func integralStopsRefiningOnceCancelled() async {
        // Noise never converges, so uncancelled the bisection spends its whole budget of 80 000 evaluations (and the
        // pieces towards the ends add more). Cancelled at the 1000th, it finishes the panel and the at most 40 panels
        // its recursion has begun, and then throws: its value is cut short, and no piece towards an end starts.
        let calls = await Task.detached { () -> (uncancelled: Int, cancelled: Int, outcome: Result<Double, MathError>) in
            var uncancelled = 0
            _ = try? Integrator.integrate({ x in
                uncancelled += 1
                return Self.noise(x)
            }, from: 0, to: 1)
            var cancelled = 0
            let outcome = Result { () throws(MathError) -> Double in
                try Integrator.integrate({ x in
                    cancelled += 1
                    if cancelled == 1000 { Self.cancelCurrentTask() }
                    return Self.noise(x)
                }, from: 0, to: 1)
            }
            return (uncancelled, cancelled, outcome)
        }.value
        #expect(calls.uncancelled >= 80_000)
        #expect(calls.cancelled < 5_000)
        #expect(calls.outcome == .failure(.cancelled))
    }

    @Test func integralToInfinityStopsOnceCancelled() async {
        // sin x/(x + 1) on [0, ∞): the first pass, on t ∈ [0, 1) with x = t/(1 − t), never converges near t = 1, and
        // uncancelled the lobes come after it (6000 samples alone to find their spacing). Cancelled at the 500th
        // evaluation, the first pass stops refining and the integral throws before the lobes.
        let (outcome, evaluations) = await Task.detached { () -> (Result<Double, MathError>, Int) in
            var count = 0
            let integral = Result { () throws(MathError) -> Double in
                try Integrator.integrate({ x in
                    count += 1
                    if count == 500 { Self.cancelCurrentTask() }
                    return sin(x) / (x + 1)
                }, from: 0, to: .infinity)
            }
            return (integral, count)
        }.value
        #expect(outcome == .failure(.cancelled))
        #expect(evaluations < 2_000)
    }

    @Test func referenceValuesStayInATaskThatIsNotCancelled() async throws {
        // The live evaluation runs in a detached task (BackgroundWork); while it is not cancelled, the checks change
        // nothing: the values of CoreTests, AuditCalculusTests and FeatureTests with their tolerances.
        let cases: [(text: String, value: Double, tolerance: Double)] = [
            ("sum(1/n^2, n, 1, inf)", .pi * .pi / 6, 1e-6),
            ("sum((1/2)^n, n, 0, inf)", 2, 1e-12),
            ("sum(1/n^1.5, n, 1, inf)", 2.612375348685488, 1e-9),
            ("integral(x^2, x, 0, 1)", 1.0 / 3, 1e-12),
            ("integral(x^(-0.9), x, 0, 1)", 10, 1e-9),
            ("prod(n, n, 1, 5)", 120, 0),
        ]
        let exprs = try cases.map { try parse($0.text) }
        let body = try parse("sin(x)/x")
        let (outcomes, limit) = await Task.detached { () -> ([Result<Double, MathError>], Result<Double, MathError>) in
            let values = exprs.map { e in Result { () throws(MathError) -> Double in try RealEvaluator.evaluate(e) } }
            let limitValue = Result { () throws(MathError) -> Double in
                try LimitEvaluator.limit(body, variable: "x", at: 0, direction: .both, context: EvaluationContext())
            }
            return (values, limitValue)
        }.value
        for (c, outcome) in zip(cases, outcomes) {
            let value = try outcome.get()
            #expect(approx(value, c.value, c.tolerance), "\(c.text)")
        }
        #expect(approx(try limit.get(), 1, 1e-9))
    }
}

// MARK: Audit 2026-11-07: one evaluator for all terms of a Σ or Π

/// concurrency:3: Σ and Π evaluated every term with a new evaluator made with `context.with`, which copied the
/// variables for each of up to 5·10⁶ terms. They reuse one evaluator now, and every value must stay the same to the bit.
@Suite struct SumTermEvaluatorTests {
    /// Σ or Π as before: a new evaluator from `context.with` for every term.
    static func termByTerm(_ expr: Expr, context: EvaluationContext) throws(MathError) -> Double {
        var bounds = RealEvaluator(context: context)
        switch expr {
        case .summation(let body, let variable, let lower, let upper):
            let start = try Int(bounds.eval(lower))
            let end = try Int(bounds.eval(upper))
            var total = 0.0
            for n in start...end {
                var inner = RealEvaluator(context: context.with(variable, Double(n)))
                total += try inner.eval(body)
            }
            return total
        case .productSeries(let body, let variable, let lower, let upper):
            let start = try Int(bounds.eval(lower))
            let end = try Int(bounds.eval(upper))
            var total = 1.0
            for n in start...end {
                var inner = RealEvaluator(context: context.with(variable, Double(n)))
                total *= try inner.eval(body)
                if total == 0 || !total.isFinite { break }
            }
            return total
        default:
            throw .unsupported("ni Σ ali Π")
        }
    }

    @Test func sumsAndProductsStayTheSameToTheBit() throws {
        // The existing tests' Σ and Π (AuditExactFormsTests, FeatureTests), longer ones that pass the cancellation check
        // every 4096 terms, nested ones (also over the same letter), and rand, R.Int and dice, whose generator starts
        // again from the seed in every term.
        let typed = try ["sum(1/n!, n, 0, 11)", "sum((-1)^n/n!, n, 0, 12)", "sum(2^n/n!, n, 0, 15)",
                         "sum(1/(n*2^n), n, 1, 26)", "prod(n, n, 1, 5)", "sum(1/n^2, n, 1, 100000)",
                         "prod(1 + 1/n^2, n, 1, 20000)", "sum(sum(1/(n*k), k, 1, n), n, 1, 200)",
                         "sum(sum(n, n, 1, n), n, 1, 200)"].map(parse)
        let n = Expr.variable("n")
        let random: [Expr] = [
            .summation(.product([n, .function(.rand, [])]), variable: "n", lower: .int(1), upper: .int(10_000)),
            .summation(.function(.randInt, [.int(1), n]), variable: "n", lower: .int(1), upper: .int(5000)),
            .productSeries(.sum([.one, .quotient(.function(.dice, []), .int(1000))]), variable: "n", lower: .int(1),
                           upper: .int(5000)),
        ]
        // Stored values, among them an exact n, which the bound n replaces (context.with removes it).
        let context = EvaluationContext(angleUnit: .degrees, variables: ["A": 2, "n": 7], exactVariables: ["n": ExactReal(7)],
                                        randomSeed: 0xC0FFEE)
        for expr in typed + random {
            let reference = try Self.termByTerm(expr, context: context)
            let value = try RealEvaluator.evaluate(expr, context: context)
            #expect(value.bitPattern == reference.bitPattern, "\(expr)")
        }
    }
}
