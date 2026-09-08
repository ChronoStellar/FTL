# FTL — build order

Companion to `CLAUDE.md`, which says *how* to work. This says *what next*, and why
each thing sits where it does.

**Sizes** are relative, not calendar estimates: **S** ≈ an evening, **M** ≈ a
weekend, **L** ≈ several sessions with unknowns in them.

---

## The thesis

**The app learns to read your receipts.**

A person hand-writes one or two parsers to establish what a template looks like.
After that the model proposes patterns for new senders, a deterministic verifier
scores each proposal against real emails it never saw, and only what clears the
bar is promoted to a stored rule. Runtime executes those rules with no model in
the loop.

That is the product. Everything below exists to make that loop **safe**,
**measurable**, and **fed with real data** — those three words are the whole
ordering principle.

> **Guardrail.** If you find yourself hand-writing parser #3, stop. Two reference
> implementations is enough to know what good looks like. A third is the signal
> that the loop should already exist — you are doing the model's job by hand.

The deterministic spine is not a lesser version of the app you build while
waiting. It is the **verifier**. Its correctness is what makes the model's
mistakes cheap, and that is why it comes first.

---

## Stage 0 — Don't lose data

Nothing is built on top until these three are done.

### 1. Persist the provisional cache · **M** — ✅ built, ⚠️ unverified
`InMemoryProvisionalStore` → `SwiftDataProvisionalStore` in `services/Persistence/`.
SwiftData rather than GRDB: one `@Model` row, queryable columns for status /
createdAt / fingerprint buckets, everything else through a JSON blob so a new
field on `ProvisionalEntry` doesn't force a migration.

Rows awaiting approval do not survive a relaunch. Captured spending silently
disappearing is the worst failure this app has, and it lands on the human gate
every safety guarantee depends on. It is also where synthesized patterns will
eventually be stored — the loop needs somewhere durable to keep what it learned.

*Done when:* add an expense, force-quit, relaunch, it's still queued. **This has
not actually been run.** The code is wired and builds; nobody has watched a row
survive a relaunch, which is the only thing that proves the item.

### 2. Verify the live Sheets path · **S** — ✅ done
Rows round-trip against the real sheet. What that surfaced is Stage 0.5.

### 3. Get the corpora out of the shipping bundle · **S** — worse than recorded
Not 6.6 MB. **Both** corpora ship: `sample.json` (6.6 MB) *and*
`gmail_export.json` (75 MB). That's **82 MB of your real email metadata in a
94 MB app** — measured in the built `.app`, not estimated.

The synchronized group takes everything under `FTL/`, so `gmail_export.json`
started shipping the moment it was created, silently. `#if DEBUG` resource rule,
a build-phase strip, or a test-only target — all mean editing the project file by
hand, which is why it keeps getting deferred. It should stop being deferred: this
is no longer a tidiness item, it's the single biggest thing between this app and
anything leaving the device.

Blocked on the same thing as #5: with no test target to move it into, the options
are a `#if DEBUG` resource rule or a build-phase strip, and both mean editing the
project file by hand.

---

## Stage 0.5 — The sheet is the app's memory, and it was corrupt

Not planned work. Running #2 against a real sheet turned up a chain of write-path
bugs, each of which silently produced data that later reads couldn't make sense
of. Recorded because the pattern matters more than the individual fixes: **every
one of these was the app writing something it could not read back.**

Fixed:

- **A root that was its own parent.** `setCeiling` hard-coded `parent = total` on
  every appended row, including the `total` row itself. That row is then neither
  a root (its parent column isn't empty) nor anyone's child — the tree resolves
  to nothing and *every bucket vanishes from the dashboard*. Root cause of a
  blank Buckets section that survived three earlier speculative fixes.
- **Appends landing at column N.** `values.append` was given the `A:P` span; it
  searches a range for a "table" and writes "starting with the first column of
  the table it finds". Now anchored at `A1`.
- **The total taking a share of itself.** A root row with a non-empty parent
  comes back from `categories()` looking like an ordinary bucket, so the income
  split gave it a percentage and wrote that over the income.
- **Case-sensitive category ids.** `Food` and `food` were two buckets. `CategoryID`
  now trims and lowercases at construction — one choke point, every path.
- Cycle brake in the tree walk; orphan rows reparented rather than dropped.

Still outstanding, and they need a person:

- [.] **Total ceiling is still the clobbered `750000`** while its children sum to
      ~4.25M, so Unallocated reads about −3.5M. Re-run Set Up by Income with the
      real figure.
- [.] **Rows already written at column N** are still there. The fix stops new
      ones; it doesn't repair old ones.

**The lesson worth keeping:** four rounds went into guessing at the shape of a
sheet nobody could see. The debug inspector (Settings → Developer → Google API
harness → *Inspect budgets + categories*) found the real cause on its first run.
Reach for it first, not fifth.

---

## Stage 1 — Get real emails flowing

### 4. Gmail rail, blu only · **M**
Not "email capture". One sender.

`BluReceiptParser` already handles **116/116** sub-millisecond, so every remaining
unknown is plumbing rather than extraction. Two payoffs at once: the app starts
working while you aren't looking, **and** fresh emails start arriving for the loop
to learn from later. A pattern learner with no incoming mail is a demo.

Needs: `GmailRail`, a record of what's been handled, a way to trigger a fetch.

**✅ Working against a real mailbox.** `services/Capture/GmailRail.swift`,
triggered from Settings → Developer → *Fetch receipts from Gmail*. Receipts land
in the approval queue; re-running finds no new mail (dedupe confirmed).

Running it turned up two parser bugs that the frozen corpus could never have
shown, both fixed:

- **Snippet shape vs body shape.** `BluReceiptParser` was written and measured
  against Gmail *snippets*, where the whole transaction is one line
  (`Total Rp18.000,00`). Live mail arrives with `bodyHtml`, and a stripped HTML
  table puts each cell on its own line (`Total\nRp18.000,00`).
  `IndonesianMoney.labelled` matched the literal `label + " "`, so it read
  **3 of 112** real emails. Fixed by `CapturedEmail.flatText` (parsers match
  whitespace-collapsed text, so snippet and body converge) plus a
  whitespace-tolerant label match → **112/112**, snippet path unchanged.
- **Incoming transactions counted as spending.** `"Incoming Transaction to Your
  blu"` contains "transaction", passes the subject gate, and fell through to
  `.spend` — money *received* inflating spend and pushing buckets over their own
  ceilings by the user's own income. Now `.nonSpend`/`.transfer` (Invariant 5).
  3 of 122 blu emails reclassified, nothing else moved.

The lesson is the same one as Stage 0.5, in a different layer: **a parser is only
measured against the shape of data you fed it.** `sample.json` had bodies
stripped, so "116/116" was a claim about snippets that quietly did not transfer.

**Deliberate divergence from "incremental sync via `historyId`":** idempotency
comes from `CapturedEmailRecord` — one row per message id already handled —
rather than a cursor. A cursor is an optimisation with a failure mode: Gmail 
expires `startHistoryId` after roughly a week, and a lost or stale one silently
re-imports or skips. "Have I seen this message?" is correct whether the window
overlaps, the sync restarts, or two run at once. Revisit when volume justifies
it; at ~100 messages a month it doesn't.

What it does NOT do, and why:

- **Never approves.** Manual entry auto-approves because a person typed the
  number. Nothing here was typed by anyone, so every row lands `.pending` for the
  human gate.
- **Never categorises.** A parser reads a receipt; it doesn't know your buckets.
  `categoryID` is nil and the approver picks — guessing would put spend in a
  bucket nobody chose.
- **Never drops mail it can't read.** A recognised template with a missing field
  becomes a flagged row, not a silent skip (Invariant 6).

*Done when:* you buy something with blu, open the app, it's waiting in the queue.

---

## Stage 2 — Build the scoreboard

**This is the loop's verifier.** Without it there is no way to tell a good
proposal from a bad one, and the whole thesis collapses into vibes.

### 5. Test target + parser tests · **S**
A Unit Testing Bundle (one click in Xcode — I can't add it from here), then
`@Test(arguments:)` over `sample.json`.

The verifier in the synthesis loop *is* a test harness pointed at a candidate
pattern. Building it as tests first means the loop inherits something already
trusted.

### 6. `labels.json` · **M**, mostly your time
Ground truth. `EmailCorpus.needingLabels()` is down to **557** after
auto-excluding known non-purchase senders, and only ~216 are genuinely ambiguous.
An afternoon in Python, not a week.

Until this exists the harness reports coverage, refusals and latency but **cannot
report accuracy** — which means no proposal can ever be scored. This is the single
hardest blocker on the thesis, and it is bounded, boring work rather than a
technical risk.

### 7. Re-export with raw HTML · **S**
`strip_body_html.py` removed the bodies of exactly the emails that matter — only
19% of purchase-ish messages kept plain text. Strip HTML **in Swift**, so the
thing under test is the thing that ships.

blu happens to survive on snippets alone. Most senders won't, and the loop needs
real bodies to find patterns in.

✅ **Done.** `test/gmail_export.json` (75 MB, `bodyHtml` intact) exists, HTML is
stripped in Swift by `HTMLNormalizer`, and `EmailCorpus.load` now defaults to the
export with `sample.json` as fallback.

This mattered more than its **S** suggested. Measuring parsers against stripped
bodies meant measuring them against *snippets*, and that number did not transfer:
116/116 on snippets, 3/112 on real HTML bodies. The harness could not have caught
it, because the harness had never seen a body.

---

## Shipped off-roadmap

Manual-entry and budget-setup work that isn't part of the thesis but is now in the
app. Listed so it isn't rediscovered as a surprise.

- **Income split** (`view/Onboarding/IncomeSplitView`) — type a monthly income,
  split it across buckets by percentage, save writes every ceiling at once.
  Shown once when the Total ceiling is still zero, and any time from
  Settings → Budget Ceilings. Starts from an EVEN split: any weighted default
  would be the app having an opinion about your money (Invariant 8). Leftover is
  allowed and lands in `unallocated`; only overrunning the income is blocked.
- **`SplitBar`** — the split chart. Segments differ by opacity on one colour,
  because FTLColor is greyscale plus exactly one signal and a bucket is not a
  signal.
- **Add spend** — bucket is a menu picker, not a wrapping chip grid; the note
  moved to its own sheet. Those two inputs cannot share a screen: a system
  keyboard over the custom keypad clips the amount label and stacks two
  keyboards. Separating them deleted three earlier keyboard-dismissal
  workarounds.
- **Missing-category detection** — Settings lists categories used by transactions
  that have no budget row (the legacy import creates these) with one-tap add.
- **`AddSpendIntent`** — Spotlight / Shortcuts / Siri, writes without opening the
  app. Buckets come from the live sheet. ⚠️ `perform()` has never actually run;
  it needs a signed-in session.
- **`ManualEntry`** (`services/Capture/`) — one implementation of what a
  hand-entered spend becomes, shared by the Add sheet and the intent. Two front
  doors building the same entry independently is how they drift.
- **`AppEnvironment.shared`** — App Intents run in-process, so a second
  environment would open a second SwiftData container on the same file.

---

## Stage 3 — Establish the target shape

### 8. Grab parser — reference implementation #2 · **M**
36 emails, a different template from blu's.

The point is not coverage. It is to learn what varies between two templates, so
`ExtractionPattern` is shaped by two real examples rather than one. Write it, then
check: could an `Anchor` pair have expressed both? If not, the schema is wrong and
better to know now.

**Then stop hand-writing parsers.**

---

## Stage 4 — The loop

### 9. Pattern synthesis · **L**
`model/Contracts/PatternSynthesis.swift`

```
observe    a sender with unparsed emails
   ↓
PROPOSE    ★ model reads ~5 examples → ExtractionPattern
   ↓
VERIFY     deterministic: score it against the sender's other emails
   ↓
  ┌────────┴────────┐
passes            fails → feed the concrete misses back, re-propose (bounded)
   ↓
PROMOTE    stored rule, run by PatternDrivenParser — no model at runtime
```

Why this is safe where a runtime classifier is not: a wrong pattern is caught by
the verifier, not by your ledger. It runs **once per sender**, so the measured
3.8s p95 stops mattering. The 4-of-4 Indonesian refusal hurts less, because
success is judged deterministically afterwards. And it emits an artifact you can
read, version and revoke.

`BluReceiptParser`'s **116/116 is the bar** a synthesized pattern must clear.

Build in this order: the verifier first (it's stage 2's harness, repointed), then
`SenderProfile` triage, then proposal last. Two thirds of this is deterministic.

## ✅ The loop closed, on device, against real mail

A synthesized pattern cleared the bar set by the hand-written parser. Propose →
verify → correct → promote, with the verdict decided deterministically and the
model never grading its own work. That is the thesis, demonstrated.

It proves a small on-device model can read five receipts and describe a template
well enough to survive scoring against 111 emails it never saw.

**Promoted patterns now persist and the rail executes them.**
`ExtractionPatternRecord` + `SwiftDataPatternStore` (same container as the queue
and the capture log); `GmailRail` loads them at the start of each sync, so a
pattern promoted while the app is running is live on the next fetch.

Three rules worth keeping:

- **Hand-written parsers take precedence.** The rail takes the first parser that
  claims an email, and the list is `handWritten + learned`. `BluReceiptParser`
  reads 112/112 where its synthesized equivalent scores ~97%; letting the learned
  one win would trade real accuracy for the appearance of progress. The loop is
  for senders nobody has written a parser for.
- **Best per sender, not latest.** A later attempt can score worse, and shipping
  a regression because it is newer is the loop making the app worse while looking
  like it improved.
- **Versions are kept, and revoking is a flag not a delete.** The case for
  patterns over opinions is that the artifact can be read, diffed, versioned and
  revoked; overwriting in place throws away three of the four.

Still true: the learned pattern has never actually parsed a live email, because
blu is covered by a hand-written parser that outranks it. **The first real test
is a sender with no reference parser** — see the guardrail note below.

**Next:** `SenderProfile` triage (#10) — decide which sender is worth a run.

**The guardrail can be re-read now.** "Stop before parser #3" assumed a person
writes the reference implementations. Grab was on the list to *shape* the schema
— but executing the schema shaped it instead (48% → 96%), so Grab is better spent
as the loop's **first unseen sender**: a genuine test of whether this generalises
past the template it was tuned on, rather than another parser written by hand.

**Built:** `PatternDrivenParser` (executes a pattern), `PatternVerifier` +
`PatternOracle` (scores one), `FoundationModelSynthesizer` (★ the model call),
`DefaultPatternLearner` (drives propose → verify → retry). Run it from
Settings → Developer → Google API harness → *Learn a pattern for blu*.

**First real run: the model was right and the executor was wrong.** 41.8s,
4 attempts, rejected at 11.7%. But read what it proposed:

```
subject:  Transaction | Refund
amount:   after 'Total'      → Transaction Date | Admin Fee
merchant: after 'bluAccount' → Amount | bluVirtual | Admin Fee
nonSpend: Admin Fee | Incoming
```

That is the correct template — the same multi-terminator structure derived by
hand, and it found `Incoming` unprompted. The 11.7% was two bugs of mine:

- **`window` and the terminator search span were the same constant (60).** blu
  puts `Transaction Date` 95 characters after `Total`, so a correct anchor found
  no terminator and returned nothing. They answer different questions — "how long
  can this value be?" versus "how far off may its end marker sit?" — and a marker
  can be far while the value is short. Split: `window` 60, `searchSpan` 400.
  **12.1% → 94.0%.**
- **`ProposedPattern` was narrower than `ExtractionPattern`.** `amountAfter` was
  one `String` where the executor takes `[Anchor]`, so the model could not
  propose the `Total`/`Amount` fallback *even when the feedback told it to*. The
  retry loop was structurally unable to fix the remaining failures. Now a list.
  **94.0% → 96.6%, clearing the 0.95 bar.**

The general lesson, third time today: **the loop can only correct what the
schema lets it say.** Four attempts and 42 seconds were spent re-proposing
against a fault the model had no vocabulary to address.

**LanguageGate has to be applied per example, not per prompt.** The first real
run refused outright with `unsupportedLanguage`. The gate was right about the
text and wrong about the question: blu's *transaction block* is English, but its
footer is a support number, a registered office on Jl. M.H. Thamrin and an NPWP,
and five of those concatenated into one 3,500-character blob reads as Indonesian.
One boilerplate footer was vetoing an entire sender.

Two corrections, both of which the roadmap already implied:

- Gate each example and keep the ones that pass — synthesis "only has to succeed
  on SOME examples", which makes the gate a **selector**, not a veto. Every call
  still goes out gated, so Invariant 9 is intact.
- Send the transaction block (~400 chars), not the whole email. The anchors all
  live there; the footer only adds context, noise, and a language the template
  isn't written in. `maxExamples` already caps how much a small model is shown —
  this is the same argument applied inside one example.

**`labels.json` is not a blocker for blu.** `ParserOracle(BluReceiptParser())`
supplies truth for that sender, so the loop can be exercised now; the labels
oracle is for senders with no reference parser.

**The schema was wrong, and executing it proved it.** A hand-written blu pattern
scored 48% through `PatternDrivenParser` — amounts right, merchants empty —
because blu ends the merchant with `Amount` in one layout and `bluVirtual` in
another, and `Anchor.before` allowed exactly one terminator. Generalising every
single-value field to a list took it to 115/116:

| | |
|---|---|
| one terminator, one subject, one amount label | 54/112 · 48% |
| + terminators as a list, earliest wins | 108/112 · 96% |
| + amount-label fallback (`Total` then `Amount`) | 111/112 · 99% |
| + subject matches as a list (brings refunds in) | **115/116 · 99%** |

This is the answer Stage 3 #8 was meant to produce — *"could an `Anchor` pair
have expressed both?"* — reached by running the schema against sender #1 rather
than hand-writing parser #2. Worth doing Grab anyway, but the schema is no longer
shaped by a single template's assumptions.

### 10. Sender discovery · **M**
The other half of "learn which emails to fetch". A sender becomes
`.receiptSource` when a pattern for it actually held up — not when the model
thought it looked promising. Same propose→verify→promote shape, and it prunes the
fetch list so model calls are never spent on LinkedIn.

---

## Stage 5 — The residue

### 11. `PurchaseClassifier` · **L**
Now the **fallback**, not the main event. If stage 4 works, most senders never
reach it — it handles genuinely one-off emails with no template to learn.

Prerequisites: #6 (or you can't tell if it works) and the language measurement
below (or you can't tell if it *can* work).

### 12. Measure the language mix · **S** — do this before #11
`DefaultLanguageGate.languageBreakdown()`, one tap, no model call, run on real
receipt bodies after #7.

The framework refused 4 of 4 Indonesian prompts. If your receipts are mostly
Indonesian, #11 is dead on arrival — and #9 still isn't, which is another reason
the loop is the better bet.

---

## Not now — and why

| Deferred | Reason |
|---|---|
| **Dedup rule** | `Fingerprint` exists and is unused. Correct: one rail means no duplicates. Build it when the second rail lands. |
| **Statement rail** | One bespoke parser per bank format, and no template to learn from — the loop can't help. |
| **Photo rail** | Cash residue. Lowest volume, highest manual cost. |
| **Query box / `ResultReasoner`** | Nothing to query until the ledger is full. |
| **Recurring detection** | `GROUP BY` over one month of data. |
| **Nested budgets, line-item splits** | v0.5 §10 says simple-first; flat buckets aren't visibly wrong yet. |
| **`Auto` trust level** | Pinned off by Invariant 10 until accuracy is re-measured. |

---

## Decisions I need from you

**Where synthesis runs.** This is the one job a larger model would help most with,
and it touches five examples rather than your mailbox. On-device keeps v0.6's
privacy premise intact; off-device would likely work better. Worth deciding
deliberately rather than by default — it is the single biggest lever on whether
the thesis works.

**The savings goal.** Home card, detail screen, `SavingsGoal`, `GoalStore`,
`GoalViewModel` — and no line in v0.6. It came from the design canvas. Keep or
cut; cutting touches four files and `AppEnvironment`.

**Re-export scope.** Raw HTML makes the corpus much larger. All 1000, or just the
~216 purchase-ish?

**Unallocated in the bucket list.** I show it; the canvas doesn't. I argued from
v0.5 §10 that hidden mystery spend is the failure the target tree exists to
prevent. Still your call.

**Income-split rounding.** Percentages are whole numbers, so reopening the split
and saving it unchanged shifts ceilings slightly — a bucket at 2.400.000 comes
back as 37% and saves as 2.405.000. The screen isn't idempotent. Fixable by only
writing rows whose percentage actually changed. Drift is small; churning the
sheet on every visit isn't nothing.

---

## Working notes

**`xcodebuild` incremental builds went stale mid-session** — reporting
BUILD SUCCEEDED while running zero compile steps, with the simulator launching a
nine-hour-old binary. Any "it builds" claim made that way is worthless. Use
`clean build` when a change appears not to take effect.

**When the sheet looks wrong, inspect it before theorising.** Settings →
Developer → Google API harness → *Inspect budgets + categories* dumps both tabs
verbatim and re-runs the app's own resolution over them: roots, unresolved
parents, id collisions once normalized, header integrity, and which columns each
of the last rows actually occupies.
