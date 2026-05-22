import Foundation

enum LocalSearchNavigationResolvedKind: Equatable {
    case thing
    case event
    case rule
    case note
    case chatMessage
    case timelineSlice
    case missing
}

struct LocalSearchNavigationRecordStore {
    let things: [Thing]
    let events: [LedgerEvent]
    let rules: [LedgerRule]
    let notes: [LedgerNote]
    let messages: [ChatMessage]

    func resolvedKind(for target: LocalSearchNavigationTarget) -> LocalSearchNavigationResolvedKind {
        switch target {
        case .thingDetail(let id):
            things.contains { $0.id == id } ? .thing : .missing
        case .eventDetail(let id):
            events.contains { $0.id == id } ? .event : .missing
        case .ruleDetail(let id):
            rules.contains { $0.id == id } ? .rule : .missing
        case .noteDetail(let id):
            notes.contains { $0.id == id } ? .note : .missing
        case .chatMessage(let id):
            messages.contains { $0.id == id } ? .chatMessage : .missing
        case .timelineSlice:
            .timelineSlice
        }
    }
}
