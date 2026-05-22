import SwiftData
import SwiftUI

struct InternalQALabView: View {
    @Environment(\.debugAccessPolicy) private var debugAccessPolicy

    let apiKeyStore: any APIKeyStore

    var body: some View {
        Group {
            if debugAccessPolicy.allowsInternalQAScreens {
                List {
                    Section("State") {
                        NavigationLink {
                            QAFixtureCatalogView()
                        } label: {
                            Label("Load Fixtures", systemImage: "tray.and.arrow.down")
                        }

                        NavigationLink {
                            QADatabaseResetView()
                        } label: {
                            Label("Reset Local Database", systemImage: "trash")
                        }

                        NavigationLink {
                            QAFakeDateView()
                        } label: {
                            Label("Fake Date", systemImage: "calendar.badge.clock")
                        }

                        NavigationLink {
                            QATimelineJumpView()
                        } label: {
                            Label("Timeline Jump", systemImage: "calendar")
                        }
                    }

                    Section("Processing") {
                        NavigationLink {
                            QAReprocessEntryView(apiKeyStore: apiKeyStore)
                        } label: {
                            Label("Reprocess Entry", systemImage: "arrow.clockwise")
                        }

                        NavigationLink {
                            ExtractionDebugListView(apiKeyStore: apiKeyStore)
                        } label: {
                            Label("Extraction Attempts", systemImage: "list.bullet.rectangle")
                        }

                        NavigationLink {
                            ExtractionDebugListView(apiKeyStore: apiKeyStore, initialFilter: .failed)
                        } label: {
                            Label("Failed Extractions", systemImage: "exclamationmark.triangle")
                        }
                    }

                    Section("Inspection") {
                        NavigationLink {
                            QAGraphInspectorView()
                        } label: {
                            Label("Graph Inspector", systemImage: "point.3.connected.trianglepath.dotted")
                        }

                        NavigationLink {
                            QAExtractionQualityMetricsView()
                        } label: {
                            Label("Extraction Quality Dashboard", systemImage: "chart.bar.xaxis")
                        }
                    }
                }
            } else {
                DeveloperModeRequiredView(content: .internalQA)
            }
        }
        .navigationTitle("Internal QA Lab")
    }
}

struct QAFixtureCatalogView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var sessionState: AppSessionState

    @State private var resetBeforeLoad = false
    @State private var useRecommendedFakeDate = true
    @State private var statusText: String?

    private var descriptors: [QAFixtureDescriptor] {
        QAFixtureLoader(modelContext: modelContext).descriptors()
    }

    var body: some View {
        List {
            Section("Options") {
                Toggle("Reset database before load", isOn: $resetBeforeLoad)
                Toggle("Use fixture fake date", isOn: $useRecommendedFakeDate)
            }

            if let statusText {
                Section("Last Result") {
                    Text(statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(QAFixtureDescriptor.Category.allCases, id: \.self) { category in
                let categoryDescriptors = descriptors.filter { $0.category == category }
                if !categoryDescriptors.isEmpty {
                    Section(category.rawValue) {
                        ForEach(categoryDescriptors) { descriptor in
                            fixtureRow(descriptor)
                        }
                    }
                }
            }
        }
        .navigationTitle("Load Fixtures")
    }

    private func fixtureRow(_ descriptor: QAFixtureDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(descriptor.title)
                .font(.headline)
            Text(descriptor.summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(countText(descriptor.counts))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Load Fixture") {
                load(descriptor)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }

    private func load(_ descriptor: QAFixtureDescriptor) {
        do {
            if resetBeforeLoad {
                sessionState.invalidateInFlightDataWork()
            }
            let result = try QAFixtureLoader(modelContext: modelContext).load(
                descriptor,
                options: QAFixtureLoadOptions(resetBeforeLoad: resetBeforeLoad, applyRecommendedFakeDate: useRecommendedFakeDate)
            )
            if resetBeforeLoad {
                sessionState.reloadAfterLocalDataClear()
            }
            statusText = ([result.fixtureID, countText(result.insertedCounts)] + result.warnings).joined(separator: "\n")
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func countText(_ counts: QARecordCounts) -> String {
        "\(counts.sourceMessages) messages, \(counts.things) things, \(counts.events) events, \(counts.reminders) reminders, \(counts.notes) notes, \(counts.extractionAttempts) attempts"
    }
}

struct QADatabaseResetView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var sessionState: AppSessionState

    @State private var clearsFakeDate = true
    @State private var statusText: String?
    @State private var confirmsReset = false

    var body: some View {
        List {
            Section("Scope") {
                Toggle("Clear fake date", isOn: $clearsFakeDate)
            }

            Section {
                Button("Reset Local Database", role: .destructive) {
                    confirmsReset = true
                }
            }

            if let statusText {
                Section("Last Result") {
                    Text(statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Reset Database")
        .confirmationDialog("Reset local database?", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) {
                reset()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func reset() {
        do {
            sessionState.invalidateInFlightDataWork()
            try QADatabaseResetService(modelContext: modelContext).reset(options: QADatabaseResetOptions(clearsFakeDate: clearsFakeDate))
            sessionState.reloadAfterLocalDataClear()
            statusText = "Local QA database reset."
        } catch {
            statusText = error.localizedDescription
        }
    }
}

struct QAFakeDateView: View {
    @State private var draftText = ""
    @State private var statusText: String?
    private let store = QAFakeDateStore()

    var body: some View {
        List {
            Section("Effective Date") {
                Text(store.displayText(for: store.effectiveNow()))
                    .font(.body.monospacedDigit())
                if let override = store.overrideDate {
                    Text("Override: \(store.displayText(for: override))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Set Override") {
                TextField("2026-05-20T09:00:00-04:00", text: $draftText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Apply") {
                    apply()
                }
                Button("Clear Override", role: .destructive) {
                    store.clearOverride()
                    statusText = "Fake date cleared."
                }
            }

            if let statusText {
                Section("Last Result") {
                    Text(statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Fake Date")
    }

    private func apply() {
        do {
            let date = try store.parseOverride(draftText)
            store.setOverride(date)
            statusText = "Fake date set to \(store.displayText(for: date))."
        } catch {
            statusText = error.localizedDescription
        }
    }
}

struct QATimelineJumpView: View {
    private let fakeDateStore = QAFakeDateStore()

    var body: some View {
        let now = fakeDateStore.effectiveNow()
        let options = QATimelineJumpService(now: now).options()
        List(options) { option in
            NavigationLink {
                TimelineSliceReplayView(descriptor: option.descriptor, now: now)
            } label: {
                Label(option.title, systemImage: "calendar")
            }
        }
        .navigationTitle("Timeline Jump")
    }
}
