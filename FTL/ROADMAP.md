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

### The agent has tools, and the tools are the loop

The agent is not a thing that reads your email. It is a small, bounded loop that
**calls tools**, and each tool's answer is checked by code before it counts.

| tool | what it proposes | what checks it | today |
|---|---|---|---|
| **learn a pattern** | where the fields sit in a sender's template, **and which way the money went** | `PatternVerifier`, against emails the model never saw | ✅ built |
| **tag a purchase** | which bucket a transaction belongs in | the user's own approvals, accrued per merchant | ✅ built, ⚠️ never run against real mail |

The two are deliberately different, and the difference is the whole design.

**A pattern can be checked without you.** "The amount follows the word Total" is
either true of the next fifty emails or it isn't, and code can find out. That is
why synthesis is allowed to run unattended.

**A tag cannot.** Whether `HOKKY SUPERMARKET` is *groceries* or *shopping* is not
a fact in the email — it is your decision about your own budget. No verifier can
settle it, so the only honest source of truth is what you approved last time.
**The approval queue is the tagger's training signal**, which is also why the
queue must stay pleasant to use: it is not overhead around the loop, it is the
loop's other half.

### Auto-commit is the third rung

Once a tool has been right often enough, its rows stop needing a tap and are
written straight to the ledger.

Three properties keep that from being a licence to be wrong:

- **Earned against your decisions**, never self-reported confidence. A model
  claiming 90% certainty has said nothing; a tagger that matched you on nine of
  its last ten identical merchants has said something checkable.
- **Scoped as narrowly as the evidence.** Per merchant, per sender, per tool.
  Trusting `HOKKY SUPERMARKET` implies nothing about a shop seen once.
- **Marked and reversible.** Silence is not agreement. Every auto-committed row
  says it was auto-committed, so a threshold set too low is recoverable rather
  than a mystery six weeks later.

The number is a decision, not a default. At **>80%**, one row in five is wrong
and lands unseen — while the *promotion* bar for a pattern is currently 95% over
≥20 verified emails. Those two gates should be argued about together before
either ships, and the honest way to pick is to run the tagger in shadow for a
month and count how often it would have matched you.

**The shadow run is now buildable.** Every approval records what was suggested
against what you chose (`TagMemory`, Settings → Developer → *Score the tagger
against your approvals*). Nothing routes on it and nothing is auto-committed;
the point is to have the number before the argument, not after.

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

**And it was still wrong about the direction of the money.** `nonSpendMarkers`
was a bare `[String]`, so a learned pattern could say "not spending" and nothing
more. That covers a transfer adequately and covers the two cases that actually
change what a person sees not at all: a **refund**, and **money arriving**. Both
were reachable only by hand — `BluReceiptParser` reads its own subject for
"Refund" and "Incoming" — so every sender the loop learns instead of a person
writing it lost the distinction.

Worse, **the verifier never looked.** `verify` compared the amount and the
merchant, so a pattern could get the direction wrong on every email and still
score 1.00, and coverage can't see it either. The loop could not have learned a
sender's refunds however many it saw, because nothing it did was ever marked
wrong.

Three changes, all of them the same lesson as the anchors — *the loop can only
correct what the schema lets it say*:

- `NonSpendMarker` carries a `NonSpendType`, and the synthesizer proposes
  refund / incoming / transfer as three separate literal lists. Three plain
  string lists rather than one list of typed objects, because copying words into
  three named buckets is a much easier task for a small model than choosing an
  enum case per string.
- `PatternVerifier` **scores `kind`**, which moves a number, and reports a wrong
  `nonSpendType` as advisory feedback, which does not. The subtype is a label on
  a row already excluded from every ceiling, and the oracle often *infers* it —
  blu concludes `.transfer` from a bank name beside an account number — so
  failing a pattern for not reproducing that would score the oracle's reasoning
  rather than the pattern's reading. It still reaches the retry as a concrete
  miss, which is how the loop learns to say "Refund" rather than merely "not
  spending".
- `NonSpendType` gained `.incoming`. blu's arriving money was labelled
  `.transfer`, which is a different fact — a transfer is money you moved between
  your own accounts. Nothing about any total changes; both are non-spend.

Measured over the fixture's blu subset, with only the markers differing:

| | |
|---|---|
| no direction markers | 7/12 · 58% |
| + refund / incoming / transfer markers | **11/12 · 92%** |

The four-email gap is the whole point: before this change both patterns scored
the same, because the four the first one got wrong were never checked. (The
twelfth is a merchant anchor missing on one layout — the same in both runs, and
not what is being measured here.)

Also added: a pinned learned pattern with typed markers and four fixture cases
(`learned-pattern-refund`, `-money-received`, `-untyped-marker-flags`, and the
spending control). An untyped marker is the one case that flags `ambiguousKind`
— "Admin Fee" says a bank was involved and nothing about what the movement was,
so the app reached a conclusion the sender never stated. A typed marker doesn't
flag, for the same reason blu's refunds don't: the word came from the sender's
own email, and a flag that fires on the sender's own statement is a flag nobody
reads.

### 10. Sender discovery · **M** — ✅ selection built, ⚠️ never run end-to-end
`PatternDiscovery` picks its own targets from unread money mail. Naming the
sender was the last hand-conditioned step in the loop; nothing types a domain
now.

The funnel is entirely deterministic — regex and set arithmetic, no model
anywhere — which is what makes it safe to leave running:

    all mail → carries Rp/IDR → nothing can read it → groups into a layout
    → its figures MOVE → enough of them → worth a model call

**The step that makes it safe is amount variance.** Ranked by volume alone, the
top two candidates in the real corpus are Apple's "your iCloud storage is full"
and Traveloka's discount campaign — both templated, both full of Rp, neither a
transaction. A pattern learned from either reads a figure out of every email and
scores 1.0 coverage, which is exactly the failure coverage cannot detect. Asking
whether the numbers change costs one regex pass and separates them completely:

| | variance |
|---|---|
| blu 55 · blu 40 · grab ride · grab food | 0.88 – 1.00 |
| apple · traveloka · linkedin · edx | 0.04 – 0.12 |

**It has never proposed a pattern for a sender nobody had named.** On the 1,000-
email corpus it correctly finds *zero* candidates: after blu and Grab, what is
left is brochures, or real receipt senders with 3–9 emails against a floor of 10
(Mandiri 0.67, KAI 0.50 — both clear the variance bar and fail on volume). The
limit is the sample, not the loop. Re-export at 3,000–5,000 and it has work.

---

## Where this stands — 2026-09-08

### What went well

**Grab learned, and the trust ladder held on its first real test.** Two layouts
separated deterministically, both patterns provisional, both persisted. The one
thing the agent got wrong — the merchant — arrived in the queue *flagged*
`unverifiedPattern` rather than trusted. Assist, never Auto, working as designed
rather than as an aspiration.

**The prompt's language, not the receipt's, was gating synthesis.** Measured on
device: `SystemLanguageModel` supports 21 locales, Indonesian not among them, and
it judges the WHOLE PROMPT. The old terse scaffolding (`--- EXAMPLE 1 ---` /
`SUBJECT:` / `TEXT:`) around a ride receipt detected as `id 0.83`; the same
receipt alone reads `en 1.00`. **blu had only ever worked because its prompt
happened to detect as Dutch, which is on the list.** Framing in English prose
takes every layout to `en 1.00`, Indonesian food receipts included. See the note
on `FoundationModelSynthesizer.prompt` before touching prompt formatting.

**Every purchase through Grab was being counted twice** — the merchant's receipt
and the bank's card notification, both true records of one payment. Rp 718,016 of
Rp 7,026,838: spending read **10% high**. Neither parser was wrong. The detector
for it already existed (`candidates(matching:)`, `possibleDuplicate`,
`Fingerprint.adjacent`) and had **no callers**.

**A deterministic fixture suite.** 29 cases, committable, no personal data,
pinned learned patterns so the executor runs with no model or network. It has
already caught two things nobody was looking for.

### What didn't work

The pattern is consistent enough to name: **every instrument that was calibrated
for one context and reused in another gave a confident wrong answer.**

| the instrument | asked the wrong question |
|---|---|
| `coverage` | "did it extract something?" — non-empty is a liveness check, not a quality bar. Scored garbage merchants 1.00 on 21 real rows |
| `LanguageGate` | filtered *email* language for a task gated on *prompt* language, and its `[.english]` set is narrower than the model's 21 locales |
| subject-first triage | one subject is not one layout (Grab, 0.52 coverage) — and one layout is not one subject (blu loses a third layout of 12 receipts) |
| `Fingerprint` ±Rp5,000/±3d | built to pair a statement line with a receipt whose totals differ; useless where the bank charges exactly what the merchant billed. 48/137 flagged, 29 wrong |
| `isLikelyTransaction` | precise on Grab (21/21) and **0/116 on blu** — vocabulary does not generalise |
| boilerplate-ratio plausibility | separates on average (0.14 vs 0.71) but rejects 15/116 real merchants — would sink a *good* pattern |

Process failures worth not repeating, all mine:

- **Four speculative fixes for an empty dashboard** before writing an inspector.
  The inspector found it in one run.
- **The pipeline harness seeded with `SampleLedger` preview fixtures**, which
  sorted to the top and were reported as pipeline output. A test whose fixtures
  are indistinguishable from its results is worse than no test.
- **Hand-counting a 60-character window** for four fixture expectations. The
  pipeline was right in all four; the fixture was wrong.
- **Changing production triage to fit fixture data I had just written.** The
  finding was real (blu's third layout); acting on it unasked was not. It took
  Grab from 2 clusters to 24, turned a latent O(clusters × emails) cost in
  `discriminators` into an OOM crash, and cost a revert.
- **Discovery fed from the rail's own fetch could never grow.** The rail asks
  Gmail for `from:(domains it already parses)`, so an unknown sender's mail never
  arrives. The corpus hid it completely — `EmailCorpus` returns every sender.

### What's next

Ordered by what actually blocks something.

1. **Re-learn Grab under the plausibility bar, then fill a month and compare
   against the sheet.** The check should take the ride pattern to 0/11 and the
   food pattern to 5/10, forcing a retry that is now fed concrete failures.
2. **Grab's merchant anchors are still wrong** — 5 known issues in the fixture,
   pinned as they actually behave. They turn green when the anchors do.
3. **`flatText` is recomputed on every access outside `SenderTriage`** — every
   `canParse`, every `parse`, every gate excerpt strips the whole HTML body
   again. `Prepared` fixed the one hot spot; the real fix is flattening once on
   entry, which changes `CapturedEmail`'s shape and touches every parser. Do it
   on the timings, not on a hunch.
4. **The subject pass costs blu a third layout of 12 real receipts.** Removing it
   works and is measured — but takes Grab to 24 clusters and narrows the promo
   margin from 0.04–0.12 vs 0.88 to 0.41 vs 0.75. A live trade, worth taking on
   its own merits.
5. **Ship blockers, unchanged:** the whole capture pipeline is `#if DEBUG`, 82 MB
   of real mail ships in the bundle (Stage 0 #3), and there is still no test
   target — the fixtures run from a debug screen, not CI (Stage 2 #5).
6. **Smaller, real:** a refund is non-spend so it never offsets the card hold it
   reverses; a duplicate split across two bank charges (5.000 + 46.500 vs 51.500)
   cannot be caught by exact matching and is pinned unflagged.

   ✅ **A refund is a dedup problem, and is now handled as one.** One purchase,
   two rows, arriving weeks apart instead of a day apart — so it is found by the
   same fingerprint buckets `possibleDuplicate` uses and settled the same way:
   flagged as a pair, never merged. A refund now arrives saying *"Undoes TOKO
   ROTI MANIS on 20 Sep"*.

   The reason it needed its own pass rather than a widened duplicate check is
   the window. `Fingerprint.adjacent` is ±1 bucket, which is ±3 days — right for
   two rails reporting one purchase, useless for a reversal that takes a
   fortnight. Widening `dateWindowDays` for everyone would flood every duplicate
   check, so `Fingerprint.lookingBack(days:)` lets a caller that needs a longer
   reach say so and pay for it in fetches. Refunds are rare enough that it is
   cheap, and rare enough that only rows already read as `.refund` trigger it.

   Three tests, each stopping a specific wrong pairing: **exact amount** (same
   choice as `isSameCharge` — a tolerance wide enough for partials is wide
   enough to pair unrelated purchases), **same normalized merchant** (the test
   duplicates don't need and this one does: two Rp 50.000 charges a fortnight
   apart are ordinary, and the merchant is what says which one), and **the
   charge came first** (without it, two refunds in a window pair with each
   other).

   Still not netted, and that stays deliberate: the refund is non-spend, the
   purchase is spend, and a Rp 42.500 purchase you were refunded still reads as
   Rp 42.500 with its reversal beside it. Netting would be a non-spend row
   moving a spend total — a change to what a ceiling means, and the person
   holding the pair can now see it and decide.

   `reversalWindowDays` is 30 and is **unmeasured**, unlike `dateSlackDays`.
   There are 4 refunds in the corpus and not one of them has its original charge
   in it. Revisit on real pairs.

---

## Stage 4.5 — The second tool

### 13. `tag_purchase` · **L** — ✅ built, ⚠️ never run against real mail
The agent's second tool. Given a transaction — merchant, amount, date, sender —
propose which bucket it belongs to.

**Built:** `PurchaseTagger` + `TagMemory` (contracts), `DefaultPurchaseTagger`
(the memory-first layering), `FoundationModelTagger` (★ the model call),
`SwiftDataTagMemory` (the decision history, same container as the queue), and
the queue line that says where a suggestion came from. `GmailRail` tags a batch
after dedup and before the write; `DefaultApprovalService` records the decision
after the ledger append.

What it does NOT do, and why:

- **Never decides.** A suggestion pre-selects a chip on a `.pending` row. The
  gate is unchanged and Invariant 1 with it.
- **Never tags a row that isn't spending.** A refund, an arriving payment or a
  transfer has no bucket, and asking a model to pick one produces a confident
  answer to a question nobody asked. Neither does it tag a row a parser failed
  to read — that merchant is a subject line.
- **Never calls the model for a merchant you have settled.** That is a lookup.
  The model half is bounded at 8 calls per sync, because the feasibility run
  already produced one unbounded loop at 30.
- **Never accepts a bucket that isn't yours.** The model picks from the sheet's
  own category list, matched by exact name; anything else is a refusal and the
  row arrives untagged. No fuzzy matching — "Transport" against "Ride &
  Transport" *and* "Travel" is a bucket you didn't pick chosen by a rule nobody
  can read.

**The first version put the suggestion in the wrong place, and using it showed
that immediately.** Tagging ran once, at capture, and was frozen there. So:

- a sync of five rows from one merchant looked up what was known *before* you
  had settled any of them, and settling the first taught the other four nothing;
- a row already waiting in the queue from last week never got a suggestion at
  all, however much you had taught it since.

The suggestion was buried at the start of the pipeline, so everything the queue
learned went unused until the next fetch — which is the opposite of the design,
where the queue *is* the training signal.

The fix is to split the tool by cost rather than run it once:

| | when | what it does |
|---|---|---|
| `tag` | once, at capture | may call the model — 3.8s p95, bounded, off the render path |
| `refresh` | **every queue load** | memory lookup only; no model, no network |

`tag` is now a cache of the expensive half; `refresh` re-derives the cheap half
from what you have decided *by now*, and memory beats a stored model guess
whenever both exist. It writes only the rows whose suggestion actually changed,
and it will not touch a row whose provenance is `.manual` — that bucket is
someone's decision, not a slot to overwrite. Verified: three rows from one
merchant, nothing suggested at first; settle two and the third comes back
`groceries · memory(2 of 2)`, across a `HOKKY SUPERMARKET` / `hokky supermarket`
spelling difference.

**The dashboard was stale for the same reason** — it reloaded on sheet dismiss
and nothing else, so approving five rows moved nothing behind the sheet until it
closed. The queue now calls back per settled row (`onSettled`), and Home reloads
without forcing: `append` already invalidates the ledger cache, so the next read
is fresh for free. The forced reload on dismiss stays, for everything that
changed from somewhere else.

Four more things worth knowing that only came out of building it:

- **A suggestion must never be free to be right.** The first cut let memory
  suggest "not a spend" for a merchant you consistently mark that way. But an
  untagged row already *displays* as "Not a spend", so approving one unchanged
  would record an agreement nobody made — the hit rate measuring its own output,
  which is the exact failure mode the shadow run exists to avoid. A suggestion
  is now always a real bucket; a merchant you settle as non-spend gets no
  suggestion at all, and is not handed to the model either.

- **Manual entry seeds the memory for free.** `ManualEntry` promotes through the
  same gate, so every spend you type by hand records a decision with no
  suggestion attached — the tagger learns your regular shops before it has ever
  guessed at one, and those rows never touch the hit rate.
- **A retag has to survive the retag.** `amend` replaces the whole resolution,
  so the suggestion is re-attached explicitly. Without that the queue records
  what you chose and forgets what was offered, and the hit rate quietly becomes
  a measure of the rows nobody had to fix.
- **The suggestion has to be visible as one.** A pre-selected chip a person
  can't tell from their own decision gets approved as if it were, the app
  records agreement, and the scoreboard measures its own output. The queue says
  "you chose it 4 of the last 4 times here" — a count, not a confidence.

⚠️ **Unrun.** The whole path is wired and builds; nothing has watched a
suggestion arrive from real mail, and the scoreboard has no rows in it. Same
status as Stage 0 #1 was, and worth the same suspicion.

It is a genuinely different problem from pattern synthesis and must not be built
by copying it. Synthesis has an oracle: run the rule over held-out mail and see.
Tagging has none — whether `KAYABOYS1 SURABAYA` is *food* or *entertainment* is
your call about your own budget, and no amount of reading the email settles it.

So the design is inverted. Instead of *propose → verify → promote*, it is
**propose → you decide → accrue**:

1. The tool suggests a bucket; the row lands in the queue pre-tagged.
2. You approve, or you retag. Either way the app records what you chose against
   the normalized merchant.
3. Over time each merchant accumulates a hit rate — how often the suggestion
   matched your decision.

The four notes this was written against, and how each landed:

- **Deterministic first, model second.** Held. `DefaultPurchaseTagger` looks up
  before it asks. A merchant is "settled" at ≥2 decisions with ≥60% going one
  way — two bars, because one past decision is an anecdote and a merchant split
  evenly between two buckets is a merchant you have *not* settled. Suggesting
  the marginal winner there would be the app inventing a preference you don't
  have (Invariant 8).
- **`merchantRaw` is not the key.** Held, as `MerchantID(normalizing:)`. It
  folds case, collapses punctuation, and drops a trailing payment reference —
  `Grab* A-9MVBRDUGW7GDAV` and `Grab* A-7QQZZBBXX1PLMN` both key to `grab`, where
  before they were two merchants each seen once. Deliberately nothing else: no
  city stripping, no corporate suffixes. A rule that fires on a real name merges
  two shops invisibly, and shows up later as a tagger confidently wrong about a
  merchant you never actually settled. `7ELEVEN KEMANG` is why "mixes letters
  and digits" was not the rule.
- **Retagging is signal, not correction noise.** Held, and it needed explicit
  work: `amend` replaces the whole resolution, so the suggestion is re-attached
  by hand or the miss is erased.
- **Categories come from the sheet**, not a fixed list. Held — one read per
  batch, and a suggestion pointing at a bucket you have since deleted falls
  through to the model rather than proposing a row that would land nowhere.

### 14. Auto-commit · **M**, after #13 has run in shadow
Rows above the accrued-accuracy threshold skip the queue.

Do not build this before there is a month of shadow data. The entire question is
what the threshold costs, and that is measurable: run the tagger for a month
without acting on it, then count how often it would have matched you, per
merchant and overall. Only then pick a number.

**The shadow run is now recording**, which is the only part of this that was
blocking. `TagScoreboard` reports per-merchant agreement and an overall figure,
and the overall figure is printed with a warning next to it: auto is scoped per
merchant precisely because one number over every merchant hides the only
distinction that matters. Nothing routes on either. Come back when there is a
month of rows.

Everything else here is bookkeeping the trust ladder already implies —
`ApprovalService` promoting without a tap (Invariant 1 unchanged), a marker on
the row, an easy way to see and undo what was auto-committed, and a per-merchant
scope rather than a global switch.

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

**When something gets slower or crashes, suspect the property you called in a
loop.** `CapturedEmail.flatText` strips the whole HTML body through several
regexes on *every access*. Clustering called it once per email per cluster, which
was invisible at 2 clusters and an OOM at 24. `SenderTriage.Prepared` reads each
email once; nothing downstream should touch `flatText` again.

**Coverage is shape-fitting, not correctness.** It says "this pattern fits the
template", never "this pattern is right". Anything it clears goes to a person
flagged, and `verifiedAgainst: 0` is stamped deliberately so the artifact cannot
imply a measurement nobody made.

**`xcodebuild` incremental builds went stale mid-session** — reporting
BUILD SUCCEEDED while running zero compile steps, with the simulator launching a
nine-hour-old binary. Any "it builds" claim made that way is worthless. Use
`clean build` when a change appears not to take effect.

**When the sheet looks wrong, inspect it before theorising.** Settings →
Developer → Google API harness → *Inspect budgets + categories* dumps both tabs
verbatim and re-runs the app's own resolution over them: roots, unresolved
parents, id collisions once normalized, header integrity, and which columns each
of the last rows actually occupies.
