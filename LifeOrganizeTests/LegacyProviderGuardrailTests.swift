import XCTest
@testable import LifeOrganize

final class LegacyProviderGuardrailTests: XCTestCase {
    func testAppTargetDoesNotReintroduceLegacyDirectProviderSymbols() throws {
        let combined = try appSwiftSources(excluding: ["Utilities/V1ScopeContract.swift"]).joined(separator: "\n")
        let legacySymbols = [
            "OpenAIClient",
            "OpenAIRequest",
            "OpenAIResponse",
            "OpenAIExtractionSchema",
            "OpenAIUserPayload",
            "APIKeyStore",
            "loadOpenAIAPIKey",
            "saveOpenAIAPIKey",
            "deleteOpenAIAPIKey",
            "screenshot-api-key"
        ]

        let offenders = legacySymbols.filter { combined.contains($0) }
        XCTAssertEqual(offenders, [])
    }

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func appSwiftSources(excluding excludedRelativePaths: Set<String>) throws -> [String] {
        try swiftFiles(in: projectRoot.appending(path: "LifeOrganize"))
            .filter { url in
                let relativePath = url.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
                return !excludedRelativePaths.contains(relativePath.replacingOccurrences(of: "LifeOrganize/", with: ""))
            }
            .map { try String(contentsOf: $0) }
    }

    private func swiftFiles(in directory: URL) throws -> [URL] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return try contents.flatMap { url -> [URL] in
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                return try swiftFiles(in: url)
            }
            return url.pathExtension == "swift" ? [url] : []
        }
    }
}
