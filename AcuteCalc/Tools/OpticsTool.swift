import AcuteCore
import SwiftUI

/// Thin lenses and spherical mirrors: the image from 1/f = 1/a + 1/b with its size and nature,
/// and its construction with the three principal rays.
struct OpticsToolView: View {
    @State private var kind = Optics.Kind.convergingLens
    @State private var focal: Double? = 10
    @State private var distance: Double? = 30
    @State private var height: Double? = 4
    @AppStorage("opticsUnit") private var unit = "cm"

    var body: some View {
        let result = compute()
        List {
            Section {
                if case .success(let image) = result, let focal, let distance, let height {
                    RayDiagram(kind: kind, focal: Optics.focalLength(kind, focal), distance: distance, height: height, image: image)
                        .frame(height: 260)
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }
                Picker("Element", selection: $kind) {
                    ForEach(Optics.Kind.allCases, id: \.self) { Text(Self.title($0)).tag($0) }
                }
                NumberInputField(title: "f (goriščna razdalja)", value: $focal)
                NumberInputField(title: "a (razdalja predmeta)", value: $distance)
                NumberInputField(title: "P (velikost predmeta)", value: $height)
                Picker("Enota dolžin", selection: $unit) {
                    Text("cm").tag("cm")
                    Text("m").tag("m")
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("1/f = 1/a + 1/b, M = |S|/P = |b|/a. Razpršilna leča in izbočeno zrcalo imata f < 0; predznak upošteva orodje samo. b > 0: realna slika (za lečo oziroma pred zrcalom), b < 0: navidezna. Žarki: vzporedni z osjo, skozi središče oziroma teme in skozi gorišče.")
            }
            results(result)
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
    }

    static func title(_ kind: Optics.Kind) -> String {
        switch kind {
        case .convergingLens: "Zbiralna leča"
        case .divergingLens: "Razpršilna leča"
        case .concaveMirror: "Vbočeno zrcalo"
        case .convexMirror: "Izbočeno zrcalo"
        }
    }

    private func compute() -> Result<Optics.Image, MathError> {
        guard let focal, let distance, let height else { return .failure(.incomplete) }
        do throws(MathError) {
            return .success(try Optics.image(kind: kind, focalLength: focal, objectDistance: distance, objectHeight: height))
        } catch {
            return .failure(error)
        }
    }

    @ViewBuilder
    private func results(_ result: Result<Optics.Image, MathError>) -> some View {
        switch result {
        case .success(let image):
            Section("Slika") {
                if image.isAtInfinity {
                    Label("Predmet je v gorišču: žarki gredo vzporedno, slika je v neskončnosti.", systemImage: "infinity")
                } else {
                    ResultRow(title: "b (razdalja slike)", value: image.distance, unit: unit)
                    ResultRow(title: "S (velikost slike)", value: image.height, unit: unit)
                    ResultRow(title: "Povečava M", value: Swift.abs(image.magnification))
                    LabeledContent("Slika", value: Self.nature(image))
                }
                if let focal {
                    let f = Optics.focalLength(kind, focal)
                    if kind.isMirror {
                        ResultRow(title: "Polmer ukrivljenosti R = 2f", value: 2 * f, unit: unit)
                    } else {
                        ResultRow(title: "Lomnost D = 1/f", value: unit == "cm" ? 100 / f : 1 / f, unit: "dpt")
                    }
                }
            }
        case .failure(let error):
            Section {
                Text(error == .incomplete ? "Vnesi f, a in P." : (error.errorDescription ?? error.shortDescription))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// "realna, obrnjena, pomanjšana"
    static func nature(_ image: Optics.Image) -> String {
        let m = Swift.abs(image.magnification)
        let size = Swift.abs(m - 1) < 1e-9 ? "enako velika" : (m > 1 ? "povečana" : "pomanjšana")
        return [image.isReal ? "realna" : "navidezna", image.isUpright ? "pokončna" : "obrnjena", size].joined(separator: ", ")
    }
}

/// The construction: the object P, the lens or mirror with its focal points, the three principal
/// rays and the image S; a virtual image and the backward extensions of the rays are dashed.
private struct RayDiagram: View {
    let kind: Optics.Kind
    /// The signed focal length.
    let focal: Double
    let distance: Double
    let height: Double
    let image: Optics.Image

    var body: some View {
        Canvas { context, size in
            // After a lens the light goes on to the right, after a mirror back to the left.
            let forward: Double = kind.isMirror ? -1 : 1
            let imageX = kind.isMirror ? -image.distance : image.distance
            let reach = 8 * Swift.max(distance, Swift.abs(focal))
            let showsImage = !image.isAtInfinity && Swift.abs(imageX) <= reach && Swift.abs(image.height) <= 12 * Swift.abs(height)
            let marks: [(x: Double, label: String)] = kind.isMirror
                ? [(-focal, "F"), (-2 * focal, "C")]
                : [(-Swift.abs(focal), "F"), (Swift.abs(focal), "F′"), (-2 * Swift.abs(focal), "2F"), (2 * Swift.abs(focal), "2F′")]
            var xs = [-distance, 0] + marks.map { $0.x }
            if showsImage { xs.append(imageX) }
            let low = xs.min()!, high = xs.max()!
            let padX = (high - low) * 0.08
            let minX = low - padX, maxX = high + padX
            let yMax = 1.35 * Swift.max(Swift.abs(height), showsImage ? Swift.abs(image.height) : 0)
            let left = 6.0, right = Double(size.width) - 6, midY = Double(size.height) / 2, halfH = Double(size.height) / 2 - 14
            func point(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: left + (x - minX) / (maxX - minX) * (right - left), y: midY - y / yMax * halfH)
            }
            func segment(_ a: CGPoint, _ b: CGPoint) -> Path {
                var path = Path()
                path.move(to: a)
                path.addLine(to: b)
                return path
            }
            let dashed = StrokeStyle(lineWidth: 1.2, dash: [5, 4])
            // The optical axis and the marked points.
            context.stroke(segment(CGPoint(x: left, y: midY), CGPoint(x: right, y: midY)), with: .color(.secondary), lineWidth: 1)
            for mark in marks {
                let p = point(mark.x, 0)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)), with: .color(.secondary))
                context.draw(Text(mark.label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary), at: CGPoint(x: p.x, y: p.y + 10))
            }
            drawElement(in: &context, top: point(0, 0.9 * yMax), bottom: point(0, -0.9 * yMax))
            // The object and the image.
            arrow(from: point(-distance, 0), to: point(-distance, height), color: .accentColor, dashed: false, label: "P", in: &context)
            if showsImage {
                arrow(from: point(imageX, 0), to: point(imageX, image.height), color: .red, dashed: !image.isReal, label: "S", in: &context)
            }
            // The rays: parallel to the axis, through the centre (vertex), through the focal point.
            let tip = point(-distance, height)
            let colors: [Color] = [.orange, .green, .purple]
            let edgeX = forward > 0 ? maxX : minX
            for (k, y) in [height, 0, image.height].enumerated() {
                if image.isAtInfinity && k == 2 { continue }
                guard y.isFinite else { continue }
                let hit = point(0, y)
                context.stroke(segment(tip, hit), with: .color(colors[k]), lineWidth: 1.5)
                // The direction after the element: towards a real image, away from a virtual one,
                // parallel to the reflected or straight central ray when the image is at infinity.
                let dx: Double, dy: Double
                if image.isAtInfinity {
                    dx = forward * distance
                    dy = -height
                } else if image.isReal {
                    dx = imageX
                    dy = image.height - y
                } else {
                    dx = -imageX
                    dy = y - image.height
                    context.stroke(segment(hit, point(imageX, image.height)), with: .color(colors[k].opacity(0.8)), style: dashed)
                }
                guard dx * forward > 0 else { continue }
                let t = (edgeX - 0) / dx
                context.stroke(segment(hit, point(edgeX, y + t * dy)), with: .color(colors[k]), lineWidth: 1.5)
            }
        }
        .clipped()
        .accessibilityLabel("Konstrukcija slike z žarki: " + OpticsToolView.title(kind))
    }

    /// A lens with its arrowheads (outwards: converging, inwards: diverging) or a mirror with
    /// hatching behind it, bent towards (concave) or away from (convex) the object.
    private func drawElement(in context: inout GraphicsContext, top: CGPoint, bottom: CGPoint) {
        let color = Color.primary
        if kind.isMirror {
            let bend = kind == .concaveMirror ? -7.0 : 7.0
            var mirror = Path()
            mirror.move(to: CGPoint(x: top.x + bend, y: top.y))
            mirror.addQuadCurve(to: CGPoint(x: bottom.x + bend, y: bottom.y), control: CGPoint(x: top.x - bend, y: (top.y + bottom.y) / 2))
            context.stroke(mirror, with: .color(color), lineWidth: 2.5)
            var hatch = Path()
            var y = top.y + 6
            while y < bottom.y - 2 {
                let t = (y - top.y) / (bottom.y - top.y)
                // The curve's x at this height (the quadratic Bézier with equal ends).
                let x = top.x + bend * (1 - 2 * 2 * t * (1 - t))
                hatch.move(to: CGPoint(x: x + 2, y: y))
                hatch.addLine(to: CGPoint(x: x + 8, y: y - 6))
                y += 9
            }
            context.stroke(hatch, with: .color(color.opacity(0.6)), lineWidth: 1)
        } else {
            var lens = Path()
            lens.move(to: top)
            lens.addLine(to: bottom)
            context.stroke(lens, with: .color(color), lineWidth: 2)
            let outwards = kind == .convergingLens
            for (end, sign) in [(top, -1.0), (bottom, 1.0)] {
                // Outwards the head points away from the axis; inwards it points back to it.
                let s = outwards ? sign : -sign
                var head = Path()
                head.move(to: CGPoint(x: end.x - 6, y: end.y - s * 7))
                head.addLine(to: end)
                head.addLine(to: CGPoint(x: end.x + 6, y: end.y - s * 7))
                context.stroke(head, with: .color(color), lineWidth: 2)
            }
        }
    }

    private func arrow(from a: CGPoint, to b: CGPoint, color: Color, dashed: Bool, label: String, in context: inout GraphicsContext) {
        var shaft = Path()
        shaft.move(to: a)
        shaft.addLine(to: b)
        context.stroke(shaft, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: dashed ? [5, 4] : []))
        let up = b.y < a.y ? -1.0 : 1.0
        var head = Path()
        head.move(to: b)
        head.addLine(to: CGPoint(x: b.x - 5, y: b.y - up * 9))
        head.addLine(to: CGPoint(x: b.x + 5, y: b.y - up * 9))
        head.closeSubpath()
        context.fill(head, with: .color(color))
        context.draw(Text(label).font(.caption.weight(.semibold)).foregroundStyle(color), at: CGPoint(x: b.x + 11, y: b.y))
    }
}
