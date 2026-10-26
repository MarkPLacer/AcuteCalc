import UIKit
import XCTest

/// README screenshots on the iPad simulator: every showcase scene of the app (Showcase.swift,
/// Debug builds) in landscape, dark and light. The PNG files go to `SCREENSHOT_DIR` (the
/// workflow passes `TEST_RUNNER_SCREENSHOT_DIR`) and are attached to the test result too.
final class ScreenshotTests: XCTestCase {
    private let scenes = ["graphs", "analysis", "calculator", "surface", "complex", "tools", "formulas"]

    @MainActor
    func testScreenshots() throws {
        let path = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] ?? NSTemporaryDirectory()
        let directory = URL(filePath: path, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        XCUIDevice.shared.orientation = .landscapeLeft
        var coldStart = true
        for appearance in ["dark", "light"] {
            for scene in scenes {
                let app = XCUIApplication()
                app.launchEnvironment = ["ACUTE_SHOWCASE": scene, "ACUTE_SHOWCASE_APPEARANCE": appearance]
                app.launch()
                // The app builds the scene and frames the graph; then the renderers settle. The
                // first launch also compiles the GPU pipelines.
                sleep(coldStart ? 30 : 15)
                coldStart = false
                let screenshot = XCUIScreen.main.screenshot()
                let name = "\(scene)-\(appearance)"
                try uprightPNG(screenshot.image).write(to: directory.appending(path: "\(name).png"))
                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = name
                attachment.lifetime = .keepAlways
                add(attachment)
                app.terminate()
            }
        }
    }

    /// PNG data drawn upright: a landscape screenshot keeps the screen's portrait pixels and only
    /// a rotation flag, which the image's own PNG data would lose.
    @MainActor
    private func uprightPNG(_ image: UIImage) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: image.size, format: format).pngData { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
