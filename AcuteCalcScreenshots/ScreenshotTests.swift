import UIKit
import XCTest

/// Screenshots of the app on a simulator, for the README and for agents that need to see the UI.
///
/// The app is launched once with the requested showcase scenes (`SCREENSHOT_SCENES` and
/// `SCREENSHOT_APPEARANCE`, see Showcase.swift) and a handshake directory (`SCREENSHOT_SYNC`, see
/// ShowcaseSync.swift). It shows one scene after another and reports when each has settled; the
/// test then captures the screen once two screenshots in a row agree, saves
/// `<scene>-<appearance>.png` to `SCREENSHOT_DIR` and lets the app go on. `scenes.json` there
/// lists the shots with their timings. The workflow passes these as `TEST_RUNNER_SCREENSHOT_*`.
final class ScreenshotTests: XCTestCase {
    private struct Shot: Decodable {
        var scene: String
        var appearance: String
        var name: String { "\(scene)-\(appearance)" }
    }

    private struct Plan: Decodable {
        var shots: [Shot]
        var error: String?
    }

    private struct Ready: Decodable {
        var seconds: Double
        var settled: Bool
        var problems: [String]?
    }

    private struct Record: Encodable {
        var name: String
        var scene: String
        var appearance: String
        var file: String
        /// Seconds the app needed to build the scene and settle.
        var settleSeconds: Double
        /// Seconds until two screenshots in a row agreed.
        var captureSeconds: Double
        /// False if the app was still busy, or the screen still changing, when the wait ran out.
        var settled: Bool
        var steady: Bool
        /// What the app could not build as asked (empty when the scene is as meant).
        var problems: [String]
        /// How long each screenshot took and how many thumbnail pixels changed between them.
        var screenshotSeconds: [Double]
        var changedPixels: [Int]
        /// Seconds spent drawing and encoding the PNG.
        var encodeSeconds: Double
        /// Seconds the first shot waited for the workflow to set the status bar.
        var statusBarWaitSeconds: Double?
    }

    @MainActor
    func testScreenshots() throws {
        let environment = ProcessInfo.processInfo.environment
        let output = URL(filePath: environment["SCREENSHOT_DIR"] ?? NSTemporaryDirectory(), directoryHint: .isDirectory)
        let sync = URL(filePath: environment["SCREENSHOT_SYNC"] ?? NSTemporaryDirectory() + "showcase-sync",
                       directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: sync)
        try FileManager.default.createDirectory(at: sync, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        XCUIDevice.shared.orientation = environment["SCREENSHOT_ORIENTATION"] == "portrait" ? .portrait : .landscapeLeft

        let app = XCUIApplication()
        app.launchEnvironment = [
            "ACUTE_SHOWCASE": environment["SCREENSHOT_SCENES"] ?? "all",
            "ACUTE_SHOWCASE_APPEARANCE": environment["SCREENSHOT_APPEARANCE"] ?? "both",
            "ACUTE_SHOWCASE_SYNC": sync.path,
        ]
        app.launch()
        let plan = try XCTUnwrap(read(Plan.self, from: sync.appending(path: "plan.json"), timeout: 120),
                                 "The app wrote no plan.json")
        if let error = plan.error { return XCTFail(error) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var records: [Record] = []
        for (index, shot) in plan.shots.enumerated() {
            // The first scene also waits for the cold launch and the GPU pipelines.
            let ready = try XCTUnwrap(read(Ready.self, from: sync.appending(path: "ready-\(index).json"), timeout: 180),
                                      "The app never showed \(shot.name)")
            var statusBarWait: Double?
            if index == 0, let statusBar = environment["SCREENSHOT_STATUS_BAR"] {
                // The workflow sets the status bar once the app is up and touches this file.
                let waitStart = Date()
                XCTAssertTrue(waitForFile(statusBar, timeout: 180), "The status bar was not set")
                statusBarWait = Date().timeIntervalSince(waitStart)
            }
            let start = Date()
            let capture = steadyScreenshot()
            let captureSeconds = Date().timeIntervalSince(start)
            try Data().write(to: sync.appending(path: "ack-\(index)"))
            // Encoded while the app builds the next scene.
            let encodeStart = Date()
            try uprightPNG(capture.screenshot.image).write(to: output.appending(path: "\(shot.name).png"))
            records.append(Record(name: shot.name, scene: shot.scene, appearance: shot.appearance, file: "\(shot.name).png",
                                  settleSeconds: ready.seconds, captureSeconds: captureSeconds,
                                  settled: ready.settled, steady: capture.steady, problems: ready.problems ?? [],
                                  screenshotSeconds: capture.seconds, changedPixels: capture.changed,
                                  encodeSeconds: Date().timeIntervalSince(encodeStart),
                                  statusBarWaitSeconds: statusBarWait))
            // After every shot, so a failed run still lists the ones it took.
            try encoder.encode(records).write(to: output.appending(path: "scenes.json"))
        }
        app.terminate()
    }

    /// The app's file decoded once it is there (nil after the timeout).
    private func read<Value: Decodable>(_ type: Value.Type, from url: URL, timeout: TimeInterval) -> Value? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(type, from: data) {
                return value
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return nil
    }

    /// True once the file exists (false after the timeout).
    private func waitForFile(_ path: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: path) { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    /// The screen once two screenshots in a row agree, so the last frame has reached the display;
    /// with the time each screenshot took and the pixels that changed between them.
    @MainActor
    private func steadyScreenshot(timeout: TimeInterval = 10)
        -> (screenshot: XCUIScreenshot, steady: Bool, seconds: [Double], changed: [Int]) {
        var seconds: [Double] = []
        var changed: [Int] = []
        func take() -> XCUIScreenshot {
            let start = Date()
            defer { seconds.append((Date().timeIntervalSince(start) * 100).rounded() / 100) }
            return XCUIScreen.main.screenshot()
        }
        var screenshot = take()
        var pixels = thumbnail(screenshot.image)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
            let next = take()
            let nextPixels = thumbnail(next.image)
            let difference = changedPixels(pixels, nextPixels)
            changed.append(difference)
            // At most 0.3 % of the pixels (a blinking caret stays below that).
            if difference * 1000 <= nextPixels.count / 4 * 3 { return (next, true, seconds, changed) }
            screenshot = next
            pixels = nextPixels
        }
        return (screenshot, false, seconds, changed)
    }

    /// The screenshot 192 pixels across, RGBA.
    private func thumbnail(_ image: UIImage) -> [UInt8] {
        guard let cgImage = image.cgImage, cgImage.width > 0 else { return [] }
        let width = 192
        let height = max(1, cgImage.height * width / cgImage.width)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return pixels
    }

    /// The thumbnail pixels that differ visibly (all of them if the sizes differ).
    private func changedPixels(_ a: [UInt8], _ b: [UInt8]) -> Int {
        guard !a.isEmpty, a.count == b.count else { return max(a.count, b.count) / 4 + 1 }
        var differing = 0
        for pixel in stride(from: 0, to: a.count, by: 4) {
            for channel in pixel..<pixel + 3 where abs(Int(a[channel]) - Int(b[channel])) > 32 {
                differing += 1
                break
            }
        }
        return differing
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
