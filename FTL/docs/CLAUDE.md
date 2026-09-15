# FTL — development guide

**An iOS app that learns to read your receipts.**

A person hand-writes one or two parsers to establish what a template looks like.
After that the model proposes extraction patterns for new senders, a deterministic
verifier scores each proposal against real emails it never saw, and only what
clears the bar becomes a stored rule. Runtime executes those rules with no model
in it. Spending lands in a Google Sheets ledger, and everything canonical is gated
by a deterministic rule or by the user.

The deterministic spine is not a lesser app built while waiting for the model. It
is the **verifier** — its correctness is what makes the model's mistakes cheap.

**The target is a mailbox nobody has looked at** — other banks, other merchants,
other currencies, no hand-written parser for any sender. This one is mine, and
every number recorded against it is a number about *this* corpus. Decided
2026-09-09; see the audit in `ROADMAP.md` for which assumptions survive it and
which do not.

What to build next, and why in that order: `ROADMAP.md`. What has actually been
measured, and what has not: `TESTING.md` — read its last section before trusting
any number in this file.

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

Everything not named below is deterministic code or a human gate. If a change
would route deterministic work through the model, it is the wrong change — say
so rather than implementing it.

⚠️ **The numbering below is the INTENDED architecture and is not what runs.**
Audited 2026-09-14 — read this before forming a mental model from the rest of
the section:

| calls the model | conforms to | wired |
|---|---|---|
| `FoundationModelSynthesizer` — learn a sender's template | `PatternSynthesizer` | **yes** (job 3 below) |
| `FoundationModelTagger` — which bucket? | via `DefaultPurchaseTagger` | **yes** (job 4 below) |
| `FoundationModelClassifier` — is this a purchase? | nothing | no — Evaluation harness only |
| `FailureExplainer` — reads a failing eval run | nothing | no — `DebugView` only |

So **jobs 1 and 2 — the two this section calls "at runtime" — make no model
calls at all.** `PurchaseClassifier` and `ResultReasoner` are Phase 2 contracts;
in `AppEnvironment` they are still two commented-out lines. The only two jobs
that actually reach a model are the ones described below as the "third" and
"fourth", which arrived later and were never renumbered. The live agent is the
LOOP (synthesis) and the TAGGER, and nothing else.

**Job 3 — pattern synthesis, and one of the two that actually runs** (Phase 3,
`model/Contracts/PatternSynthesis.swift`). The model learns a sender's template,
a deterministic verifier scores the proposal against real emails, and only a
pattern that clears the bar is promoted to a stored rule. This does not weaken the
principle — it applies it. The model proposes, code verifies, and the artifact it
produces is executed with no model in the loop.

**Job 4 — the tagger, the other one that actually runs, and the shape the
other three are not:** the tagger
(`model/Contracts/PurchaseTagger.swift`). Synthesis has an oracle *where a
hand-written parser exists* — run the proposed rule over held-out mail and score
it. (On an unseen mailbox it does not, and the gap between those two cases is
measured in *Measured constraints*; the two tools converge there, because the
queue ends up being the only oracle either of them has.) Tagging has none and
cannot have one anywhere: whether `HOKKY SUPERMARKET` is groceries or shopping is a decision about
your own budget, not a fact in the email. So it is not *propose → verify →
promote* but **propose → you decide → accrue**, which makes the approval queue
the tagger's training signal rather than overhead around the loop. Every
suggestion is deterministic where you have decided before (`TagMemory` — a
lookup, and the wide path); the model is asked only for a merchant with no
history. Nothing it says reaches the ledger without the same tap everything else
needs.

The model half is asked **once per merchant per batch**, not once per row: the
budget counts calls, and asking per row spends it on rows rather than questions.
Measured on a real device — a 45-row sync across ~20 merchants used all 8 calls
on the first 8 rows and left later rows from merchants it had already answered
untagged.

**The agent does not run in the background at all.** `BackgroundRefresh` builds
its rail with `makeGmailRail(tagged: false)`, so an unattended fetch does
capture, parse, dedup and pairing — and no tagging. The reason is arithmetic:
`FoundationModelTagger` is bounded at 8 calls and the measured p95 is 3.82s
each, which is up to 30 seconds, which is the entire budget `BGAppRefreshTask`
gets before iOS kills the task. Spending it there would mean rows parsed and
never written.

Nothing is lost by it, and that is only true because of the split below: the
memory half runs on every queue load, so rows captured while the app was shut
arrive tagged the moment the queue is opened. If `refresh` ever stops being
cheap to re-run, this trade stops working.

**It has two entry points, split by cost, and that split is load-bearing.**
`tag` runs once at capture and may call the model. `refresh` runs on **every
queue load** and is a memory lookup with nothing expensive in it — no model, no
network. That is what makes settling one row visible on the next one down in the
same sitting. The first version tagged only at capture, so a decision taught the
rest of the queue nothing until the next fetch, and a row already waiting never
got a suggestion at all. Moving the memory half back to capture time is the
wrong change.

---

## Invariants — these do not bend

Violating any of these is a bug even if the tests pass and the feature works.

1. **The model never writes to the ledger.** Only `ApprovalService` PROMOTES a
   `ProvisionalEntry` into `LedgerStore`, and promotion is the path this
   invariant is about — there is exactly one, and no rail, rule or model reaches
   it. `LedgerStore` itself is not read-only: `update` and `delete` exist so a
   person can correct or remove a row they are looking at (see *The ledger is
   editable* below). Neither is reachable from the pipeline; both are reachable
   only from a screen with a human on it. If a third write path appears, check
   which kind it is — a second way to promote breaks this, a second way for a
   person to fix their own ledger does not.
2. **The model never does arithmetic.** Every number shown to the user comes from
   `CalcTool` or a Sheets formula. A model that emits a total is a defect.
3. **`merchantRaw` is never mutated.** Normalization writes a separate `merchant`
   field. The raw string survives forever, per source — it is the reconciliation
   join key and the recovery path for every normalization error.
4. **Money is never `Double`.** Use `Money` (integer minor units + currency).
5. **Non-spend is labelled, never deleted.** `kind == .nonSpend` rows stay in the
   ledger for audit and are excluded from spend aggregates. A refund and an
   arriving payment are non-spend *cases*, not spending with a minus sign: a
   refund does not offset the purchase it reverses, because a non-spend row
   moving a spend total would contradict this rather than extend it. What it
   does instead is **pair**: a refund is a dedup problem — one purchase, two
   rows, weeks apart — so it is found by the same fingerprint buckets and
   flagged `.reversal` naming the charge it undoes. Flagged, never netted, the
   same answer `possibleDuplicate` USED to give — see Invariant 6, which that
   flag no longer obeys.
6. **Escalate by flagging — never by asking, never by blocking.** An uncertain row
   gets a `ReviewFlag` and the batch continues. No modal questions, no blocked runs.

   **One deliberate exception, added by decision and not by derivation:** a row
   flagged `possibleDuplicate` is now `.autoDropped` at capture and never
   reaches the queue (`GmailRail.droppingDuplicates`). This is the only place
   the system discards captured spending without asking, and the test behind it
   is deliberately loose — `isSameCharge` blocks on a fingerprint bucket and
   ignores direction, so two identical fares on one day are indistinguishable
   from one fare billed twice. It is made survivable rather than safe: the row
   is still INSERTED (under its own status, so a machine drop is never confused
   with a person saying no), it is listed under "dropped as duplicates" in the
   queue with a Restore, and it records no `PatternObservation` — the queue's
   worth as an oracle is that it is human evidence. A row also flagged
   `.reversal` is never dropped, or refunds would vanish.
7. **Provisional is not canonical.** Nothing in `ProvisionalStore` is a fact. The UI
   must always make the difference visible. Four statuses are human outcomes
   (`pending`, `approved`, `rejected`, `promoted`); `autoDropped` is the fifth
   and is deliberately NOT `rejected`, because `rejected` means a person looked
   and said no and that record is the only one of its kind the app has.
8. **Descriptive, never prescriptive.** The app reports position against ceilings the
   user set. It never judges whether they are spending well. This binds copy, colour,
   and iconography — see *Design tokens*.
9. **Every model call passes a `LanguageGate` first.** See *Measured constraints*.
   The gate is parameterised by `ModelTask`, because strictness follows what happens
   to the answer. `.classification` is strict — that answer is the product and is
   taken on trust. `.anchorSynthesis` skips the language check — that answer is a
   proposal, scored by `PatternVerifier` against real emails before it can affect
   anything, so refusing it up front does not prevent a wrong answer, it prevents
   finding out. Empty and over-length are refused for both; they are physical limits,
   not trust judgements. Adding a new model call means choosing a task, and
   `.classification` is the default for an unannotated call site.
10. **Trust ladder climbs by measurement, one rung at a time.** `Assist` is the
    default and the only rung shipping today. `Auto` — a row reaching the ledger
    without a person seeing it — is now an intended destination rather than a
    forbidden one, and it is reached only like this:
    - The accrued accuracy that opens it is measured **against the user's own
      approvals**, not against a model's confidence in itself. A tool that says
      it is 90% sure has told you nothing; a tagger that matched your decision on
      nine of its last ten identical merchants has. That counting now exists —
      `TagMemory`, recorded at the gate, read by `TagScoreboard`. It is a
      measurement in shadow and nothing routes on it.
    - It is scoped as narrowly as the evidence is. Per merchant, per sender, per
      tool — never a global switch. Auto for `HOKKY SUPERMARKET` says nothing
      about a shop seen once.
    - Every auto-committed row is marked as such and is reversible. Silence is
      not the same as agreement, and the audit trail is what makes a wrong
      threshold recoverable instead of a mystery.
    - The threshold is a measurement, not a preference. Whatever number is
      chosen, what it costs at that number must be known first — 80% accuracy is
      one wrong row in five.

    Invariant 1 is unchanged and is what makes this safe to attempt: `Auto` means
    `ApprovalService` promoting without a human tap, **not** a second write path.

---

## Flow

As it runs today. ★ marks the only two places a model is called; everything else
on this page is deterministic code or a person.

```
 Email·P1   Statement·P2   Photo·P3        CaptureRail   (only Email is built)
     └───────────┼─────────────┘
                 ▼
       activeParsers: learned + presets    ← ★ SYNTHESIS wrote these, offline,
                 │                            verified before promotion. No model
                 │                            runs here — a pattern is a stored
                 ▼                            rule, executed with none in the loop.
          DocumentNormalizer          deterministic: parse, strip, fingerprint
                 ▼
            RuleEngine                dedup · pairing · non-spend · recurring
           ╱          ╲
    settled            possibleDuplicate ──▶ .autoDropped   (Invariant 6's one
       │                                      exception — restorable in the queue)
       ▼
   PurchaseTagger.tag                 ★ TAGGER — asked ONLY for a merchant with
       │                                no history, ≤8 model calls per sync, and
       │                                NOT AT ALL on a background fetch
       ▼
   ProvisionalStore (on-device, SwiftData)      recoverable — Invariant 7
       │
       │   on every queue load, no model, no network:
       │     · PurchaseTagger.refresh   — re-derives tags from TagMemory
       │     · MerchantMemory           — fills in what you call each shop
       ▼
 ═══════════════════════════════════════════════════════
   ApprovalService          ← THE HUMAN GATE. Assist, pinned.
                              correctAmount / correctMerchant / retag / drop
 ═══════════════════════════════════════════════════════
       ▼
   LedgerStore ─── BudgetStore  (Google Sheets, canonical)
       │             update / delete are human-driven; promotion is the
       │             one path this diagram guards
       ▼
   CalcTool ──▶ every number on screen, and the widget snapshot

 NOT BUILT: PurchaseClassifier (job 1), ResultReasoner (job 2) — Phase 2
 contracts, commented out in AppEnvironment, zero model calls.
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
    ├── model/                    Pure Swift. No I/O, no SwiftUI, no SwiftData, no networking.
    │   ├── Domain/               The nouns. Value types, Sendable, Codable where stored.
    │   │   ├── Money.swift                 integer minor units — never Double
    │   │   ├── LedgerTransaction.swift     the canonical Sheets row
    │   │   ├── ProvisionalEntry.swift      a cache row + how it got there
    │   │   ├── NormalizedTransaction.swift a parsed candidate, not yet judged
    │   │   ├── BudgetNode.swift            the target tree + BudgetPosition
    │   │   ├── MonthSummary.swift          one month against its ceiling
    │   │   ├── SpendCategory.swift         + CategoryID, kind, non-spend taxonomy
    │   │   ├── TagSuggestion.swift          what the tagger said, kept beside
    │   │   │                                what you chose — the accuracy record
    │   │   ├── SavingsGoal.swift           ⚠️ not in the spec — see Scope deviations
    │   │   ├── CapturedEmail.swift         one email as the Gmail export gives it
    │   │   ├── CaptureSource · Fingerprint · Merchant · ReviewFlag · RuleID
    │   │   └── DateInterval+Ledger.swift   half-open month bucketing (see Gotchas)
    │   └── Contracts/            Protocols. Every service is reached through one of these.
    │       ├── LedgerStore.swift            P1  ← the canonical store
    │       ├── BudgetStore.swift            P1
    │       ├── CalcTool.swift               P1  ← all arithmetic lives behind this
    │       ├── ProvisionalStore.swift       P1
    │       ├── ApprovalService.swift        P1  ← the only ledger write path
    │       ├── GoalStore.swift              P1  ⚠️ not in the spec
    │       ├── ReceiptParser.swift          P1  ← deterministic extraction
    │       ├── LanguageGate.swift           P2
    │       ├── PurchaseClassifier.swift     P2  ★ model job 1
    │       ├── ResultReasoner.swift         P2  ★ model job 2
    │       ├── PatternSynthesis.swift       P3  ★ tool 1 — learn a pattern
    │       ├── PurchaseTagger.swift         P3  ★ tool 2 — tag a purchase
    │       ├── MerchantMemory.swift         P3  ← what you CALL each shop, so a
    │       │                                    rename outlives the row it was
    │       │                                    typed on. Keyed on MerchantID
    │       │                                    alone — unlike TagKey, a name
    │       │                                    does not vary by layout
    │       └── TagMemory.swift              P3  ← what you decided. The only
    │                                            oracle tool 2 can ever have
    │
    ├── view/                     SwiftUI only. No business logic, no service access.
    │   ├── RootView.swift        the auth gate: restoring → signed out → signed in
    │   ├── ContentView.swift     the signed-in shell — one NavigationStack + sheets
    │   ├── Screens.swift         wrappers that OWN each screen's view model in @State
    │   ├── Onboarding/           SignInView, IncomeSplitView (income → % → ceilings)
    │   ├── DesignSystem/
    │   │   ├── MoneyFormatter.swift   the only place Money becomes a string
    │   │   ├── Tokens/           FTLColor, FTLSpacing, FTLRadius, FTLTypography
    │   │   └── Components/       SurfaceCard, MeterBar, SplitBar, RatioSlider,
    │   │                         FlowLayout, Chrome, Saucer (the one piece of
    │   │                         iconography), ActionFailure (the alert three
    │   │                         screens used to not show — see its header)
    │   ├── Home/                 P1 — hero, queue card, buckets, goal, recent
    │   ├── Bucket/               P1 — one bucket; its ceiling is a READOUT here,
    │   │                         set in Settings or all at once by income
    │   ├── Goal/                 P1 — savings goal (⚠️ not in the spec)
    │   ├── Months/               P1 — the month picker sheet
    │   ├── Review/               P1 — the approval queue sheet (the human gate)
    │   ├── Capture/              P1 — add spend (keypad + bucket picker + note),
    │   │                         and EditTransactionSheet — correcting a row
    │   │                         already in the ledger, in native Form controls
    │   ├── Settings/             P1 — account, ceilings, background fetch + the
    │   │                         daily reminder hour, trust ladder, Debug link
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
        ├── GoogleAPI/            auth, Gmail, Sheets transport, shared client
        ├── Ledger/               REAL: SheetsSchema, SheetsLedgerStore,
        │                         SheetsBudgetStore, LedgerCalcTool,
        │                         DefaultApprovalService
        ├── Pipeline/             IndonesianMoney, BluReceiptParser,
        │                         DefaultLanguageGate
        ├── Evaluation/           EmailCorpus (fixtures + labels), Evaluator
        ├── Preview/              fixtures only — InMemory* stores + SampleLedger
        ├── Persistence/          SwiftDataProvisionalStore — durable provisional
        │                         cache. One container, FIVE tables: the queue,
        │                         the capture log, promoted patterns,
        │                         SwiftDataMerchantMemory (what you call each
        │                         shop — a preference, overwritten, one row per
        │                         merchant), and
        │                         SwiftDataTagMemory. That last one is the only
        │                         table here with NO upstream copy — the ledger
        │                         re-reads from the Sheet and the queue can be
        │                         re-approved, but a lost decision history is
        │                         everything the tagger learned, gone.
        ├── Capture/              AutoSync (foreground), BackgroundRefresh (iOS
        │                         decides when) and NotificationSchedule (a
        │                         reminder at an hour you pick).
        │                         ManualEntry — the one manual-spend write path,
        │                         shared by the Add sheet and the App Intent.
        │                         GmailRail — the email rail, which now also asks
        │                         the tagger for a bucket after parsing.
        │                         Photo/statement rails still deferred.
        ├── Widget/               WidgetDataSnapshot (shared with the widget
        │                         extension through an App Group) and
        │                         WidgetSnapshotWriter, which builds it from
        │                         CalcTool so anything — Home, a background
        │                         fetch, an intent — can refresh the home screen
        ├── Intents/              AddSpendIntent and CheckReceiptsIntent —
        │                         Spotlight / Shortcuts / Siri. The second is
        │                         how a fetch gets scheduled at an exact hour;
        │                         see its header for why that cannot be us
        └── Agent/                FoundationModelSynthesizer — ★ tool 1's model
                                  call. FoundationModelTagger — ★ tool 2's, asked
                                  only for a merchant with no history and bounded
                                  at 8 calls a sync. FoundationModelClassifier —
                                  an on-device tool-calling classifier,
                                  ⚠️ reachable ONLY from the Evaluation harness:
                                  it returns Evaluator's `Verdict`, not
                                  `ClassificationVerdict`, so it does NOT conform
                                  to PurchaseClassifier and is not wired into
                                  AppEnvironment.

  test/sample.json                1000 real emails. ⚠️ 6.6 MB, currently shipped
                                  in the app bundle — gate behind DEBUG before
                                  any build leaves the device.
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

### Two environments

`AppEnvironment.live()` is the real app — the user's Google Sheet is the ledger.
`AppEnvironment.sample()` is fixtures, used by the DEBUG skip-sign-in path so UI
work doesn't need an account. **`FTLApp` owns which is active**: a separate flag in
`RootView` raced the environment swap and built the screens against the wrong store.

`RootView` gives `ContentView` an `.id(ObjectIdentifier(environment))` so swapping
environments rebuilds the screens — they hold view models in `@State` and would
otherwise keep the ones bound to the old store.

**The provisional cache now survives a relaunch.** `SwiftDataProvisionalStore` in
`services/Persistence/` — Stage 0 #1, done.

### What goes where — the test

- Does it do I/O, or know about Google/SwiftData/Foundation Models? → `services/`
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
where `URLSession`, SwiftData, Gmail, and Foundation Models are allowed to exist.

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
    private let store: ProvisionalStore      // protocol, not the SwiftData type
    private let approvals: ApprovalService

    private(set) var entries: [ProvisionalEntry] = []
    private(set) var phase: LoadPhase = .idle

    init(store: ProvisionalStore, approvals: ApprovalService) { … }
}
```

`AppEnvironment` is the single composition root. It is the only file allowed to
write `SheetsLedgerStore()` or `SwiftDataProvisionalStore()`. Everything else receives
protocols.

---

## Design tokens

**Neutral greyscale plus exactly one signal colour.** There is no accent hue, no
gradient, and no glow anywhere in the app. Hierarchy comes from type size and
value; colour is spent only on the thing that needs pointing at.

The v0.6 canvas's indigo ground, violet glows and gradient glass were built and
then removed — three layers of decoration on every surface, none of them carrying
information, and collectively the house style of generated UI. What survived from
the canvas is its *structure*: the nav, the hero-then-buckets order, the month
menu, the sheets.

- **Ground** `#0F0F10`, **panel** `#191919`. Flat and opaque — no translucency,
  no gradient, no shadow. `.ultraThinMaterial` reads grey over this ground; don't
  reach for it.
- **A card is a fill and a hairline.** That is the whole recipe (`SurfaceCard`,
  `PanelCard`). The home hero is not a card at all — the largest number on screen
  doesn't need a box to say it matters, and boxing it just adds an edge.
- **The signal** is `#C87F5C`, warm terracotta. It is `budgetOverCeiling`,
  `flagged` and `destructive` — three tokens sharing one value so any can diverge
  later. Nothing else in the app has a hue.
- **No raw colour in `view/`.** No `Color.red`, no `Color(hex:)`, no `.blue`.
  Everything resolves through `FTLColor`, backed by `Assets.xcassets/Colors/` and
  addressed via Xcode's generated symbols, so a missing token fails the build
  instead of rendering nothing. Same for `FTLSpacing`, `FTLRadius`,
  `FTLTypography` — no magic numbers.
- The app is a **committed dark theme**; both appearance slots carry the same
  value, so a light theme is a catalog edit with no code change.
- Type is SF Pro and SF Mono at the canvas's metrics. **Every figure is
  monospaced** so columns align and a changing number never reflows its row.

### Invariant 8 is carried by restraint, not by hue

The app reports position against a ceiling the user set and never judges them for
it. With one signal colour doing over-ceiling, flags *and* destructive, the whole
guarantee rests on *how* that colour is used:

> It appears as a thin meter fill and a small figure. Never a filled banner, never
> a warning glyph, never enlarged, never animated. A row over its ceiling reads
> "210.000 over" and stops — no verb, no adjective, no icon.

---

## Testing workflow

Three lanes, because Foundation Models only runs on-device: you cannot `pytest` it,
and a nondeterministic call with a 3.8s p95 has no business in a unit test.

| Lane | Tool | Speed | When |
|---|---|---|---|
| Data prep, sampling, labelling | **Python** — keep it there | — | offline, once |
| Parsers, rules, `Money` maths | Swift Testing (`@Test(arguments:)`) | ms | every build |
| Model evaluation | on-device harness → JSON report | ~1h / 1000 | on demand |

Lane 1 stays Python. Don't rewrite pandas in Swift; JSON is the interface.

Lane 3 is **not a test** — it is a measurement run whose product is a number you
can argue with, which is exactly what `feasibility-report.md` already is. It lives
at **Settings → Evaluation** (DEBUG).

### The harness

`EmailJudge` is the shared seam: a `ReceiptParser` and a `PurchaseClassifier` both
conform, so both report identically and **the gap between them is the model's
actual job**. `Evaluator` produces an `EvaluationReport` carrying the metrics from
the feasibility run — coverage, refusals, honest rate, confidently-wrong, latency,
per-sender — and writes JSON to share back into Python.

Run the deterministic parser first. Whatever it settles is work the model never
has to see.

⚠️ **There is no test target yet.** Lane 2 needs a Unit Testing Bundle added in
Xcode before the parsers can have fast table-driven tests. They are pure functions
and deserve them.

---

## What the corpus says

`test/sample.json` — 1000 emails, exported 2026-09-07. Facts worth not
rediscovering:

- **Sender concentration is extreme.** 72 domains; the top 20 are 86% of the
  corpus. LinkedIn alone is 326. A sender allowlist removes most noise before any
  classification.
- **blu by BCA is the ledger.** 116 emails, **ten unique subjects, 95 identical**.
  That is a template, and templates are regex work. `BluReceiptParser` handles
  116/116 at sub-millisecond, from the snippet alone.
- **The bodies of the receipts are missing.** `strip_body_html.py` removed
  `bodyHtml`, and receipts are HTML emails — only 19% of purchase-ish messages
  kept a plain body, against 70% overall. The ones that kept text are LinkedIn,
  Steam, Strava: not spending. **Re-export keeping raw HTML, and strip it in
  Swift**, so the thing under test is the thing that ships.
- **Gmail's snippet is often enough.** All 112 blu transaction snippets carry a
  parseable amount and counterparty. Treat body as a bonus, not a precondition.
- ~22% look purchase-ish by a crude heuristic, which already false-positived on
  ten LinkedIn emails.
- Language by subject+snippet: 67% English, 17% Indonesian. **The share among
  actual receipts is unmeasured** because the bodies are gone — and it matters,
  because the framework refused 4 of 4 Indonesian prompts. `DefaultLanguageGate
  .languageBreakdown()` answers this with no model call; run it after the
  re-export before building the classifier.

---

## Measured constraints

From `feasibility-report.md`, run against the on-device model on 2026-09-03. These
are why v0.6 is scoped the way it is; do not design as though they are solved.

- **The refusal is decided by the language of the WHOLE PROMPT, not the receipt.**
  Measured on device 2026-09-08: `SystemLanguageModel` supports 21 locales, Dutch and
  Vietnamese among them, Indonesian not. A prompt whose text reads as `id` throws
  `unsupportedLanguageOrLocale` regardless of content, and one that reads as anything
  on the list goes through. Two consequences, both counter-intuitive:
  - blu's synthesis succeeded for a year's worth of Indonesian receipts because its
    prompt happened to detect as **Dutch**. That was luck, not capability.
  - Prompt SCAFFOLDING moves the verdict. Terse `--- EXAMPLE 1 ---` / `SUBJECT:` /
    `TEXT:` headers around a ride receipt read as `id 0.83`; the same receipt alone
    reads `en 1.00`. English prose framing takes every layout to `en 1.00`. See the
    note on `FoundationModelSynthesizer.prompt` before touching prompt formatting.
  - Consequently `DefaultLanguageGate.supported = [.english]` is narrower than the
    model actually is, and is refusing content the framework would accept. Unmeasured
    for classification accuracy, so not widened — but it is known to be wrong.
- **The framework refused 4 of 4 Indonesian prompts**, and 28 of 84 calls suite-wide
  were refused before the model saw them. Read this in light of the entry above: the
  prompts, not the ledger, were what got classified. Hence `LanguageGate`: check
  before every model call, and
  fall through to a deterministic flag on a miss. A refused row must still produce a
  cache entry — flagged, never dropped silently.
- **Auto is unsafe: 67% of unattended writes correct**, 8 verdicts confidently wrong.
  Assist only.
- **Confidence does not track correctness** — 0.76 when right, 0.73 when wrong,
  0.03 separation. Do not gate anything on a confidence threshold; it does not carry
  the information. Route on rules and flags instead.
- **One runaway tool loop hit 30 calls.** Any agent loop needs a hard call budget.
- **Without an oracle, nothing is ever promoted.** Measured 2026-09-09 over the
  1,000-email export: a pattern that is 100% correct on 116 emails still only
  reaches `.provisional`, because promotion runs through `PatternVerifier.verify`
  and `verify` needs a `PatternOracle`. On a mailbox with no reference parser,
  `attempted == 0` for every sender — so **every row from every learned pattern
  arrives flagged, always.** This is structural, not a threshold to tune.

  The circularity is worth stating plainly: `ParserOracle` makes the loop
  rigorously verifiable exactly where a hand-written parser already covers the
  sender — i.e. exactly where the learned pattern is redundant.

  The approval queue is the only oracle an unseen mailbox generates, and it is
  now wired: `PatternMemory` records what you did with every row a learned
  pattern produced, and `unverifiedPattern` stops firing once the queue has kept
  ≥95% of that pattern's rows over ≥20 settled ones (`PatternTrustPolicy`).
  Drops take it back down — the ladder is reversible, per Invariant 10.

  It used to measure an ACCEPTANCE rate rather than an accuracy, because the
  queue could not edit an amount or a merchant — so approving a row was a vote
  that it looked right, not a check that it was. **Done, 2026-09-13:** the queue
  corrects both, and `PatternObservation.Verdict` now separates
  `correctedAmount` (it could not find the number the email states outright),
  `correctedMerchant` (it found the number and named it wrong) and
  `correctedKind` (direction, which is inferred and has the best excuse).

  Two caveats that keep it honest. A rename that normalizes to the SAME
  `MerchantID` is cosmetic and is not counted against the pattern — otherwise
  `MerchantMemory`, which fills that name in on every later row, would pin the
  pattern at zero forever. And none of this can see an error nobody noticed: a
  rubber-stamped queue still measures nothing, which is why `labels.json` is
  still on the list.
- **Coverage could not see a constant merchant, and now can.** Same run: a
  pattern reading the same string out of every email — a label, not a name —
  scored **81.9% coverage at 0% accuracy**, refused only by an 8-point margin.
  `PatternVerifier.constantComplaint` closes it: real patterns read 64–66
  distinct merchants at 0.08–0.10 modal share, the label-reader reads one at
  1.00, and the bar sits at 0.5. Takes that pattern to **0.0%** and leaves the
  real ones untouched. The two plausibility rules are complementary — the
  window-edge rule catches an anchor with no terminator (values vary), this
  catches an anchor pointed at a label (values do not).
- **The money parser is Indonesian-only.** `IndonesianMoney` matches `Rp|IDR` and
  nothing else, and `Money` assumes zero minor units — right for IDR, wrong for
  almost everything. 32 emails in the corpus carry `$`/USD that nothing can read.
  On a non-Indonesian mailbox the pipeline reads zero.
- **The language gate refuses 36% of money mail** (93 of 258) at the strict
  `.classification` setting, which is what `FoundationModelTagger` uses. That is
  the correct strictness for an answer nothing verifies, and it is a measured
  ceiling on how much of the queue the tagger's model half can ever reach.
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

## The ledger is editable

`LedgerStore` gained `update` alongside `append` and `delete`. This is the
clarification Invariant 1 now carries: what that invariant protects is
**promotion**, and promotion still has exactly one door. Correcting a row you are
already looking at is a different act, and it is the same authority `delete`
always had.

What an edit cannot touch is fixed by the TYPE, not by a doc comment.
`merchantRaw`, `id`, `source`, `capturedAt` and `approvedAt` are all `let` on
`LedgerTransaction`, so Invariant 3 survives any future change to the editor:
a correction physically cannot rewrite the raw string the reconciliation join
key depends on. `amount` is `var` — it is the one field where "what the app
read" and "what was actually charged" can differ and only a person can say
which is right. `date` stays `let`: when a receipt was dated is a fact about the
receipt, not a judgement about the row.

`SheetsLedgerStore.update` rewrites ONE row, located by its id in column A — not
the clear-and-rewrite `delete` does. A whole-tab replace spent on a one-cell
correction briefly empties the ledger and depends on the second call landing.
The row number cannot come from `all()`, which drops the header and skips rows
it cannot parse: a user-editable sheet makes half-typed rows an expected state,
and those indices stop matching the sheet's the moment one appears.

---

## Widgets read through an App Group, and that is a trap

`WidgetDataManager` writes a `WidgetDataSnapshot` into
`group.hend-aml.FTL`; the extension reads it. Both targets need
`com.apple.security.application-groups` in their entitlements — `FTL/FTL
.entitlements` and `FTLWidgets/FTLWidgets.entitlements`, wired through
`CODE_SIGN_ENTITLEMENTS` in the pbxproj.

⚠️ **This silently did nothing for the whole of the widgets' first existence.**
There were no entitlements files at all, so `UserDefaults(suiteName:)` returned
nil, the code fell back to `?? .standard`, the app wrote a perfectly good
snapshot into its own container, and the extension — a separate process with a
separate container — read its own, found nothing, and rendered `.placeholder`.
Every figure on those widgets was a hardcoded fixture, and nothing anywhere
looked broken.

The fallback is gone. `sharedDefaults` is optional, `saveSnapshot` returns
whether it worked, and `isSharedStoreAvailable` says so out loud. A shared store
that quietly stops being shared is worse than one that fails.

`WidgetSnapshotWriter` builds the snapshot from `CalcTool` (Invariant 2 — the
arithmetic is not re-implemented for the home screen) and is called from Home,
from `BackgroundRefresh` and from `CheckReceiptsIntent`. The background call is
unconditional: the per-day allowance moves every midnight whether or not
anything was bought, so a closed-app fetch is the only chance to correct it.

---

## Where this actually is

Built and working: the UI, the approval gate, manual entry, and the **Sheets-backed
ledger** — `transactions` and `budgets` tabs, created with headers on first use.
That is a usable manual expense tracker with a budget view, and a legitimate place
to stop and live with it for a while.

Also built: the evaluation scaffold and the first deterministic parser. See
*Testing workflow* and *What the corpus says*.

Also built, and **not yet run against real mail** — hold both at arm's length:
the second tool (`PurchaseTagger` + `TagMemory`), typed non-spend markers so a
learned pattern can say a row is a refund or money arriving rather than only
"not spending", and refund/charge pairing through the existing fingerprint
buckets. The verifier now scores direction; before, a pattern could get it wrong
on every email and still score 1.00.

**The agent now reads the mail.** As of 2026-09-09 `makeGmailRail` passes
`parsers: []`; precedence is `learned + presets`, then hand-written. blu is
covered by a preset pattern (`Fixtures/preset-patterns.json`) and
`BluReceiptParser` keeps the one job only it can do — being the oracle
`PatternVerifier` scores proposals against.

The old order was `handWritten + learned`, and the rail takes the FIRST parser
that claims an email, so a learned pattern never read a blu email. The
justification was sound (protect 112/112 from ~97%) and the consequence was
fatal: the loop was shut out of the one sender it could be verified against, so
nothing ever accrued. What makes agent-first safe is not a reference parser
winning — it is the approval queue, which every row passes through anyway.

**The queue is now a real oracle, not just an acceptance count.** It can correct
an amount and a merchant before approving (`ApprovalService.correctAmount`,
`correctMerchant`), so `PatternRecord` counts a misread figure or name as a miss
instead of letting it pass as a keep. A merchant correction that only tidies the
same shop — `GRAB* A-9MVB…` → `Grab`, which normalizes to the same `MerchantID`
— is cosmetic and is NOT counted against the pattern; one that keys somewhere
else entirely is. Without that split, `MerchantMemory` would pin every pattern
it helped at zero accuracy forever.

Not built, in the order they matter: a `labels.json` so accuracy can be measured
against ground truth rather than against agreement, then one capture rail end to
end. **Still no test target** — five targets, none of them tests — so every pure
function in here (`apportion`, `setPercent`, `verdict(for:)`,
`merchantWasMisread`, the parsers, `Money`) is verified by hand on a simulator
and nothing else.

**v0.6 is a spec, not a commitment.** The rails and the model job are upgrades to a
working app, not prerequisites for one. Cutting scope is legitimate, and the spec's
own build order says to decide from real use.

---

## Build order

**Phase 1 — the deterministic spine.** Capture rails, normalize, fingerprint, the
rule set, provisional cache, approval queue, Sheets ledger, budget dashboard. No
model. This is useful on its own, and it is the current phase.

**Phase 2 — one model job.** `PurchaseClassifier` behind `LanguageGate`, writing
provisional rows only. Then `ResultReasoner` + `CalcTool` for the query box.

**Phase 3 — decide from measurement.** Whether classify+tag earns promotion, or
collapses to "flag it", is settled by observed false-positive rates. Not upfront.

**The app now runs itself up to the queue, from four triggers.** `AutoSync` on
foreground (throttled to 15 minutes) was the first thing here that ever ran
without a tap. `DiscoverySync` runs one bounded sweep per launch.
`BackgroundRefresh` runs when iOS grants a window, which is opportunistic and
cannot be pinned to an hour. `CheckReceiptsIntent` runs whenever Shortcuts says
to, which CAN be — that is why scheduling lives there rather than in a
background task pretending to be a scheduler.

The boundary is identical for all four and is the one the invariants already
draw: fetch, parse, dedup, pair and tag write only to the provisional cache and
are automated; approving writes to the ledger and is never automated (Invariant
1, `.assist`). Audited 2026-09-14: none of the four reaches `approve`. If a
change would move a ledger write onto any of those paths, it is the wrong
change.

**Phase 4 — make it work on someone else's mail.** The target (top of this file)
is a mailbox with no hand-written parser for any sender. Three of the four
things that stood in the way are done (queue-as-oracle, the constant-merchant
check, agent-first precedence); currency generalisation was **descoped** —
"unseen mailbox" means other banks and merchants, not other currencies, and
`IndonesianMoney` stays the only money parser. What remains is unattended
discovery → synthesis → promote. See `ROADMAP.md`.

Contracts for Phase 2 exist now so the spine is built against the right seams. Do
not implement them early.

---

## Conventions

- Swift 5 language mode, iOS 26.5, `@Observable` over `ObservableObject`.
- Protocols in `model/Contracts` are named for the role (`LedgerStore`), impls for
  the mechanism (`SheetsLedgerStore`, `SwiftDataProvisionalStore`).
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
- **`DateInterval.contains` is closed at both ends**, and a calendar month ends at
  midnight on the 1st — so a transaction stamped exactly midnight counted in two
  months and every monthly total was silently wrong. Use
  `interval.containsLedgerDate(_:)` for every ledger date comparison.
- **Sheets writes use `valueInputOption=RAW`.** `USER_ENTERED` lets Sheets
  reinterpret "2026-09-07" as a date serial and hand it back locale-formatted, and
  amounts as floats. Amounts store as integer minor units (`34500`) — the cell is
  less pretty, the arithmetic is exact.
- **`NumberFormatter` cannot read Indonesian amounts under a US locale.**
  "Rp18.000,00" parses as **18.0** — a thousandfold error, silently, in a ledger.
  Dots group thousands and the comma is the decimal separator, the mirror of US
  formatting. Use `IndonesianMoney`, which parses by hand.
- **A SwiftUI `Toggle` inside `PanelRow` renders correctly and swallows every
  tap.** The switch draws at the trailing edge and the control's hit area does
  not survive that container; the same `Binding(get:set:)` works fine inside a
  `Form` (see `DebugView`'s "Pure agent mode"). Settings rows are Buttons with
  the state on the trailing edge — "Mode · Assist" is the pattern — so follow
  that rather than losing an afternoon to it, as this cost once already.
- **`.tint` does not reach a `role: .destructive` button** under the default
  style: the system paints its own red and ignores the token. Add
  `.buttonStyle(.plain)` and `.foregroundStyle(FTLColor.destructive)`. This was
  the one hue in the app that was not `FTLColor`, and it looked correct in code.
- **`TimelineView` proposes an unspecified size to its content**, and a `Shape`
  given no proposal falls back to its 10×10 ideal. A timeline must WRAP the
  sized stack, not sit inside it — inverted, `BeamActivity`'s rungs drew into a
  tiny box at the centre while the saucer around them filled the frame.
- **`NavigationLink` will not push from inside the Settings sheet.** Neither
  `.contentShape` nor dropping `.buttonStyle(.plain)` fixes it. The developer rows
  present their destinations as sheets instead. Cause unknown; worth knowing before
  you lose an hour to it.
- Money is `Money`, never `Double` — see Invariant 4. Mixed-currency arithmetic
  traps deliberately rather than silently converting; v0.6 dropped FX, so a mixed
  sum means something upstream is wrong.
