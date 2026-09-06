# FTL — development guide

An iOS app that keeps a Google Sheets expense ledger current with almost no manual
entry. It captures spending from email, bank/e-wallet statements, and receipt
photos; a small on-device model classifies and tags purchase emails; everything
canonical is gated by a deterministic rule or by the user.

Source of truth for scope: `../Ideation/finance-app-v06-summary.md` and
`../Ideation/finance-app-v06-flowchart_1.md`. Deeper detail (ledger columns, budget
tree, non-spend taxonomy) lives in `../Ideation/finance-app-specv5.md` — v0.6 narrows
v0.5's scope but does not replace its data model. Measured on-device model behaviour:
`../tech-feasibility/reports/feasibility-report.md`.

---

## The design principle

> The model acts autonomously only where false positives are **recoverable** (the
> provisional cache), and defers to tools where errors would be **invisible** (the
> math). Everything canonical is gated by a rule or by the user.

Two model jobs exist, and only two. Everything else is deterministic code or a
human gate. If a change would route deterministic work through the model, it is
the wrong change — say so rather than implementing it.

---

## Invariants — these do not bend

Violating any of these is a bug even if the tests pass and the feature works.

1. **The model never writes to the ledger.** Only `ApprovalService` promotes a
   `ProvisionalEntry` into `LedgerStore`. There is no other write path.
2. **The model never does arithmetic.** Every number shown to the user comes from
   `CalcTool` or a Sheets formula. A model that emits a total is a defect.
3. **`merchantRaw` is never mutated.** Normalization writes a separate `merchant`
   field. The raw string survives forever, per source — it is the reconciliation
   join key and the recovery path for every normalization error.
4. **Money is never `Double`.** Use `Money` (integer minor units + currency).
5. **Non-spend is labelled, never deleted.** `kind == .nonSpend` rows stay in the
   ledger for audit and are excluded from spend aggregates.
6. **Escalate by flagging — never by asking, never by blocking.** An uncertain row
   gets a `ReviewFlag` and the batch continues. No modal questions, no blocked runs.
7. **Provisional is not canonical.** Nothing in `ProvisionalStore` is a fact. The UI
   must always make the difference visible.
8. **Descriptive, never prescriptive.** The app reports position against ceilings the
   user set. It never judges whether they are spending well. This binds copy, colour,
   and iconography — see *Design tokens*.
9. **Every model call passes a `LanguageGate` first.** See *Measured constraints*.
10. **Trust ladder is pinned to Assist.** No `Auto` write path ships until accuracy is
    re-measured. Do not add one "behind a flag".

---

## Flow

```
 Email·P1   Statement·P2   Photo·P3        CaptureRail
     └───────────┼─────────────┘
                 ▼
          DocumentNormalizer          deterministic: parse, strip, fingerprint
                 ▼
            RuleEngine                dedup · known merchant · non-spend · recurring
           ╱          ╲
    settled            unresolved
       │                   ▼
       │          PurchaseClassifier  ★ model job 1 — P2 · is-this-a-purchase, tag
       │                   │
       ▼                   ▼
        ProvisionalStore (on-device, GRDB)
                 ▼
          ApprovalService              ← human gate, Assist default
                 ▼
   LedgerStore ─── BudgetStore  (Google Sheets, canonical)
                 ▼
          ResultReasoner  ──calls──▶  CalcTool   ★ model job 2 — P2
```

Settled rows skip the model entirely and land straight in the cache. That path is
the majority and must stay that way.

---

## File structure

Building on the `model / view / viewModel / services` skeleton already in the repo.
The Xcode target uses a **file-system synchronized group** — new files and folders
inside `FTL/` join the target automatically. No `.pbxproj` editing needed.

```
FTL/
├── CLAUDE.md
└── FTL/
    ├── FTLApp.swift              @main; builds AppEnvironment, hands it to RootView
    │
    ├── model/                    Pure Swift. No I/O, no SwiftUI, no GRDB, no networking.
    │   ├── Domain/               The nouns. Value types, Sendable, Codable where stored.
    │   │   ├── Money.swift
    │   │   ├── CaptureSource.swift
    │   │   ├── CapturedDocument.swift      raw, unparsed, straight off a rail
    │   │   ├── NormalizedTransaction.swift parsed + fingerprinted, not yet judged
    │   │   ├── Fingerprint.swift
    │   │   ├── ProvisionalEntry.swift      a cache row + how it got there
    │   │   ├── LedgerTransaction.swift     the canonical Sheets row
    │   │   ├── Merchant.swift
    │   │   ├── SpendCategory.swift
    │   │   ├── BudgetNode.swift            the target tree
    │   │   └── ReviewFlag.swift
    │   └── Contracts/            Protocols. Every service is reached through one of these.
    │       ├── CaptureRail.swift            P1
    │       ├── DocumentNormalizer.swift     P1
    │       ├── DeterministicRule.swift      P1
    │       ├── ProvisionalStore.swift       P1
    │       ├── ApprovalService.swift        P1  ← the only ledger write path
    │       ├── LedgerStore.swift            P1
    │       ├── BudgetStore.swift            P1
    │       ├── CalcTool.swift               P1  ← all arithmetic lives behind this
    │       ├── LanguageGate.swift           P2
    │       ├── PurchaseClassifier.swift     P2  ★ model job 1
    │       └── ResultReasoner.swift         P2  ★ model job 2
    │
    ├── view/                     SwiftUI only. No business logic, no service access.
    │   ├── RootView.swift        the auth gate: restoring → signed out → signed in
    │   ├── ContentView.swift     the signed-in shell — one NavigationStack + sheets
    │   ├── Screens.swift         wrappers that OWN each screen's view model in @State
    │   ├── Onboarding/           SignInView
    │   ├── DesignSystem/
    │   │   ├── MoneyFormatter.swift   the only place Money becomes a string
    │   │   ├── Tokens/           FTLColor, FTLSpacing, FTLRadius, FTLTypography
    │   │   └── Components/       GlassCard, MeterBar, FlowLayout, Chrome
    │   ├── Home/                 P1 — hero, queue card, buckets, goal, recent
    │   ├── Bucket/               P1 — one bucket + its editable ceiling
    │   ├── Goal/                 P1 — savings goal (⚠️ not in the spec)
    │   ├── Months/               P1 — the month picker sheet
    │   ├── Review/               P1 — the approval queue sheet (the human gate)
    │   ├── Capture/              P1 — add spend (keypad); photo/statement still empty
    │   ├── Settings/             P1 — account, trust ladder, Debug link
    │   └── Debug/                DEBUG only — raw harness over the Google services
    │
    ├── viewModel/                @Observable @MainActor. Depends on Contracts only.
    │   ├── LoadPhase.swift       shared screen state; a view model never throws to a view
    │   ├── HomeViewModel.swift
    │   ├── BucketDetailViewModel.swift
    │   ├── ApprovalQueueViewModel.swift
    │   ├── AddSpendViewModel.swift
    │   └── GoalViewModel.swift
    │
    └── services/                 Implementations. The only layer that touches the world.
        ├── AppEnvironment.swift  Composition root — the only place concrete types are named
        ├── GoogleAPI/            EXISTING: auth, Gmail, Sheets, shared client
        ├── Preview/              ⚠️ TEMPORARY: InMemory* stores + SampleLedger fixtures
        ├── Capture/              GmailRail, StatementRail (PDFKit/CSV), PhotoRail (VisionKit)
        ├── Pipeline/             Normalizers, the rule set, IngestPipeline orchestrator
        ├── Persistence/          GRDB: database, records, ProvisionalStore impl
        ├── Ledger/               Sheets-backed LedgerStore / BudgetStore / CalcTool
        └── Agent/                P2 — Foundation Models, guided generation, schemas
```

### Navigation

`FTLApp` → `RootView` (auth gate) → `ContentView`. **No tab bar** — the v0.6 design
canvas uses one stack:

- **Home** is the only root. The month is a menu in the nav title; `+` opens Add
  spend; the queue card opens the approval sheet.
- **Push:** Bucket detail, Goal detail — each with Undo in the title bar.
- **Sheets:** Months (medium detent), To approve (large), Add spend, Settings.
- **Settings** hangs off the `FTL` wordmark, top-left. The design has no other
  affordance for it and Sign out has to be reachable. Debug is nested inside it.

The Debug screen and the sign-in "Skip sign-in" button are both `#if DEBUG`.

**View models live in `@State` inside the `Screens.swift` wrappers, never
constructed inline in a `navigationDestination` or `sheet` closure** — those
closures re-run on every re-render, which silently rebuilds the view model and
discards whatever the user was part-way through.

`services/Preview/` holds placeholder `InMemory*` implementations of the Phase-1
contracts, wired in `AppEnvironment` so the UI runs before the real stores exist.
They are **not** behind `#if DEBUG` — they are currently the only implementations,
and gating them would break a Release build silently. Delete the folder when
`SheetsLedgerStore` and `GRDBProvisionalStore` land; only `AppEnvironment` changes.

### What goes where — the test

- Does it do I/O, or know about Google/GRDB/Foundation Models? → `services/`
- Does it hold screen state or format for display? → `viewModel/`
- Is it a `View`? → `view/`
- Is it a value type or a protocol with no dependencies? → `model/`

If a file needs an exception, the structure is wrong — raise it rather than
smuggling the import.

---

## MVVM rules

**View** — SwiftUI, dumb. Reads published state off exactly one view model, sends
user intent back as method calls. No `async` work, no service references, no
formatting logic beyond what a `Text` needs. A view never imports anything from
`services/`.

**ViewModel** — `@Observable`, `@MainActor`, one per screen. Holds view state,
owns loading/error/empty states, formats for display. Depends **only on protocols
from `model/Contracts`**, injected through `init`. Never imports SwiftUI. Never
names a concrete service type — that is what makes it testable with fakes.

**Model** — value types and protocols. `Sendable`. No dependencies at all.

**Services** — actors or `Sendable` structs implementing the contracts. This is
where `URLSession`, GRDB, Gmail, and Foundation Models are allowed to exist.

The target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so **every type is
main-actor-isolated unless it says otherwise**. That default is right for views and
view models and wrong for everything in `model/`, which has to be usable from the
background. So:

- Every type and protocol in `model/` is declared `nonisolated struct` /
  `nonisolated enum` / `nonisolated protocol`. Without it, a domain type gets pinned
  to the main actor and a service that touches it drags its work back onto it.
- Services doing real work are `actor` or explicitly `nonisolated`.
- View models are `@MainActor` — the default, stated anyway for readability.

```swift
@Observable @MainActor
final class ReviewQueueViewModel {
    private let store: ProvisionalStore      // protocol, not the GRDB type
    private let approvals: ApprovalService

    private(set) var entries: [ProvisionalEntry] = []
    private(set) var phase: LoadPhase = .idle

    init(store: ProvisionalStore, approvals: ApprovalService) { … }
}
```

`AppEnvironment` is the single composition root. It is the only file allowed to
write `SheetsLedgerStore()` or `GRDBProvisionalStore()`. Everything else receives
protocols.

---

## Design tokens

Values come from the v0.6 design canvas (`../Ideation/FTL App.dc.html`): deep
indigo ground, glass cards, `#6E7FB8` accent, coral `#F08E76`. **The app is a
committed dark theme** — both appearance slots carry the same value, so a light
theme is a catalog edit with no code change.

**No raw colour in `view/`.** No `Color.red`, no `Color(hex:)`, no `.blue`. Every
colour resolves through `FTLColor`, backed by an asset-catalog colour set in
`Assets.xcassets/Colors/`. Same rule for spacing, radius, and type — `FTLSpacing`,
`FTLRadius`, `FTLTypography`, no magic numbers.

The canvas specifies Instrument Sans and IBM Plex Mono; we render with SF Pro and
SF Mono at the canvas's metrics. Swapping in the real faces is a change to
`FTLMetrics` alone. **Every figure is monospaced** so columns align and a changing
number never reflows the row around it.

`.ultraThinMaterial` reads grey over this ground — it washed out both the cards and
the sheets. Glass is a `glassHigh`→`glassLow` gradient straight on the ground
(`GlassCard`), and sheets use `.presentationBackground(FTLColor.ground)`.

Tokens use Xcode's generated asset symbols (`Color(.accent)`), not string lookup, so
a token that doesn't exist fails the build instead of rendering nothing. Adding one
means adding the colourset **and** the `FTLColor` property.

Tokens are named for **role**, never for hue or for the one place they are used:
`FTLColor.textSecondary`, not `.grey60` and not `.dashboardSubtitle`.

Ledger-semantic tokens carry domain meaning, so they are defined once and reused:

| Token | Means |
|---|---|
| `spend` | a real outflow |
| `nonSpend` | transfer, top-up, cc payment, cashback, refund |
| `provisional` | in the cache, not yet approved — must read as visibly unsettled |
| `flagged` | needs a human look |
| `budgetUnderCeiling` / `budgetAtCeiling` / `budgetOverCeiling` | position against a ceiling |
| `unallocated` | the implicit child bucket — mystery spend, kept visible |

**Invariant 8 is carried by restraint, not by hue.** The design uses one warm coral
for over-ceiling, for destructive actions and for errors, so `budgetOverCeiling`,
`destructive` and `error` currently share a value. They stay three separate tokens
so `error` can diverge later without touching call sites.

What keeps "over your ceiling" from reading as a scolding is therefore *how* coral
is used, and this is the rule: it appears as a thin meter fill and a small figure,
never as a filled banner, never with a warning glyph, never enlarged. The row says
"210.000 over" and stops. No verb, no adjective, no icon.

---

## Measured constraints

From `feasibility-report.md`, run against the on-device model on 2026-09-03. These
are why v0.6 is scoped the way it is; do not design as though they are solved.

- **The framework refused 4 of 4 Indonesian prompts**, and 28 of 84 calls suite-wide
  were refused before the model saw them. The ledger's own language is not reliably
  processable on-device. Hence `LanguageGate`: check before every model call, and
  fall through to a deterministic flag on a miss. A refused row must still produce a
  cache entry — flagged, never dropped silently.
- **Auto is unsafe: 67% of unattended writes correct**, 8 verdicts confidently wrong.
  Assist only.
- **Confidence does not track correctness** — 0.76 when right, 0.73 when wrong,
  0.03 separation. Do not gate anything on a confidence threshold; it does not carry
  the information. Route on rules and flags instead.
- **One runaway tool loop hit 30 calls.** Any agent loop needs a hard call budget.
- Latency p95 3.82s, 152 MB resident — model work is batched and off the main actor,
  never in a view's `.task` on the render path.

---

## Scope deviations from v0.6

Two things in the shipped UI are not in the spec. Both are deliberate; neither
should be quietly normalised.

- **Savings goal** (`SavingsGoal`, `GoalStore`, `view/Goal/`) arrived with the
  design canvas, which gives it a home card and a detail screen. It has no line in
  v0.6. It stays inside Invariant 8 only as long as it reports a rate against a
  target the *user* set — never suggesting the target, the deadline, or what to
  cut to reach it. If it doesn't survive review, deleting it touches those three
  places and `AppEnvironment`.
- **Unallocated is shown as a bucket row.** The canvas leaves it out of the list.
  v0.5 §10 is explicit that every parent carries a visible unallocated child so
  mystery spend stays visible, and hidden it would still land in the hero total
  with nothing on screen explaining the gap. Shown, muted, only when it holds spend.

---

## Build order

**Phase 1 — the deterministic spine.** Capture rails, normalize, fingerprint, the
rule set, provisional cache, approval queue, Sheets ledger, budget dashboard. No
model. This is useful on its own, and it is the current phase.

**Phase 2 — one model job.** `PurchaseClassifier` behind `LanguageGate`, writing
provisional rows only. Then `ResultReasoner` + `CalcTool` for the query box.

**Phase 3 — decide from measurement.** Whether classify+tag earns promotion, or
collapses to "flag it", is settled by observed false-positive rates. Not upfront.

Contracts for Phase 2 exist now so the spine is built against the right seams. Do
not implement them early.

---

## Conventions

- Swift 5 language mode, iOS 26.5, `@Observable` over `ObservableObject`.
- Protocols in `model/Contracts` are named for the role (`LedgerStore`), impls for
  the mechanism (`SheetsLedgerStore`, `GRDBProvisionalStore`).
- Errors are typed per layer and surfaced as `LoadPhase.failed(message)` — a view
  model never throws to a view.
- `id` on ledger rows is a UUID and the idempotency key for Sheets append. A retried
  append is detected by reading it back, never by appending twice.
- Tests: pure rules and normalizers are the high-value target. Every
  `DeterministicRule` gets table-driven cases including the ones from
  `feasibility-report.md` (§ *Case detail* has 66 real ones — use them as fixtures).

## Gotchas already paid for

- **Google OAuth**: `secrets.plist` (gitignored, auto-bundled by the synchronized
  group) is the single source for `CLIENT_ID`. The reversed ID must also appear as a
  URL scheme in `Info.plist` — iOS reads that before any code runs. If they disagree
  the SDK raises an **Objective-C exception**, which Swift `catch` cannot see, so it
  reads as an unexplained crash on tapping sign-in. `GoogleAuthManager.configurationProblem`
  now pre-checks this; keep that check in front of any new auth path.
- `Info.plist` is a `membershipExceptions` entry in the synchronized group — it is
  the build's Info.plist, not a bundled resource. Don't "fix" it by re-adding it.
- **`Category` is taken.** The bare name resolves to an SDK typealias
  (`OpaquePointer`) in some contexts, so the domain type is `SpendCategory`. Watch
  for the same trap with other short generic names — `Transaction` is a SwiftData
  type, hence `LedgerTransaction` and `NormalizedTransaction`.
- Money is `Money`, never `Double` — see Invariant 4. Mixed-currency arithmetic
  traps deliberately rather than silently converting; v0.6 dropped FX, so a mixed
  sum means something upstream is wrong.
