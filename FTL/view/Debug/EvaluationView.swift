//
//  EvaluationView.swift
//  FTL — view/Debug · DEBUG only
//
//  Drives the evaluation harness from the device, because Foundation Models only
//  runs here. Writes a JSON report you can share out and aggregate in Python.
//
//  Deliberately outside the architecture — it talks straight to the harness with
//  no view model. It is a lab bench, not a screen.
//

import SwiftUI

struct EvaluationView: View {
    @State private var corpus: EmailCorpus?
    @State private var status = "Not loaded"
    @State private var report: EvaluationReport?
    @State private var reportURL: URL?
    @State private var isRunning = false
    @State private var progressText = ""
    @State private var languages: [(String, Int)] = []
    @State private var transactionStats: (currencyCount: Int, successPhraseCount: Int, bothCount: Int)?
    @State private var sampleFilter: SampleFilter = .all

    enum SampleFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case purchases = "Purchases"
        case rejected = "Rejected"
        var id: String { rawValue }
    }

    private var filteredItems: [ItemResult] {
        guard let report else { return [] }
        switch sampleFilter {
        case .all:
            return report.items
        case .purchases:
            return report.items.filter { $0.isPurchase }
        case .rejected:
            return report.items.filter { $0.refused }
        }
    }

    var body: some View {
        List {
            Section("Corpus") {
                Button("Load sample.json") { load() }
                Text(status).font(.footnote).foregroundStyle(.secondary)
                if let corpus {
                    LabeledContent("Emails", value: "\(corpus.emails.count)")
                    LabeledContent("Labelled", value: "\(corpus.labels.count)")
                    LabeledContent("Needing labels", value: "\(corpus.needingLabels().count)")
                }
            }

            // No model involved. Answers "what share of my receipts could the
            // classifier ever process?" before a line of model code is written.
            Section("Language gate — no model") {
                Button("Measure language mix") { measureLanguages() }
                    .disabled(corpus == nil)
                ForEach(languages.prefix(6), id: \.0) { code, count in
                    LabeledContent(code, value: "\(count)")
                }
            }

            Section("Transaction evidence — no model") {
                Button("Scan transaction markers (Rp, success phrases)") {
                    scanTransactionMarkers()
                }
                .disabled(corpus == nil)

                if let stats = transactionStats {
                    LabeledContent("Emails with currency (Rp / IDR)", value: "\(stats.currencyCount)")
                    LabeledContent("Emails with success phrases", value: "\(stats.successPhraseCount)")
                    LabeledContent("Likely transactions (both)", value: "\(stats.bothCount)")
                }
            }

            Section("Deterministic — blu parser") {
                Button(isRunning ? "Running…" : "Evaluate blu parser") {
                    Task { await run(ParserJudge(parser: BluReceiptParser())) }
                }
                .disabled(corpus == nil || isRunning)
            }


            if let report {
                Section("Result — \(report.judge)") {
                    LabeledContent("Total Evaluated", value: "\(report.total)")
                    LabeledContent("Purchases Identified", value: "\(report.items.filter { $0.isPurchase }.count)")
                    LabeledContent("Rejected by Rule", value: "\(report.refused)")
                    LabeledContent("Coverage", value: "\(report.judged)/\(report.total)")
                    if report.labelled > 0 {
                        LabeledContent("Accuracy", value: String(format: "%.0f%%", report.accuracy * 100))
                        LabeledContent("Honest rate", value: String(format: "%.0f%%", report.honestRate * 100))
                        LabeledContent("Confidently wrong", value: "\(report.confidentlyWrong)")
                    } else {
                        Text("No labels yet — accuracy needs labels.json in the bundle.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    LabeledContent("Median Latency", value: "\(report.medianLatencyMs) ms")
                    LabeledContent("p95 Latency", value: "\(report.p95LatencyMs) ms")
                    // Correlate these two against latency to find out what's
                    // actually driving the variance: tool calls (extra inference
                    // round trips) or output length (chosen by the model per
                    // email) — rather than guessing.
                    LabeledContent("Avg tool calls", value: String(format: "%.1f", report.averageToolCalls))
                    LabeledContent("Avg output chars", value: String(format: "%.0f", report.averageOutputCharacters))
                    // Each one is a row where the model's category disagreed with
                    // its own booleans, or named a category TagStore doesn't know
                    // — exactly the pattern that silently dropped the refund.
                    LabeledContent("Category flags", value: "\(report.categoryFlagCount)")
                }

                Section("Sender Breakdown (\(report.bySender.count) senders)") {
                    ForEach(report.bySender.sorted { $0.value.total > $1.value.total }, id: \.key) { domain, stats in
                        LabeledContent(domain.isEmpty ? "unknown" : domain, value: "\(stats.judged) judged / \(stats.total) total")
                            .font(.caption)
                    }
                }

                if !report.items.isEmpty {
                    Section {
                        Picker("Filter Samples", selection: $sampleFilter) {
                            Text("All (\(report.items.count))").tag(SampleFilter.all)
                            Text("Purchases (\(report.items.filter { $0.isPurchase }.count))").tag(SampleFilter.purchases)
                            Text("Rejected (\(report.items.filter { $0.refused }.count))").tag(SampleFilter.rejected)
                        }
                        .pickerStyle(.segmented)
                        .padding(.vertical, 4)

                        ForEach(filteredItems) { item in
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: 8) {
                                    if let thinking = item.thinking, !thinking.isEmpty {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Label(item.refused ? "Rule Pre-Filter Verdict" : "Thinking Process", systemImage: item.refused ? "shield.slash" : "brain")
                                                .font(.caption).bold().foregroundStyle(item.refused ? .orange : .secondary)
                                            Text(thinking)
                                                .font(.footnote)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(8)
                                                .background(item.refused ? Color.orange.opacity(0.08) : Color(.secondarySystemBackground))
                                                .cornerRadius(8)
                                        }
                                    }

                                    if !item.taggedKeywords.isEmpty {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Label("Tagged Keywords / Evidence", systemImage: "tag")
                                                .font(.caption).bold().foregroundStyle(.secondary)
                                            HStack(spacing: 6) {
                                                ForEach(item.taggedKeywords, id: \.self) { kw in
                                                    Text(kw)
                                                        .font(.caption2).bold()
                                                        .padding(.horizontal, 6).padding(.vertical, 3)
                                                        .background(Color.blue.opacity(0.12))
                                                        .foregroundStyle(.blue)
                                                        .cornerRadius(4)
                                                }
                                            }
                                        }
                                    }

                                    LabeledContent("Date", value: item.date)
                                    if let sp = item.serviceProvider {
                                        LabeledContent("Service Provider (Rail)", value: sp)
                                    }
                                    if let merchant = item.merchant {
                                        LabeledContent("Merchant (Shop)", value: merchant)
                                    }
                                    if let type = item.transactionType {
                                        LabeledContent("Category", value: type)
                                    }
                                    if let amount = item.amount {
                                        LabeledContent("Amount", value: amount)
                                    }
                                    LabeledContent("Latency", value: "\(item.latencyMs) ms")
                                }
                                .padding(.vertical, 4)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text(item.date)
                                                .font(.caption2).bold()
                                                .foregroundStyle(.secondary)
                                            if let sp = item.serviceProvider {
                                                Text("•  \(sp)")
                                                    .font(.caption2)
                                                    .foregroundStyle(.blue)
                                            }
                                        }
                                        Text(item.subject.isEmpty ? "(No Subject)" : item.subject)
                                            .font(.subheadline).bold().lineLimit(1)
                                        Text(item.from)
                                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    if item.refused {
                                        Text("Rejected (No Rp)")
                                            .font(.caption2).bold()
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Color.orange.opacity(0.15))
                                            .foregroundStyle(.orange)
                                            .cornerRadius(4)
                                    } else {
                                        Text(item.isPurchase ? (item.transactionType ?? "Purchase") : "Not a Purchase")
                                            .font(.caption2).bold()
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(item.isPurchase ? Color.green.opacity(0.15) : Color.gray.opacity(0.15))
                                            .foregroundStyle(item.isPurchase ? .green : .secondary)
                                            .cornerRadius(4)
                                    }
                                }
                            }
                        }
                    }
                }
                if let reportURL {
                    Section {
                        ShareLink(item: reportURL) { Label("Share report JSON", systemImage: "square.and.arrow.up") }
                    }
                }
            }
        }
        .navigationTitle("Evaluation")
    }

    // MARK: - Actions

    private func load() {
        do {
            let loaded = try EmailCorpus.load()
            corpus = loaded
            status = "Loaded \(loaded.emails.count) emails, \(loaded.labels.count) labels."
        } catch {
            status = error.localizedDescription
        }
    }

    private func measureLanguages() {
        guard let corpus else { return }
        languages = DefaultLanguageGate.languageBreakdown(corpus.emails)
            .sorted { $0.value > $1.value }
            .map { ($0.key, $0.value) }
    }

    private func scanTransactionMarkers() {
        guard let corpus else { return }
        var currencyCount = 0
        var successPhraseCount = 0
        var bothCount = 0
        for email in corpus.emails {
            let evidence = TransactionMarkerDetector.detect(in: email.searchText)
            if evidence.hasCurrency { currencyCount += 1 }
            if evidence.hasSuccessPhrase { successPhraseCount += 1 }
            if evidence.isLikelyTransaction { bothCount += 1 }
        }
        transactionStats = (currencyCount, successPhraseCount, bothCount)
    }

    private func run(_ judge: EmailJudge, limit: Int? = nil, filterCurrency: Bool = false) async {
        guard let corpus else { return }
        isRunning = true
        progressText = "Starting..."
        let result = await Evaluator(corpus: corpus).run(judge, limit: limit, filterCurrency: filterCurrency) { current, total in
            Task { @MainActor in
                progressText = "\(current) / \(total)"
            }
        }
        report = result
        reportURL = try? result.write()
        progressText = ""
        isRunning = false
    }

}
