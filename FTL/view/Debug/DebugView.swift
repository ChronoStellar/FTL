//
//  DebugView.swift
//  FTL — view/Debug
//
//  A raw harness over the Google rails: hit Gmail, hit Sheets, see exactly what
//  comes back. Deliberately outside the architecture — it talks straight to the
//  services with no view model, because its whole job is to test the plumbing
//  before the pipeline exists to wrap it.
//
//  DEBUG builds only. The tab that hosts it is compiled out of Release.
//
//  Originally ContentView.swift — the Phase-0 feasibility screen.
//

import SwiftUI

struct DebugView: View {
    var body: some View {
        NavigationStack {
            DebugHarness()
                .navigationTitle("Debug")
        }
    }
}

private struct DebugHarness: View {
    @EnvironmentObject private var auth: GoogleAuthManager

    @State private var profile: GmailService.Profile?
    @State private var messages: [GmailService.Message] = []
    @State private var gmailQuery = ""
    @State private var status: String?

    // Expense entry state
    @State private var date = Date.now
    @State private var category = ""
    @State private var expenseDescription = ""
    @State private var amount = ""
    @State private var monthRows: [[String]] = []
    @State private var viewedMonth = Date.now

    var body: some View {
        List {
            Section("Account") {
                LabeledContent("Name", value: auth.name ?? "—")
                LabeledContent("Email", value: auth.email ?? "—")
                Button("Sign out", role: .destructive) { auth.signOut() }
            }

            Section("Gmail") {
                TextField("Filter (e.g. from:someone subject:invoice)", text: $gmailQuery)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("Load profile & recent mail") {
                    Task { await loadGmail() }
                }
                if let profile {
                    LabeledContent("Total messages", value: "\(profile.messagesTotal)")
                }
                ForEach(messages) { message in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(message.subject)
                                .font(.subheadline).bold().lineLimit(1)
                            Text(message.emailDate ?? "Unknown date")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let spending = message.spending {
                            Text(spending)
                                .font(.subheadline)
                                .foregroundStyle(.green)
                                .bold()
                        } else {
                            Text("—")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            Section("Add expense") {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                TextField("Category", text: $category)
                TextField("Description", text: $expenseDescription)
                TextField("Amount", text: $amount)
                    .keyboardType(.decimalPad)
                Button("Add to \(SheetsService.monthTabName(for: date))") {
                    Task { await addExpense() }
                }
                .disabled(category.isEmpty || Double(amount) == nil)
            }

            Section("Entries") {
                HStack {
                    Button { Task { await changeMonth(by: -1) } } label: {
                        Image(systemName: "chevron.left")
                    }
                    Spacer()
                    Text(SheetsService.monthTabName(for: viewedMonth)).bold()
                    Spacer()
                    Button { Task { await changeMonth(by: 1) } } label: {
                        Image(systemName: "chevron.right")
                    }
                }
                .buttonStyle(.borderless)

                if monthRows.isEmpty {
                    Text("No entries.").foregroundStyle(.secondary)
                }
                ForEach(Array(monthRows.enumerated()), id: \.offset) { _, row in
                    Text(row.joined(separator: " | "))
                        .font(.system(.footnote, design: .monospaced))
                }
            }
            .task { await loadMonth() }

            if let status {
                Section { Text(status).font(.footnote).foregroundStyle(.secondary) }
            }
        }
    }

    // MARK: Actions

    private func loadGmail() async {
        let service = GmailService(auth: auth)
        do {
            profile = try await service.profile()
            messages = try await service.recentMessages(maxResults: 10, query: gmailQuery.isEmpty ? "in:inbox" : gmailQuery)
            status = "Loaded \(messages.count) messages."
        } catch {
            status = error.localizedDescription
        }
    }

    private func addExpense() async {
        guard let amountValue = Double(amount) else {
            status = "Enter a valid amount."
            return
        }
        let service = SheetsService(auth: auth)
        let expense = SheetsService.Expense(
            date: date,
            category: category,
            description: expenseDescription,
            amount: amountValue
        )
        do {
            try await service.addExpense(expense)
            status = "Added \(category) to \(SheetsService.monthTabName(for: date))."
            category = ""
            expenseDescription = ""
            amount = ""
            viewedMonth = date // jump the viewer to the month we just added to
            await loadMonth()
        } catch {
            status = error.localizedDescription
        }
    }

    private func changeMonth(by months: Int) async {
        guard let newMonth = Calendar.current.date(byAdding: .month, value: months, to: viewedMonth) else { return }
        viewedMonth = newMonth
        await loadMonth()
    }

    private func loadMonth() async {
        let service = SheetsService(auth: auth)
        do {
            monthRows = try await service.readMonth(for: viewedMonth)
            status = "Loaded \(monthRows.count) entries for \(SheetsService.monthTabName(for: viewedMonth))."
        } catch {
            status = error.localizedDescription
        }
    }
}

#Preview {
    DebugView()
        .environmentObject(GoogleAuthManager.shared)
}
