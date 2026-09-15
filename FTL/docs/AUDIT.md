# FTL Codebase Audit: Deprecated, Unused & Dead Components

**Date:** 2026-09-11  
**Target:** FTL iOS App (`ChronoStellar/FinanceTrackerLite`)

---

## Executive Summary

This audit identifies components, files, and data structures across the FTL codebase that are no longer useful, are obsolete remnants of earlier prototypes, or represent dead code. 

Key highlights:
1. **Critical Bundle Bloat & Privacy:** ~82 MB of raw email data (`sample.json` and `gmail_export.json`) plus Python scripts are currently bundled into the shipping `.app` binary due to Xcode's synchronized folder group.
2. **Unpersisted Feature:** The entire Savings Goal stack (`SavingsGoal`, `GoalStore`, `GoalViewModel`, `GoalDetailView`, `GoalCard`) was a design canvas addition not in spec v0.6, is backed only by an in-memory empty mock, and is never visible to live users.
3. **Phase-0 Prototype Remnants:** Legacy month-tab expense tracking (`LegacyMigration`, `GmailService`, monthly tab methods in `SheetsService`) are superseded by `SheetsSchema`, `SheetsLedgerStore`, and `GmailExporter`.
4. **Dead / Unwired Phase-2 Model Stubs:** `ResultReasoner` (query box), `PurchaseClassifier`, and startup `TagStore.reconcile()` do not run in production.

---

## 1. Shipping Bundle Bloat & Test Corpora

The Xcode target uses a **file-system synchronized root group** on `FTL/`. Every file inside `FTL/` is automatically packaged into the built application bundle unless explicitly excluded.

| File | Size | Issue / Reason for Deprecation |
|---|---|---|
| `FTL/test/gmail_export.json` | **75 MB** | Real email export with intact `bodyHtml`. Intended for offline testing/evaluation, but currently ships inside the app bundle. |
| `FTL/test/sample.json` | **6.6 MB** | Outdated export with HTML bodies stripped. Caused misleading parser metrics (116/116 on snippets, failing on real bodies). Superseded by `gmail_export.json`. |
| `FTL/test/strip_body_html.py` | 3.2 KB | Python utility script used once offline. Shipped in `.app`. |
| `FTL/test/ftl-ledger-rows.tsv` | 29 KB | Static TSV dump shipped in `.app`. |

### Action:
- Move the entire `test/` folder outside of `FTL/` (e.g., to repository root `/test/`), or add a build rule / `.gitignore` / `membershipExceptions` entry in `FTL.xcodeproj`.
- Delete `sample.json` entirely.

---

## 2. Out-of-Scope & Unpersisted Feature: Savings Goal

* **Domain & Contract:** `FTL/model/Domain/SavingsGoal.swift`, `FTL/model/Contracts/GoalStore.swift`
* **View & ViewModel:** `FTL/view/Goal/GoalDetailView.swift`, `FTL/viewModel/GoalViewModel.swift`, `GoalCard` in `FTL/view/Home/HomeCards.swift`
* **App Environment & Navigation:** `AppEnvironment.goals`, `Screens.swift`

### Context & Evidence:
* Documented in `CLAUDE.md` and `ROADMAP.md` as an unrequested scope deviation from the HTML design canvas.
* There is no Google Sheets tab (`SheetsSchema` has only `transactions` and `budgets`), and no SwiftData table.
* In production (`AppEnvironment.live()`), `goals` is injected as `InMemoryGoalStore(empty: true)`.
* In `HomeView.swift`: `if let goal = viewModel.goal { GoalCard(...) }` never displays anything for real users, and `GoalDetailView` is unreachable.

### Action:
- Remove `SavingsGoal.swift`, `GoalStore.swift`, `GoalViewModel.swift`, `GoalDetailView.swift`, and `GoalCard`.
- Clean up references in `AppEnvironment.swift` and `HomeViewModel.swift`.

---

## 3. Phase-0 Prototype Remnants

The app originally began as a test tool (`google-api-test`) writing 4-column data (`Date`, `Category`, `Description`, `Amount`) to month-named tabs (e.g., `September 2026`). Phase 1 replaced this with the 16-column canonical `transactions` tab and `budgets` tab.

### Obsolete Components:
1. **`FTL/services/Ledger/LegacyMigration.swift`**
   - One-time migrator designed to read month tabs and append to `transactions`.
   - Exposed via `AppEnvironment.makeLegacyMigration()` and `SettingsView.swift` ("Migrate legacy data").
   - Once existing data is migrated, this is dead code.
2. **Phase-0 Month APIs in `FTL/services/GoogleAPI/SheetsService.swift`**
   - `SheetsService.Expense`
   - `addExpense(_:)`
   - `readMonth(for:)`
   - `deleteMonthRow(at:for:)`
   - `ensureMonthTab(for:)`
   - `monthTabName(for:)`
   - `headers = ["Date", "Category", "Description", "Amount"]`
   - Production uses `SheetsLedgerStore` and `SheetsBudgetStore`. The only caller of these legacy methods is the debug sections in `DebugView.swift`.
3. **`FTL/services/GoogleAPI/GmailService.swift`**
   - Prototype REST client with crude `spending` regex (`#"Rp\.?\s*[\d.,]+"#`).
   - Production mail fetching uses `GmailExporter.swift` (RFC 2822 fetching, HTML normalization, batching, etc.). `GmailService` is only called by an old debug section in `DebugView.swift`.
4. **Debug Sections in `FTL/view/Debug/DebugView.swift`**
   - `Section("Add expense")` and `Section("Entries")` write directly to month-named tabs.

### Action:
- Remove `LegacyMigration.swift` and its settings row.
- Prune obsolete month-tab methods from `SheetsService.swift`.
- Remove `GmailService.swift` and the corresponding Phase-0 sections in `DebugView.swift`.

---

## 4. Deferred Contracts & Dead Execution Pipelines

1. **`ResultReasoner.swift` & `CalcTool.evaluate(_:)`**
   - `ResultReasoner` was intended for a Phase-2 natural-language query box.
   - Commented out in `AppEnvironment.swift:86` (`// let reasoner: ResultReasoner`).
   - `LedgerQuery`, `LedgerAggregate`, and `CalcTool.evaluate(_:)` (implemented in `LedgerCalcTool.swift` and `InMemoryStores.swift`) have **zero call sites** anywhere in the application.
2. **`PurchaseClassifier.swift` & `struct Merchant`**
   - `PurchaseClassifier` was an on-device tool-calling classifier protocol. Commented out in `AppEnvironment.swift:85`.
   - `FoundationModelClassifier.swift` only conforms to the offline evaluation harness (`Evaluator.Verdict`), not `PurchaseClassifier`.
   - `struct Merchant` (`canonicalName`, `defaultCategoryID`, `isConfirmed`) in `Merchant.swift` is never instantiated; runtime tagging uses `MerchantID`, `TagKey`, `TagMemory`, and `TagDecisionRecord`.
3. **`TagStore.swift` & `AppEnvironment.reconcileTagStore()`**
   - `ContentView.swift` executes `.task { await environment.reconcileTagStore() }` on every launch, reading budget categories from Google Sheets and saving them to `tag_store.json`.
   - **Dead execution:** Production tagging (`FoundationModelTagger` and `DefaultPurchaseTagger`) receives categories dynamically from the ledger. They **never read `TagStore`**. `TagStore` is only used by the offline evaluation bench (`FoundationModelClassifier`).
4. **`TransactionMarkerDetector.detect(in:)` & `Evidence.isLikelyTransaction`**
   - Audited in `ROADMAP.md` as non-generalizing (0/116 on blu).
   - Only `TransactionMarkerDetector.hasCurrencyMarker` is used in production (by `CapturedEmail.hasCurrencyMarker`). The rest is dead code.

### Action:
- Drop `.task { await environment.reconcileTagStore() }` from `ContentView.swift`.
- Clean unused `evaluate` methods and deferred `ResultReasoner` / `PurchaseClassifier` contracts, or mark them clearly as experimental/evaluation-only.

---

## 5. Dead Domain Enums and Review Flags

### `ReviewFlag.Reason` Cases with Zero Production Callers:
* **`.orphan`** — Designed for statement rail ("statement line with no matching receipt"). Statement rail is deferred; 0 callers.
* **`.largeAmount`** — Designed for statement rail ("statement lines can't split; flag if material"). 0 callers.
* **`.needsSplit`** — Mixed receipt split (model job 1). Only referenced in preview mock `SampleLedger.swift`.
* **`.unknownMerchant`** — Only referenced in preview mock `SampleLedger.swift`.

### `CaptureSource` Cases:
* **`.statement`** & **`.photo`** — Unimplemented rails, deferred in `ROADMAP.md`. Only `.email` and `.manual` exist.

---

## 6. Design System & UI Remnants

1. **`FTL/view/DesignSystem/Components/GlassCard.swift`**
   - Filename is an obsolete remnant. `GlassCard` was deleted when gradient glass was replaced by flat fills and hairlines. The file now contains `SurfaceCard` and `PanelCard`.
2. **Unreferenced Color Tokens in `FTLColor.swift` & `Assets.xcassets`**
   - `FTLColor.accentContrast` (0 callers)
   - `FTLColor.scrim` (0 callers)
   - `FTLColor.provisional` (0 callers)
   - `FTLColor.budgetAtCeiling` (only in `forStanding`, unused in views)
3. **`LedgerRow.showsAccent`**
   - Defaults to `false` and is never set to `true` anywhere in the app.

---

## 7. Prioritized Action Plan

| Priority | Area | Action | Risk / Benefit |
|---|---|---|---|
| **P1** | **Bundle Bloat** | Move `test/` (82 MB) out of `FTL/` target directory; delete `sample.json`. | Zero risk; cuts app bundle size by ~87%. Fixes email privacy leak. |
| **P2** | **Savings Goal** | Delete `SavingsGoal.swift`, `GoalStore.swift`, `GoalViewModel.swift`, `GoalDetailView.swift`, `GoalCard`. | Low risk; removes dead code and reduces cognitive load. |
| **P3** | **Launch Tag Sync** | Remove `reconcileTagStore()` call from `ContentView.swift`. | Zero risk; eliminates wasteful startup I/O on every launch. |
| **P4** | **Phase-0 Remnants** | Remove `LegacyMigration.swift`, Phase-0 methods in `SheetsService.swift`, and `GmailService.swift`. | Low risk; simplifies service layer and removes obsolete UI buttons. |
| **P5** | **Cleanup & Renaming** | Rename `GlassCard.swift` to `Cards.swift`; prune dead `ReviewFlag` cases and unused `FTLColor` tokens. | Low risk; improves codebase tidiness and consistency. |
