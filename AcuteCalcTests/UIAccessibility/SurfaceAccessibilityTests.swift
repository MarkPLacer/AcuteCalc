import AcuteCore
import CoreGraphics
import Testing
@testable import AcuteCalc

/// apis:2: the 3D view and the ℂ plane are Metal views with drawn numbers, so VoiceOver found only the legend
/// words. Each now has one element: the function and its ranges, for the 3D view also the camera, which VoiceOver
/// can turn, raise, lower, zoom and reset without the gestures.
@MainActor
@Suite struct SurfaceAccessibilityTests {
    let style = MathStyle(decimalSeparator: ",")

    @Test func aHeightFieldNamesItsFunctionAndRanges() {
        let model = SurfaceModel()
        model.setFunction(.variable("x"))
        #expect(SurfaceAccessibility.title(model.kind) == "Prostorski graf")
        // z = x on ±4: the z range is sampled (2 % and 98 %) and padded by 5 % on each side.
        #expect(SurfaceAccessibility.summary(model, style: style) == "z = x; x od −4 do 4; y od −4 do 4; z od −4,4 do 4,4")
    }

    @Test func anImplicitSurfaceReadsAsAnEquationWithoutAZRange() throws {
        let sphere = try Parser.parse("x^2+y^2+z^2-4")
        let model = SurfaceModel()
        model.setFunction(sphere)
        try #require(model.kind == .implicit)
        let f = MathAccessibility.label(MathRowConverter.row(for: sphere), style: style)
        #expect(SurfaceAccessibility.summary(model, style: style) == "\(f) = 0; x od −4 do 4; y od −4 do 4")
    }

    @Test func aSolidOfRevolutionGivesItsRadius() throws {
        let model = SurfaceModel()
        model.kind = .revolution
        let two = try Parser.parse("2")
        model.setFunction(two)
        let f = MathAccessibility.label(MathRowConverter.row(for: two), style: style)
        // r = 2 everywhere: the radius itself, not the top of the z range, which is padded by 5 % of its width (2,2).
        #expect(SurfaceAccessibility.summary(model, style: style) == "vrtenina krivulje y = \(f) okoli osi x; x od −4 do 4; polmer do 2")
    }

    @Test func aSolidOfRevolutionWithoutFiniteSamplesGivesNoRadius() {
        let model = SurfaceModel()
        model.kind = .revolution
        // ln x is undefined for every x in [−4, −1]: there is no radius to read.
        model.domain = SIMD4(-4, -1, -4, 4)
        let lnx = Expr.function(.ln, [.variable("x")])
        model.setFunction(lnx)
        let f = MathAccessibility.label(MathRowConverter.row(for: lnx), style: style)
        #expect(SurfaceAccessibility.summary(model, style: style) == "vrtenina krivulje y = \(f) okoli osi x; x od −4 do −1")
    }

    @Test func aFixedZRangeReadsNoRadiusOfAnEarlierFunction() throws {
        let model = SurfaceModel()
        model.kind = .revolution
        let two = try Parser.parse("2")
        model.setFunction(two)
        let earlier = try #require(model.sampledRadius)
        #expect(earlier == 2)
        model.autoZ = false
        let three = try Parser.parse("3")
        model.setFunction(three)
        let f = MathAccessibility.label(MathRowConverter.row(for: three), style: style)
        // With a fixed z range nothing samples y = 3, so VoiceOver reads no radius, not the 2 of y = 2.
        #expect(SurfaceAccessibility.summary(model, style: style) == "vrtenina krivulje y = \(f) okoli osi x; x od −4 do 4")
    }

    @Test func aComplexLandscapeSaysWhatItsHeightIs() {
        let model = SurfaceModel()
        model.kind = .complexReal
        model.setFunction(.variable("z"))
        #expect(SurfaceAccessibility.title(model.kind) == "Kompleksna pokrajina")
        #expect(SurfaceAccessibility.summary(model, style: style)
                == "realni del funkcije f(z) = z; Re z od −4 do 4; Im z od −4 do 4; višina od −4,4 do 4,4")
        #expect(SurfaceAccessibility.summary(SurfaceModel(), style: style) == "Brez funkcije")
    }

    @Test func cameraStepsAreReadInDegrees() {
        let model = SurfaceModel()
        #expect(SurfaceAccessibility.camera(model) == "zasuk 43°, naklon 32°, povečava 100 %")
        model.turn(yaw: SurfaceAccessibility.step, pitch: SurfaceAccessibility.step)
        model.zoom(by: 1.25)
        #expect(SurfaceAccessibility.camera(model) == "zasuk 58°, naklon 47°, povečava 125 %")
        model.resetCamera()
        model.turn(yaw: -.pi, pitch: .pi)
        // Half a turn back reads 223°, not −137°; the camera stops above the box at 1.45 rad, as a drag does.
        #expect(SurfaceAccessibility.camera(model) == "zasuk 223°, naklon 83°, povečava 100 %")
    }

    @Test func theComplexPlaneNamesItsFunctionAndTheVisibleRectangle() {
        let viewport = GraphViewport(center: .zero, scale: SIMD2(60, 60), size: CGSize(width: 360, height: 240))
        #expect(ComplexPlotAccessibility.summary(expression: .variable("z"), viewport: viewport, style: style)
                == "f(z) = z; Re z od −3 do 3; Im z od −2 do 2")
        #expect(ComplexPlotAccessibility.summary(expression: nil, viewport: viewport, style: style) == "Brez funkcije")
        #expect(ComplexPlotAccessibility.readout(z: Complex(0, 0), w: Complex(1, 0), style: style) == "z = 0, f(z) = 1")
        #expect(ComplexPlotAccessibility.readout(z: Complex(0, 0), w: Complex(.infinity, 0), style: style) == "z = 0, f(z) = ∞")
    }

    @Test func theComplexPlaneResetsToItsStartView() {
        let model = ComplexPlotModel()
        let start = model.viewport
        model.viewport.zoom(by: SIMD2(2, 2), around: CGPoint(x: 10, y: 20))
        model.viewport.pan(byPoints: CGSize(width: 30, height: -40))
        model.resetView()
        #expect(model.viewport == start)
    }
}
