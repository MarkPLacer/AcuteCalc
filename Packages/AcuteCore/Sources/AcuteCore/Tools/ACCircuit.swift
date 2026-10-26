import Foundation

/// Sinusoidal steady state of RLC circuits (Osnove elektrotehnike II at FE): impedance, the
/// phasors of the currents and voltages, complex power, resonance, and the capacitor that
/// corrects the power factor. Effective (rms) values; the source voltage has phase 0.
public enum ACCircuit {
    public enum Connection: String, Sendable, Hashable, CaseIterable {
        case series, parallel
    }

    public struct Analysis: Sendable, Hashable {
        public var omega: Double
        public var impedance: Complex
        /// The source current.
        public var current: Complex
        /// In series the voltages across R, L and C; in parallel the currents through them.
        public var resistor: Complex
        public var inductor: Complex?
        public var capacitor: Complex?
        /// S = U·I* = P + jQ
        public var power: Complex
        /// f₀ = 1/(2π√(LC)) when both L and C are present.
        public var resonance: Double?
        /// The quality factor: (1/R)·√(L/C) in series, R·√(C/L) in parallel.
        public var quality: Double?

        /// cos φ, the angle by which the voltage leads the current.
        public var powerFactor: Double { cos(impedance.argument) }
        /// The bandwidth f₀/Q between the half-power frequencies.
        public var bandwidth: Double? {
            guard let resonance, let quality, quality > 0 else { return nil }
            return resonance / quality
        }
    }

    /// R in ohms, L in henries and C in farads (nil or 0: the element is missing), f in hertz and
    /// the source voltage U in volts.
    public static func analyze(_ connection: Connection, resistance r: Double, inductance l: Double?, capacitance c: Double?,
                               frequency f: Double, voltage u: Double) throws(MathError) -> Analysis {
        guard r > 0, r.isFinite else { throw .domain("upornost mora biti pozitivna") }
        guard f > 0, f.isFinite, u.isFinite else { throw .domain("frekvenca mora biti pozitivna") }
        let inductance = l.flatMap { $0 > 0 ? $0 : nil }, capacitance = c.flatMap { $0 > 0 ? $0 : nil }
        let omega = 2 * Double.pi * f
        let zR = Complex(r)
        let zL = inductance.map { Complex(0, omega * $0) }
        let zC = capacitance.map { Complex(0, -1 / (omega * $0)) }
        let source = Complex(u)
        let one = Complex(1)
        let impedance: Complex, current: Complex, resistor: Complex, inductor: Complex?, capacitor: Complex?
        switch connection {
        case .series:
            var z = zR
            if let zL { z += zL }
            if let zC { z += zC }
            impedance = z
            current = source / z
            resistor = current * zR
            inductor = zL.map { current * $0 }
            capacitor = zC.map { current * $0 }
        case .parallel:
            var y = one / zR
            if let zL { y += one / zL }
            if let zC { y += one / zC }
            impedance = one / y
            current = source * y
            resistor = source / zR
            inductor = zL.map { source / $0 }
            capacitor = zC.map { source / $0 }
        }
        let power = source * Complex(current.re, -current.im)
        var resonance: Double?, quality: Double?
        if let inductance, let capacitance {
            resonance = 1 / (2 * Double.pi * (inductance * capacitance).squareRoot())
            quality = connection == .series ? (inductance / capacitance).squareRoot() / r : r * (capacitance / inductance).squareRoot()
        }
        return Analysis(omega: omega, impedance: impedance, current: current, resistor: resistor, inductor: inductor,
                        capacitor: capacitor, power: power, resonance: resonance, quality: quality)
    }

    /// The parallel capacitor that raises the power factor of an inductive load from cos φ₁ to
    /// cos φ₂: Q_C = P·(tg φ₁ − tg φ₂) and C = Q_C/(ωU²).
    public static func compensation(power p: Double, from cos1: Double, to cos2: Double, voltage u: Double,
                                    frequency f: Double) throws(MathError) -> (reactive: Double, capacitance: Double) {
        guard p > 0, u > 0, f > 0 else { throw .domain("moč, napetost in frekvenca morajo biti pozitivne") }
        guard cos1 > 0, cos1 <= 1, cos2 > 0, cos2 <= 1, cos2 >= cos1 else {
            throw .domain("faktorja moči sta med 0 in 1, želeni ni manjši od obstoječega")
        }
        let reactive = p * (tan(acos(cos1)) - tan(acos(cos2)))
        return (reactive, reactive / (2 * Double.pi * f * u * u))
    }
}
