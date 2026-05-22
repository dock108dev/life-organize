import Foundation

struct LedgerExportJSONDiffer {
    func differences(expected: JSONValue, actual: JSONValue) -> [LedgerExportDifference] {
        diff(expected: expected, actual: actual, path: "")
    }

    private func diff(expected: JSONValue, actual: JSONValue, path: String) -> [LedgerExportDifference] {
        switch (expected, actual) {
        case let (.object(expectedObject), .object(actualObject)):
            return diffObjects(expected: expectedObject, actual: actualObject, path: path)
        case let (.array(expectedArray), .array(actualArray)):
            return diffArrays(expected: expectedArray, actual: actualArray, path: path)
        default:
            guard expected == actual else {
                let kind: LedgerExportDifferenceKind = path == "/schemaVersion" ? .schemaMismatch : .valueMismatch
                return [difference(path: path, kind: kind, expected, actual)]
            }
            return []
        }
    }

    private func diffObjects(
        expected: [String: JSONValue],
        actual: [String: JSONValue],
        path: String
    ) -> [LedgerExportDifference] {
        let keys = Set(expected.keys).union(actual.keys).sorted()
        return keys.flatMap { key in
            let nextPath = path + "/" + key
            switch (expected[key], actual[key]) {
            case let (expectedValue?, actualValue?):
                return diff(expected: expectedValue, actual: actualValue, path: nextPath)
            case let (expectedValue?, nil):
                return [difference(path: nextPath, kind: .missingRecord, expectedValue, nil)]
            case let (nil, actualValue?):
                return [difference(path: nextPath, kind: .unexpectedRecord, nil, actualValue)]
            case (nil, nil):
                return []
            }
        }
    }

    private func diffArrays(expected: [JSONValue], actual: [JSONValue], path: String) -> [LedgerExportDifference] {
        if let expectedRecords = keyedRecords(expected), let actualRecords = keyedRecords(actual) {
            let keys = Set(expectedRecords.keys).union(actualRecords.keys).sorted()
            return keys.flatMap { key in
                let nextPath = path + key.selector
                switch (expectedRecords[key], actualRecords[key]) {
                case let (expectedValue?, actualValue?):
                    return diff(expected: expectedValue, actual: actualValue, path: nextPath)
                case let (expectedValue?, nil):
                    return [difference(path: nextPath, kind: .missingRecord, expectedValue, nil)]
                case let (nil, actualValue?):
                    return [difference(path: nextPath, kind: .unexpectedRecord, nil, actualValue)]
                case (nil, nil):
                    return []
                }
            }
        }

        let count = max(expected.count, actual.count)
        return (0..<count).flatMap { index in
            let nextPath = "\(path)/\(index)"
            if index >= expected.count {
                return [difference(path: nextPath, kind: .unexpectedRecord, nil, actual[index])]
            }
            if index >= actual.count {
                return [difference(path: nextPath, kind: .missingRecord, expected[index], nil)]
            }
            return diff(expected: expected[index], actual: actual[index], path: nextPath)
        }
    }

    private func keyedRecords(_ values: [JSONValue]) -> [RecordKey: JSONValue]? {
        var keyed: [RecordKey: JSONValue] = [:]
        for value in values {
            guard case .object(let object) = value, let key = recordKey(for: object), keyed[key] == nil else {
                return nil
            }
            keyed[key] = value
        }
        return keyed
    }

    private func recordKey(for object: [String: JSONValue]) -> RecordKey? {
        if case .string(let id)? = object["id"] {
            return RecordKey(name: "id", value: id)
        }
        if case .string(let key)? = object["key"] {
            return RecordKey(name: "key", value: key)
        }
        if case .string(let sourceType)? = object["sourceType"], case .string(let sourceId)? = object["sourceId"] {
            return RecordKey(name: "source", value: "\(sourceType):\(sourceId)")
        }
        return nil
    }

    private func difference(
        path: String,
        kind: LedgerExportDifferenceKind,
        _ expected: JSONValue?,
        _ actual: JSONValue?
    ) -> LedgerExportDifference {
        LedgerExportDifference(
            path: path.isEmpty ? "/" : path,
            kind: kind,
            expected: expected.map(describe),
            actual: actual.map(describe)
        )
    }

    private func describe(_ value: JSONValue) -> String {
        switch value {
        case .string(let text):
            text
        case .number(let number):
            String(number)
        case .bool(let bool):
            String(bool)
        case .null:
            "null"
        case .array, .object:
            String(data: value.encodedData, encoding: .utf8) ?? ""
        }
    }
}

private struct RecordKey: Hashable, Comparable {
    let name: String
    let value: String

    var selector: String { "[\(name)=\(value)]" }

    static func < (lhs: RecordKey, rhs: RecordKey) -> Bool {
        lhs.name == rhs.name ? lhs.value < rhs.value : lhs.name < rhs.name
    }
}
