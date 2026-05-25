import XCTest

final class UITestNetworkBoundaryGuardrailTests: XCTestCase {
    func testUITestLaunchArgumentBlocksUseDeterministicExtractionOrScreenshotMode() throws {
        let uiTestFiles = try swiftFiles(in: "LifeOrganizeUITests")

        for fileURL in uiTestFiles {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let launchArgumentBlocks = source.launchArgumentArrayBlocks()

            for block in launchArgumentBlocks {
                XCTAssertTrue(
                    block.contains(#""-use-fake-extractor""#) || block.contains(#""-screenshot-mode""#),
                    "UI test launch arguments must avoid live backend calls in \(fileURL.lastPathComponent): \(block)"
                )
            }
        }
    }

    func testRoutineUITestsLaunchThroughSharedHelper() throws {
        let allowedManualLaunchFiles: Set<String> = [
            "UITestSupport.swift",
            "LifeOrganizeScreenshotTests.swift",
            "LifeOrganizeUITests+ScreenshotMode.swift"
        ]
        let uiTestFiles = try swiftFiles(in: "LifeOrganizeUITests")

        for fileURL in uiTestFiles where !allowedManualLaunchFiles.contains(fileURL.lastPathComponent) {
            let source = try String(contentsOf: fileURL, encoding: .utf8)

            XCTAssertFalse(
                source.contains("XCUIApplication()"),
                "Routine UI tests must launch through launchUITestApp(...) in \(fileURL.lastPathComponent)."
            )
        }
    }

    func testUnitTestsDoNotConstructDefaultLiveAIServiceClient() throws {
        let unitTestFiles = try swiftFiles(in: "LifeOrganizeTests")

        for fileURL in unitTestFiles {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let defaultClientPattern = #"AIServiceClient\s*\(\s*deviceToken\s*:[^,\)]*\)"#
            XCTAssertNil(
                source.range(of: defaultClientPattern, options: .regularExpression),
                "Unit tests must inject an AIServiceHTTPSession in \(fileURL.lastPathComponent)."
            )
        }
    }

    private func swiftFiles(in relativePath: String) throws -> [URL] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appendingPathComponent(relativePath)
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil
        )
        return (enumerator?.compactMap { $0 as? URL } ?? [])
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.path < $1.path }
    }
}

private extension String {
    func launchArgumentArrayBlocks() -> [String] {
        var blocks: [String] = []
        let lines = components(separatedBy: .newlines)
        var current: [String] = []
        var isCapturing = false

        for line in lines {
            if !isCapturing && line.contains("app.launchArguments = [") {
                isCapturing = true
                current = [line]
                if line.contains("]") {
                    blocks.append(current.joined(separator: "\n"))
                    isCapturing = false
                }
                continue
            }

            guard isCapturing else { continue }
            current.append(line)
            if line.contains("]") {
                blocks.append(current.joined(separator: "\n"))
                isCapturing = false
            }
        }

        return blocks
    }
}
