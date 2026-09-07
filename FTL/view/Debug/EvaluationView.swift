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

            Section("Foundation Model (On-Device)") {
                if FoundationModelClassifier.isAvailable {
                    Text("SystemLanguageModel is ready.")
                        .font(.caption)
                        .foregroundStyle(.green)

                    HStack(spacing: 12) {
                        Button(isRunning ? "Running…" : "Test 5 samples") {
                            Task { await run(FoundationModelJudge(), limit: 5) }
                        }
                        .disabled(corpus == nil || isRunning)

                        Button(isRunning ? "Running…" : "Test 20 samples") {
                            Task { await run(FoundationModelJudge(), limit: 20) }
                        }
                        .disabled(corpus == nil || isRunning)
                    }
                } else {
                    Text("FoundationModels unavailable on this device/simulator. Requires Apple Intelligence on iOS 26+.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !progressText.isEmpty {
                    Text("Progress: \(progressText)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let report {
                Section("Result — \(report.judge)") {
                    LabeledContent("Coverage", value: "\(report.judged)/\(report.total)")
                    LabeledContent("Refused", value: "\(report.refused)")
                    if report.labelled > 0 {
                        LabeledContent("Accuracy", value: String(format: "%.0f%%", report.accuracy * 100))
                        LabeledContent("Honest rate", value: String(format: "%.0f%%", report.honestRate * 100))
                        LabeledContent("Confidently wrong", value: "\(report.confidentlyWrong)")
                    } else {
                        Text("No labels yet — accuracy needs labels.json in the bundle.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    LabeledContent("Median", value: "\(report.medianLatencyMs) ms")
                    ForEach(topSenders(report), id: \.0) { domain, stats in
                        LabeledContent(domain, value: "\(stats.judged)/\(stats.total)")
                            .font(.caption)
                    }
                }

                if !report.items.isEmpty {
                    Section("Sample Inspections (\(report.items.count))") {
                        ForEach(report.items) { item in
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: 8) {
                                    if let thinking = item.thinking, !thinking.isEmpty {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Label("Thinking Process", systemImage: "brain")
                                                .font(.caption).bold().foregroundStyle(.secondary)
                                            Text(thinking)
                                                .font(.footnote)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(8)
                                                .background(Color(.secondarySystemBackground))
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

    private func run(_ judge: EmailJudge, limit: Int? = nil) async {
        guard let corpus else { return }
        isRunning = true
        progressText = "Starting..."
        let result = await Evaluator(corpus: corpus).run(judge, limit: limit) { current, total in
            Task { @MainActor in
                progressText = "\(current) / \(total)"
            }
        }
        report = result
        reportURL = try? result.write()
        progressText = ""
        isRunning = false
    }

    private func topSenders(_ report: EvaluationReport) -> [(String, EvaluationReport.SenderStats)] {
        report.bySender.sorted { $0.value.total > $1.value.total }.prefix(5).map { ($0.key, $0.value) }
    }
}
