import SwiftUI

struct ThingSelectionPicker: View {
    let title: String
    let things: [Thing]
    @Binding var selection: UUID?
    var includesNone = true

    private var sortedThings: [Thing] {
        things.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        Picker(title, selection: $selection) {
            if includesNone {
                Text("None").tag(nil as UUID?)
            }
            ForEach(sortedThings) { thing in
                Text(thing.name).tag(thing.id as UUID?)
            }
        }
    }
}
