import SwiftData
import SwiftUI

struct QAExtractionQualityMetricsView: View {
    @Environment(\.debugAccessPolicy) private var debugAccessPolicy
    @Environment(\.modelContext) private var modelContext

    @State private var snapshot: QAExtractionQualityMetricsSnapshot?
    @State private var errorText: String?

    var body: some View {
        Group {
            if debugAccessPolicy.allowsInternalQAScreens {
                dashboardContent
            } else {
                DeveloperModeRequiredView(content: .internalQA)
            }
        }
        .navigationTitle("Quality Dashboard")
        .task {
            if snapshot == nil {
                refresh()
            }
        }
    }

    private var dashboardContent: some View {
        List {
            Section {
                Button("Refresh Metrics") {
                    refresh()
                }
                Text("Internal proxy metrics from local records and deterministic fixtures. These are not ground-truth precision, recall, or user analytics.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: LedgerAdaptiveLayout.Width.debugDetailMax, alignment: .leading)
            }

            if let errorText {
                Section("Error") {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: LedgerAdaptiveLayout.Width.debugDetailMax, alignment: .leading)
                }
            }

            if let snapshot {
                extractionOverview(snapshot.extraction)
                attemptReliability(snapshot.extraction)
                reviewQuality(snapshot.reviews)
                entityLinkHealth(snapshot.entityLinks)
            } else {
                Section {
                    ContentUnavailableView("No Metrics Loaded", systemImage: "chart.bar.xaxis")
                }
            }
        }
    }

    private func extractionOverview(_ metrics: QAExtractionPipelineMetrics) -> some View {
        Section("Extraction Overview") {
            metricRow("User messages", metrics.userMessageCount)
            metricRow("Extraction candidate messages", metrics.candidateMessageCount)
            metricRow("Attempted messages", metrics.attemptedMessageCount)
            metricRow("Attempt coverage", metrics.attemptCoverage)
            metricRow("Strict success rate", metrics.strictMessageSuccessRate)
            metricRow("Operational success rate", metrics.operationalMessageSuccessRate)
            metricRow("Attention burden", metrics.attentionBurdenRate)
            metricRow("Retry rate", metrics.retryRate)
            metricRow("Persisted entity volume proxy", metrics.persistedEntityCandidateVolume)
            metricRow("Deterministic attempts", metrics.deterministicAttemptCount)
            metricRow("AI attempts", metrics.aiAttemptCount)
        }
    }

    @ViewBuilder
    private func attemptReliability(_ metrics: QAExtractionPipelineMetrics) -> some View {
        Section("Attempt Reliability") {
            metricRow("Strict attempt success", metrics.strictAttemptSuccessRate)
            metricRow("Operational attempt success", metrics.operationalAttemptSuccessRate)
            metricRow("Retry due", metrics.retryDueCount)
            metricRow("Retry not due", metrics.retryNotDueCount)
            metricRow("Retry missing schedule", metrics.retryMissingScheduleCount)
            metricRow("Latency samples", metrics.latency.sampleCount)
            DebugMetadataRow(label: "Average latency", value: seconds(metrics.latency.averageSeconds))
            DebugMetadataRow(label: "p50 latency", value: seconds(metrics.latency.p50Seconds))
            DebugMetadataRow(label: "p95 latency", value: seconds(metrics.latency.p95Seconds))
            DebugMetadataRow(label: "Max latency", value: seconds(metrics.latency.maxSeconds))
            metricRow("Invalid timing", metrics.latency.invalidTimingCount)
        }

        Section("Extraction Status Distribution") {
            breakdownRows(metrics.messageStatusDistribution)
        }

        Section("Attempt Status Distribution") {
            breakdownRows(metrics.attemptStatusDistribution)
        }

        if !metrics.attemptErrorDistribution.isEmpty {
            Section("Attempt Error Distribution") {
                breakdownRows(metrics.attemptErrorDistribution)
            }
        }
    }

    @ViewBuilder
    private func reviewQuality(_ metrics: QAReviewQualityMetrics) -> some View {
        Section("Review Quality Proxies") {
            metricRow("Review items", metrics.totalReviewItems)
            metricRow("Review rate proxy", metrics.reviewRate)
            metricRow("Open reviews", metrics.openReviewCount)
            metricRow("Resolved reviews", metrics.resolvedReviewCount)
            metricRow("Failed review actions", metrics.failedReviewActionCount)
            metricRow("Duplicate Thing reviews", metrics.duplicateThingReviewCount)
            metricRow("Normalization candidate reviews", metrics.normalizationCandidateReviewCount)
            metricRow("Temporal review volume", metrics.temporalReviewCount)
            metricRow("Failed temporal signals", metrics.failedTemporalInterpretationSignals)
            metricRow("Review acceptance proxy", metrics.reviewAcceptanceProxy)
        }

        Section("Open Reviews By Kind") {
            breakdownRows(metrics.openReviewCountsByKind)
        }

        Section("Resolved Reviews By Kind") {
            breakdownRows(metrics.resolvedReviewCountsByKind)
        }

        Section("Review State Distribution") {
            breakdownRows(metrics.reviewStateDistribution)
        }
    }

    @ViewBuilder
    private func entityLinkHealth(_ metrics: QAEntityLinkQualityMetrics) -> some View {
        Section("Entity Link Health") {
            metricRow("Graph nodes", metrics.nodeCount)
            metricRow("Links", metrics.linkCount)
            DebugMetadataRow(label: "Graph density", value: decimal(metrics.graphDensity))
            metricRow("Extraction-created links", metrics.extractionCreatedLinkCount)
            metricRow("Extraction link coverage", metrics.extractionCreatedLinkCoverage)
            DebugMetadataRow(label: "Average link confidence", value: decimal(metrics.averageLinkConfidence))
            metricRow("Low-confidence link rate", metrics.lowConfidenceLinkRate)
            metricRow("Invalid link confidence", metrics.invalidConfidenceCount)
            metricRow("Orphan-like link patterns", metrics.orphanLikeFailureCount)
        }

        Section("Link Confidence Distribution") {
            breakdownRows(metrics.linkConfidenceDistribution)
        }

        Section("Links By Creator") {
            breakdownRows(metrics.linkCountsByCreator)
        }

        Section("Links By Relation") {
            breakdownRows(metrics.linkCountsByRelation)
        }

        if !metrics.orphanLikeFailuresByCode.isEmpty {
            Section("Orphan-Like Patterns") {
                breakdownRows(metrics.orphanLikeFailuresByCode)
            }
        }
    }

    private func breakdownRows(_ rows: [QACountBreakdown]) -> some View {
        Group {
            if rows.isEmpty {
                Text("None")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rows) { row in
                    metricRow(row.label, row.count)
                }
            }
        }
    }

    private func metricRow(_ label: String, _ count: Int) -> some View {
        DebugMetadataRow(label: label, value: "\(count)")
    }

    private func metricRow(_ label: String, _ rate: QARateMetric) -> some View {
        DebugMetadataRow(label: label, value: percentage(rate))
    }

    private func refresh() {
        do {
            snapshot = try QAExtractionQualityMetricsService(
                modelContext: modelContext,
                now: QAFakeDateStore().effectiveNow()
            ).snapshot()
            errorText = nil
        } catch {
            snapshot = nil
            errorText = error.localizedDescription
        }
    }

    private func percentage(_ rate: QARateMetric) -> String {
        guard let value = rate.value else {
            return "\(rate.numerator)/\(rate.denominator) -"
        }
        return "\(rate.numerator)/\(rate.denominator) \(Self.percentFormatter.string(from: NSNumber(value: value)) ?? "-")"
    }

    private func seconds(_ value: Double?) -> String {
        guard let value else { return "-" }
        return String(format: "%.2fs", value)
    }

    private func decimal(_ value: Double?) -> String {
        guard let value else { return "-" }
        return String(format: "%.2f", value)
    }

    private static let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 1
        return formatter
    }()
}
