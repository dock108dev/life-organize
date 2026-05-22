import SwiftUI
import UIKit

struct DebugTextViewer: View {
    let title: String
    let text: String?
    var emptyDescription: String = "This extraction attempt did not store this payload."

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(title)
                        .font(.headline)
                    Spacer()
                    if let text, !text.isEmpty {
                        Button("Copy") {
                            UIPasteboard.general.string = text
                        }
                    }
                }

                if let text, !text.isEmpty {
                    Text("\(text.count) characters")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(text)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ContentUnavailableView(
                        "No \(title)",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(emptyDescription)
                    )
                }
            }
            .padding()
        }
    }
}

struct DebugJSONViewer: View {
    let title: String
    let jsonText: String

    private var prettyJSON: String? {
        guard let data = jsonText.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        else {
            return nil
        }
        return String(data: prettyData, encoding: .utf8)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(prettyJSON == nil && !jsonText.isEmpty ? "Invalid JSON · showing stored text" : "Valid JSON")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top)

            DebugTextViewer(title: title, text: prettyJSON ?? jsonText)
        }
    }
}
