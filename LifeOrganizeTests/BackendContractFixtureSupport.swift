import Foundation

private final class BackendContractFixtureBundleAnchor {}

func decodeContractFixture<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
    try JSONDecoder().decode(type, from: contractFixtureData(name))
}

func contractFixtureData(_ name: String) throws -> Data {
    if let bundledURL = Bundle(for: BackendContractFixtureBundleAnchor.self).url(
        forResource: name,
        withExtension: "json",
        subdirectory: "Fixtures/BackendContract"
    ) {
        return try Data(contentsOf: bundledURL)
    }

    let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let sourceURL = projectRoot
        .appending(path: "LifeOrganizeTests")
        .appending(path: "Fixtures")
        .appending(path: "BackendContract")
        .appending(path: "\(name).json")
    return try Data(contentsOf: sourceURL)
}
