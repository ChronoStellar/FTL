# FTL — build order

Companion to `CLAUDE.md`, which says *how* to work. This says *what next*, and why
each thing sits where it does. `TESTING.md` is the third: every harness that
exists, what each measured, and — the part that matters — what is **not** tested
and what that costs.

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

### The target is an UNSEEN mailbox

Decided 2026-09-09, and it reorders most of what follows.

This is my mailbox, but the version being built is one that works on a mailbox
nobody has looked at: other banks, other merchants, other currencies, no
hand-written parser for any sender.

That is not a stretch goal, it is a different set of load-bearing assumptions,
and the audit below measures which of them hold. The short version: **the
deterministic funnel generalises and the verification does not.** Every
promotion path currently in the code runs through an oracle that an unseen
mailbox does not have.

Read every number recorded before this date as a number about *this* corpus.

### The agent has tools, and the tools are the loop

The agent is not a thing that reads your email. It is a small, bounded loop that
**calls tools**, and each tool's answer is checked by code before it counts.

| tool | what it proposes | what checks it | today |
|---|---|---|---|
| **learn a pattern** | where the fields sit in a sender's template, **and which way the money went** | `PatternVerifier` where an oracle exists; **coverage everywhere else** | ✅ built, ⚠️ shut out of the runtime path |
| **tag a purchase** | which bucket a transaction belongs in | the user's own approvals, accrued per merchant | ✅ built, ⚠️ never run against real mail |

⚠️ Read the first row's middle column carefully — the audit below put a number
on it. "Against emails the model never saw" is true, but *scored against what?*
On an unseen mailbox there is no oracle, so it is coverage, and coverage is
shape-fitting. A pattern that is 100% correct and one that reads a label instead
of a merchant are separated by eight points there.

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

> **Guardrail, revised 2026-09-09.** The original read: *if you find yourself
> hand-writing parser #3, stop — you are doing the model's job by hand.* That
> treated hand-written parsers as competing with the loop. They are its scarce
> INPUT: each one is an oracle, and oracles are the thing an unseen mailbox
> cannot produce. Two is a thin base to have calibrated a synthesizer on.
>
> So: a third parser is worth writing precisely when it would **disagree** with
> what the loop produced for that sender — as a test of the process, not as
> coverage. Writing one to make a sender work is still the wrong move; writing
> one to find out whether the loop can be trusted on a sender it has never seen
> is the whole point.

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
- **`AppEnvironment.liveWithoutSheet()`, DEBUG only** — a real mailbox with no
  Google Sheet behind it. Two reasons to have it: the app should be usable by
  someone who hasn't set one up, and stress-testing capture → discovery → tag
  against a real mailbox at volume has no business writing hundreds of test
  rows into anyone's real ledger. `ledger`/`budgets` swap to
  `InMemoryLedgerStore`/`InMemoryBudgetStore` (ephemeral, lost on relaunch —
  Invariant 7 still holds, there is simply no Sheet backing it);
  `provisional`/`captureLog`/`patterns`/`tagMemory` stay the SAME instances
  `.shared` uses, deliberately NOT a second `live()` call — that would open a
  second SwiftData container on the same on-disk file, the exact hazard
  `.shared`'s own doc comment already exists to prevent. Entry point:
  `SignInView`'s "Sign in without a spreadsheet (debug)", real Google
  sign-in, no Sheets scope needed. `DebugView` shows which backend is active
  (`AppEnvironment.LedgerBackend`) so a stress-test session and a real one
  are never visually the same screen. ⚠️ Unrun end to end — see the same
  caution as `DiscoverySync` below.

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

### 10a. Deepen a near-miss sender before writing it off · **S** — built, 2026-09-11

Raised directly from using the app: "if the model can only read from email
with high quantity that's a liability... the agent should be able to
generalize." Right — and worth being precise about what it does and doesn't
fix, because the wrong fix is lowering `minimumDistinctAmounts` or
`minimumProvisionalEvidence`. That trades statistical soundness for
coverage, the exact trade the constant-merchant defect (item 2 above) already
burned once — 81.9% coverage, 0% accuracy.

Two different failure modes were being named as one:

- **A sender has plenty of real mail; the ambient sweep's window just didn't
  happen to include it all.** `PatternDiscovery.candidates` only ever sees
  whatever the caller already fetched — `discoveryQuery`'s 180 days live, or
  a `TemporalHoldoutRunner` slice as narrow as 2 months. A low-*frequency*
  sender (used for years, rarely) can fail the volume floor purely because
  most of its history sits outside whatever window this sweep used, not
  because the evidence isn't real. Measured directly: the 2026-09-11
  temporal-holdout run, over a 2-month live slice, found Grab clearing
  discovery **zero** times — where the full frozen export's longer span
  found it twice (`grab.com/compliments`, `grab.com/diterbitkan`), and the
  ⚠️ *Expectation* note above already put a number on the same gap ("142
  emails across 15 senders, exactly one qualifies").
- **A sender genuinely doesn't send enough mail, ever, for a reusable
  template to be learnable.** No fetch strategy manufactures volume that
  isn't there. That is `PurchaseClassifier`'s job (Stage 5, #11) — read the
  one-off email directly, no template required, Invariant 6 flags what it
  can't handle and moves on — not discovery's. Still blocked on #6 and #12.

**Built, for the first failure mode.**
`PatternDiscovery.nearMisses(in:isRead:excluding:)` finds a sender with real
currency-marker signal that `candidates` didn't select for one of two honest
reasons: too little raw mail yet in THIS sweep to judge `distinctAmounts`
fairly (you cannot have 5 distinct amounts from 3 emails), or enough to look
transactional but short of the volume floor. Deliberately excluded: a
sender the sweep already saw *enough* of that still reads as a brochure —
that is a real answer (Apple's storage nag, Traveloka's discount campaign),
and re-fetching it every run would just spend a live call reconfirming a no.

`PatternDiscovery.run(fetching:isRead:knownSenders:)` now tops up each near
miss — bounded by `maxNearMissesPerRun`, kept separate from the model-call
budget `maxSendersPerRun` since a top-up spends a Gmail fetch, not a model
call — with one unrestricted `from:(domain)` query (`deepenFetchLimit`
capped, no date window; the same query shape `CorpusEmailSource` already
parses) before candidate selection runs. A thin-looking sender gets a fair,
fuller look before being judged; a genuinely rare one still fails, honestly,
on real evidence rather than a window artefact. Production
(`AppEnvironment.makeDiscoveryContext`) sets `maxNearMissesPerRun: 1`, same
"one sender per launch" tightening `maxSendersPerRun` already gets.

**Same fix, structurally, as the already-open 14-day backfill problem**
(Automation item 4, above): once a pattern exists for a sender, the rail
still only ever asks for its last two weeks going forward, so older mail is
invisible forever. A bounded, unrestricted `from:(domain)` top-up is the
answer to both "not enough evidence to learn from" and "learned it, now
can't see its history." **Not done here**: wiring the same top-up into
`GmailRail`/the capture log for the *post*-promotion case still needs "the
capture log to know which domains it has seen before," the exact
prerequisite the backfill item already named. Scoped out of this pass on
purpose — a bigger, separate change.

⚠️ `TemporalHoldoutRunner` does **not** get this for free — it calls
`PatternDiscovery.run(over:...)` on mail it already fetched itself, not
`run(fetching:...)`, so its 2-month Grab-never-clears result stands
unchanged until it is wired to top up too.

⚠️ Unmeasured, same honest label `minimumProvisionalEvidenceForKnownSender`
already carries: `minimumSignalForDeepening` (2) and `maxNearMissesPerRun`
(1 live, 3 default) are judgment calls, not tuned numbers. Watch them.

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

**Reordered 2026-09-09** by the audit, under the unseen-mailbox target. The old
order optimised the loop for *this* corpus; the first four items below are the
ones that decide whether it works on anyone else's.

#### Agent first — the decision, and what it takes

**Decided and done, 2026-09-09.** The runtime path used to have a hand-written
parser in front of the loop, and the precedence rule (`handWritten + learned`)
meant a learned pattern never read a blu email — the loop was shut out of
exactly the sender it could be verified against, so nothing ever accrued.
**The agent reads the mail now; hand-written parsers are oracles.**

What makes that safe is not the reference parser winning — it is the approval
queue, which every row passes through anyway (Invariant 1). A misread amount
costs a person seeing a wrong number in a queue built for that. The reference
parser in front was belt-and-braces on a system that already has a belt, and it
was the reason nothing could improve.

Items 1, 2 and 4 below are shipped. 3 and 5 are not, and both are load-bearing
for the unseen-mailbox target.

1. ✅ **The queue becomes tool 1's oracle.** Done — `PatternMemory`,
   `PatternObservation`, `SwiftDataPatternMemory`, recorded at the gate beside
   `TagMemory`, with a scoreboard at Settings → Developer → *Score the learned
   patterns*. `unverifiedPattern` is now a ladder rather than a permanent label:
   once the queue has kept ≥95% of a pattern's rows over ≥20 settled ones
   (`PatternTrustPolicy`), its rows stop being flagged — and drops take it back
   down, which is what makes it reversible. Verified: 20 approvals → vouched;
   2 drops → 91%, un-vouched.

   ⚠️ **The ladder only moved for NEW rows, and that was named as a gap and
   fixed 2026-09-11.** `GmailRail` stamps `unverifiedPattern` once, at
   capture, from whatever the vouch status was THEN — but a row already
   sitting in the queue when its pattern crosses the bar had no way to find
   that out, and stayed flagged forever unless re-synced. The identical shape
   of bug already named and fixed once for tagging ("frozen at capture...
   the wrong change", Stage 4.5 #13) had quietly reappeared in a different
   field. Fixed the same way: `ApprovalQueueViewModel.reviseUnverifiedFlags`,
   called from `load()` beside `tagger.refresh`, clears `unverifiedPattern`
   from a pending row whose `readBy` pattern is vouched *now* — sharing one
   trust check (`PatternTrustPolicy.vouched(among:using:)`) with `GmailRail`
   so "vouched" cannot mean two things depending on who asks.

   One direction only: a trust DROP does not retroactively re-flag an
   already-pending row here. That needs the full `ExtractionPattern` (to
   confirm `verifiedAgainst == 0` still holds, the same condition `GmailRail`
   checks at capture) rather than just a pattern id, and re-flagging a row
   someone may already be looking at is a different judgment call than
   quietly clearing a stale caution. Scoped out on purpose, not missed.

   ⚠️ **It is an ACCEPTANCE rate, not an accuracy**, and the scoreboard says so
   on screen. The queue cannot edit an amount or a merchant, so approving a row
   is a vote that it looked right, not a check that it was. Letting a person
   correct a figure in the queue is what turns this into the real thing — and
   the moment it does, `labels.json` stops being anything anyone needs.

   The original description of the work: The only thing that lifts a pattern
   off `.provisional` on an unseen mailbox, and it retires `labels.json` as a
   blocker. Approve → the pattern read right. Correct the amount or merchant →
   a labelled failure with the answer attached. Same mechanism `TagMemory`
   already uses; the pattern gets a hit rate that keeps moving instead of a
   number frozen at synthesis. It also makes template drift detectable, which
   it currently is not: `verifiedAgainst: 111` is a claim about one Tuesday.
2. ✅ **The constant-merchant check.** Done — measured first: real patterns read
   64–66 distinct merchants at 0.08–0.10 modal share; the label-reader reads
   **one** value at 1.00. The threshold sits at 0.5, 5× clear of every real
   pattern and half of the failure. It takes the label-reader from **81.9%
   coverage to 0.0%** and leaves blu-correct at 100% and the model's proposal at
   94% untouched. It also reaches the retry loop as a concrete miss.

   The two plausibility rules are complementary and neither subsumes the other:
   the window-edge rule catches Grab (no terminator, values vary), this catches
   the label reader (values do not vary). Cost, stated rather than discovered
   later: a sender whose counterparty genuinely never changes is refused, and
   refused means no pattern rather than a flagged one.

   The original description of the work: Closes the measured blind spot — 81.9%
   coverage at 0% correctness — and it is what makes a provisional row safe to
   act on. Deterministic, one pass, no model.
3. ~~**Currency generalisation.**~~ **Descoped 2026-09-09.** `IndonesianMoney`
   stays the only money parser, and an unseen mailbox in another currency reads
   nothing. That is a known and accepted limit, not an oversight: "unseen
   mailbox" means other banks and other merchants, not other currencies. The
   measurement stands in the audit if the scope ever widens — 32 emails in this
   corpus carry `$`/USD that nothing can read, and `Money` assumes zero minor
   units.

   What replaced it as the priority: **automation**.

#### Automation — the app runs itself up to the queue

Until 2026-09-09 nothing in this app ever ran without a tap. `rail.sync()` had
exactly one caller and it was inside `#if DEBUG`, so in a release build nothing
fetched anything, ever. The loop was real, verified, and manual.

The boundary is the one the invariants already draw, so this enforces rather
than bends it:

| stage | writes to | automated |
|---|---|---|
| fetch + parse | `ProvisionalStore` | ✅ recoverable by definition (Invariant 7) |
| dedup + reversal pairing | flags on pending rows | ✅ recoverable |
| tag | a suggestion on a pending row | ✅ recoverable |
| approve | the **ledger** | ❌ never — Invariant 1, `.assist` |

**Everything up to the queue runs itself; the queue is where you show up.**

- ✅ **A. A trigger.** `AutoSync` (`services/Capture/`), owned by
  `AppEnvironment` so the throttle survives view rebuilds. Fires on first
  appearance of the signed-in shell (always) and on every return to `.active`
  (throttled to 15 minutes). Home reloads only when the queue actually grew —
  `syncIfDue` returns that, so a foreground that found nothing costs no Sheets
  read. Errors are swallowed: nobody asked for this sync, so nobody is waiting
  on an answer, and an error banner for a background fetch reports something the
  person cannot act on. Visible at Settings → Developer → **Auto-sync**.
- ✅ **B. Out of `#if DEBUG`.** `AutoSync` is the non-DEBUG caller, so the
  capture path now runs in a release build. The Debug button stays as a dev
  tool. Checked: no `#if DEBUG` remains anywhere in the capture path, and
  `gmail.readonly` is requested unconditionally at sign-in.
- ✅ **C. Discovery → synthesis → promote, unattended.** — built, ⚠️ **never run**.
  `DiscoverySync` (`services/Capture/`), triggered from its own `.task` on
  `ContentView`'s first appearance, alongside `autoSync` rather than chained
  after it — discovery fetches its own 180-day window independently
  (`PatternDiscovery.discoveryQuery`), so it does not need the ordinary sync to
  go first. Feeds `PatternDiscovery.run(fetching:isRead:)` a live
  `GmailExporter` instead of the frozen `EmailCorpus`, and persists whatever
  clears a bar (`.promoted` or `.provisional`) straight to `PatternStore` — the
  same two cases the Debug screen's manual "Discovery" button already
  persists, same call site shape (`report(_:)` in `DebugView`).

  **Call budget, and why it's tighter than the manual button:** `maxSendersPerRun: 1`,
  not the default 3 — "one sender per launch" is the literal bound, enforced by
  a `hasRun` flag with no timer, because the object's lifetime already *is* the
  launch (`AppEnvironment` and `DiscoverySync` are both built once per process).
  A failed run (offline, no model) does not set `hasRun` — see `AutoSync` for
  the same reasoning: nothing was spent, so nothing is owed back.

  **`isRead` reuses the rail's own precedence, not a second definition of it.**
  `GmailRail.activeParsers()` went from `private` to internal so
  `DiscoverySync` can call it through `AppEnvironment.makeDiscoveryContext()` —
  duplicating that precedence (learned patterns, then presets, then any
  hand-written parser) is exactly how "unread by discovery" and "unread by the
  rail" would have drifted apart.

  **Unrun, and worth the same suspicion as every other "built" item here**
  (Stage 0 #1, tool 2): it type-checks and a clean `xcodebuild` passes, but
  nobody has watched it find a sender on a live mailbox, persist a pattern,
  and had that pattern show up in the next `GmailRail.sync()`. On *this*
  mailbox the audit already predicts what that would look like — idle, because
  after blu and Grab nothing else clears the volume and variance bars at this
  corpus size (see *Automation*, ⚠️ Expectation). The honest first test is
  either a re-exported mailbox with more senders, or a longer stretch of real
  use.

**`BGAppRefreshTask` is deliberately not taken yet.** It adds Info.plist surgery
and a scheduler whose failure mode is silent, on top of a capture path that has
never run unattended even once. Prove foreground first.

⚠️ **Expectation, from the audit:** even with C working perfectly, on this
mailbox the agent will appear to do nothing. 878 emails across 70 senders the
rail never fetches, 142 carrying Rp across 15 senders, and after the volume and
variance gates exactly **one** qualifies — Grab, already learned. Correct,
automatic, and visibly idle. The loop gets work at a 3,000–5,000 email
re-export, or as new senders accumulate.
4. ✅ **Retire the hand-written parser from the runtime path.** Done. blu ships
   as a preset *pattern* (`Fixtures/preset-patterns.json`), `parsers: []` in
   `makeGmailRail`, and `BluReceiptParser` keeps the one job only it can do —
   being the oracle. Precedence is now `learned + presets`, then hand-written;
   see `GmailRail.activeParsers` for why the old order had quietly become the
   reason nothing could improve.

   ⚠️ **The backfill problem was misdiagnosed and is still open.** It was
   written up as "unfamiliar mail is logged `.skipped` and never revisited".
   That is wrong: the rail queries `from:(domains it can parse)`, so an unknown
   sender's mail is never fetched and therefore never logged at all. The real
   gap is the **14-day window** — when a pattern is promoted for a new sender,
   the rail only ever asks for that sender's last two weeks, and everything
   older is invisible forever. Fix is a wider window on a sender's first sync,
   which needs the capture log to know which domains it has seen before.
5. **Widen `LanguageGate` on measurement.** It refuses 36% of money mail at the
   strict setting, and `[.english]` is known to be narrower than the model's 21
   locales. Measure, then widen — not the other way round.

#### Still true, still queued

6. **Re-learn Grab under the plausibility bar, then fill a month and compare
   against the sheet.** The check should take the ride pattern to 0/11 and the
   food pattern to 5/10, forcing a retry that is now fed concrete failures.
7. **Grab's merchant anchors are still wrong** — 5 known issues in the fixture,
   pinned as they actually behave. They turn green when the anchors do.
8. **`flatText` is recomputed on every access outside `SenderTriage`** — every
   `canParse`, every `parse`, every gate excerpt strips the whole HTML body
   again. `Prepared` fixed the one hot spot; the real fix is flattening once on
   entry, which changes `CapturedEmail`'s shape and touches every parser. Do it
   on the timings, not on a hunch.
9. **The subject pass costs blu a third layout of 12 real receipts.** Removing it
   works and is measured — but takes Grab to 24 clusters and narrows the promo
   margin from 0.04–0.12 vs 0.88 to 0.41 vs 0.75. A live trade, worth taking on
   its own merits.
10. **Ship blockers, unchanged:** the whole capture pipeline is `#if DEBUG`, 82 MB
    of real mail ships in the bundle (Stage 0 #3), and there is still no test
    target — the fixtures run from a debug screen, not CI (Stage 2 #5).
11. **Smaller, real:** a duplicate split across two bank charges (5.000 + 46.500
    vs 51.500) cannot be caught by exact matching and is pinned unflagged.

#### Done: manual entries missed as duplicates — 2026-09-10

✅ Reported directly: the same purchase landed once as a manual entry and
again from its own receipt email, days apart, and `possibleDuplicate` never
fired. `isSameCharge`'s 1-day slack was measured against two AUTOMATED
rails — a bank notification and a merchant receipt, both stamped at or near
the moment of purchase (see the Grab measurement above). `ManualEntry` has no
way to backdate a row to when the purchase actually happened — Add Spend has
no date field, so a manual row is always stamped at whenever a person opened
the app and typed it in, which can be days after the fact. The 1-day rule was
correct for the case it was measured against and silently wrong for this one.

Fixed with a second, wider slack (`manualDateSlackDays`, 5 days) that applies
only when a manual entry is one side of the pair — the measured 1-day case
for two automated rails is untouched. The candidate SEARCH also had to widen
to match: `Fingerprint.widened(byDays:)`, new, distinct from the existing
`lookingBack(days:)` a refund search uses. `lookingBack` reaches mostly
backward because a refund is always chronologically after the charge it
reverses; a manual entry can land on EITHER side of its own receipt's date
(logged early, or logged late), so this needed a symmetric search instead.

⚠️ **Unmeasured, unlike `dateSlackDays`.** Five days is a judgment call — wide
enough to cover "logged it a few days late", narrow enough that two unrelated
purchases of the same round amount within a week stay rare — not a number
pulled from a corpus of real manual-entry timing, because there isn't one yet.
Revisit once there are enough real pairs to look at.

**Root cause still open:** widening the match is a safety net, not a fix for
why the date was wrong in the first place. Add Spend still has no way to
backdate an entry to when a purchase actually happened — worth doing on its
own merits, independent of dedup.

#### Done: refunds

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

## End-to-end from an empty state — 2026-09-10

`Settings → Developer → End-to-end · empty state`. The one harness that starts at
NOTHING: no preset, no hand-written parser, no learned pattern, no memory, no
capture log. `Fixtures/empty-state-corpus.json` — 100 invented emails, six
senders, each sitting on one side of one gate so a failure names the gate rather
than "the pipeline is off".

    ① 100 emails fetched, 0 read      with no parser the sender query is EMPTY,
                                       so it asks for everything and reads none
    ② discovery picks 3 of 6           three refusals, three different gates
    ③ 3 patterns stored, 1 refused     dompetku's counterparty never changes
    ④ 45 rows queued, all flagged      nothing verified them
    ⑤ a suggested bucket per row       observed, never asserted
    ⑥ approve 20 → vouched → unflagged the queue as the only oracle

Three things it demonstrates that nothing else covered:

- **The constant-merchant check, end to end.** dompetku is rejected after four
  attempts — every one anchored on `Tujuan`, which is followed by the same string
  in every email. There is no better anchor, so no retry can save it.
- **The retry loop, visible in a version number.** nusabank promotes as `:2`. The
  scripted first attempt leaves the merchant anchor with no terminator, the value
  runs to the window edge, `implausibility` refuses it, and attempt two — fed
  that concrete miss — adds the terminator.
- **A sender's rare layouts are invisible.** nusabank sends 2 refunds and 2
  incoming; triage keeps the dominant subject cluster, so the model only ever saw
  purchases and proposed a pattern that does not claim the others. Asserted at
  zero rather than discovered later.

⚠️ **The synthesizer is SCRIPTED** (`ScriptedSynthesizer`). This measures the
machinery — verifier, retry, plausibility, promotion, trust — and says nothing
about what a real model would propose. The repo had `UncallableLearner`, which
asserts the model is never reached; nothing exercised what happens when it is.

⚠️ **The tag column is observed, not asserted.** The tagger's model half runs for
real when the device has one, so that column is not deterministic. Everything
asserted is.

### First real-device run — 2026-09-10

The model half fired: **45 queued · 8 pre-tagged**, exactly the call budget.

| merchant | suggested | reading |
|---|---|---|
| `KEDAI KOPI LARAS` (coffee shop) | Food | right |
| `BENGKEL MOTOR RAPI` (motorbike workshop) | Transport | defensible |
| `APOTEK SEHAT JAYA` (pharmacy) | **Subscriptions** | wrong — and there is no Health bucket to be right with |

Cold-start quality on a four-bucket taxonomy, which is exactly what the shadow
scoreboard exists to count. Not a defect; a data point, and the first real one.

**The run also exposed a budget bug.** Every merchant that appeared twice got a
suggestion on its first row and nothing on its second — `APOTEK SEHAT JAYA`
Rp 84.000 tagged, `APOTEK SEHAT JAYA` Rp 52.000 blank. The model was being asked
once per ROW, so a batch of 45 rows across ~20 merchants spent all 8 calls on the
first 8 rows and left later rows from merchants it had **already answered**
untagged.

Memory cannot cover that gap: it fills only from approvals, and
`minimumDecisions` is 2, so a merchant seen exactly twice in one batch never
benefits from its own first row. Fixed by caching the model's answer per
normalized merchant for the duration of a batch — the same 8 calls now buy 8
merchants instead of 8 rows.

**That fixed repeats within a merchant; it left WHICH merchants get the 8
calls to accident of order — 2026-09-10.** On a cold-start sync (no memory
yet, so every merchant is a candidate) with more than 8 distinct merchants in
the batch, the calls went to whichever 8 were reached first while iterating
the batch — which, since Gmail tends to return newest mail first, meant
"whichever merchants happen to be newest," not "whichever merchants would
benefit the most." A ten-row regular could sit untagged behind eight
one-off rows. Symptom in the queue: a handful of tagged rows read as if the
tagger barely worked, when it had actually spent its whole budget — just not
where it would have shown.

Fixed the same way the repeat-within-a-merchant bug was: change what the
budget buys. `DefaultPurchaseTagger.tag` now counts, per batch, how many
TAGGABLE ROWS each candidate merchant has (not distinct appearances — a
ten-row merchant outranks ten one-row merchants), and spends the 8 calls on
the highest counts first. Deterministic, no model call spent deciding it —
one pass over what `tag` was already computing.

Paired with a queue fix, because prioritising the calls doesn't help if the
result is still invisible: the approval queue sorted by `createdAt` (when a
row was CAPTURED) descending, so a big first sync clumped everything by fetch
recency regardless of tag status. Now sorted by the transaction's own date,
oldest first (`ApprovalQueueViewModel.sorted`), with that date shown on every
card (`ApprovalQueueSheet`) — tagged and untagged rows interleave in the
order a person actually recognises their spending, rather than by whichever
order Gmail happened to return the mail in. Flagged rows still sort first
within that — unchanged, they are the ones that actually need a person.

⚠️ Unmeasured past the code review: nobody has watched this on a real
cold-start sync with more than 8 distinct merchants — that needs either a
bigger mailbox than this one currently produces, or the wider re-export the
ROADMAP already calls for elsewhere.

### Failures carry their evidence, and the model reads it

A failure that says only "expected 3, got 2" sends a person hunting. Every
assertion now attaches what the run itself computed — per-sender triage counts
against the live gate values, the concrete misses out of `PatternFeedback`, the
active patterns' provenance, the `PatternRecord` behind a trust decision.

Verified by breaking a gate on purpose (`minimumDistinctAmounts` 5 → 11):

    Stage ② discovery — "senders worth a model call" produced 1, expected 3
      - nusabank.example.com: 29 money mail · 25e/22d
      - kirimin.example.com:  20 money mail · 10e/9d 10e/10d
      - dompetku.example.com: 10 money mail · 10e/10d
      - gates — distinct ≥ 11, volume ≥ 10 per layout

The cause is readable off the page: the floor is 11 and the layouts have 9 and
10. **`FailureExplainer` narrates exactly that** and is forbidden to go past it —
it is handed the evidence and a terse stage map, never asked "why did the
pipeline fail", which is an invitation to invent a story about code it cannot
see. It is instructed to explain the EARLIEST failing stage only, and to say
"the evidence does not say" rather than guess.

Its answer is labelled a guess on every run, because nothing checks it. That is
the one place in this app where a model's prose reaches a person — allowed
because the false positive is recoverable in the cheapest possible way: you open
the file it named, find nothing, and ignore it. No row moves.

The report exports to a file (`ShareLink`), same idiom as the pipeline and
coverage runs: a run whose output only exists on a phone screen cannot be diffed
against the last one.

---

## Audit — 2026-09-09 · the loop with the oracle taken away

Run over the real 1,000-email export, against the shipping sources. The question
was not "does the loop work on my mail" — that was answered — but **what an
unseen mailbox would experience**, where no hand-written parser exists for any
sender.

✅ **This is now a live toggle, not just a one-off offline run — 2026-09-10.**
`AppEnvironment.pureAgentMode` (Settings → Developer → Discovery), off by
default. On, it drops blu's preset from `makeGmailRail` and swaps
`ParserOracle(BluReceiptParser())` for `NoOracle()` in
`makeDiscoveryContext`'s learner — the two hand-authored crutches this audit
already measured the app leaning on. With it on, blu has to be rediscovered,
relearned and promoted through the exact coverage-only path a genuinely
unseen sender takes, on a REAL mailbox, not the frozen export. Motivated
directly: "what if we're not using the premade parser at all — the agent
will recognize the pattern on its own", and the honest answer to that
question needed something you could actually flip and watch, not another
paragraph asserting it already works.

⚠️ **Unrun** — same status as everything else marked built-not-watched in
this file. The expected result, from the audit below and from Stage 4's own
"the loop closed, on device, against real mail" run: blu should get
rediscovered, reach `.provisional` (never `.promoted` — there is no oracle to
clear the bar with), and every row it produces should arrive flagged
`unverifiedPattern` until the queue itself vouches for it over ≥20 settled
rows at ≥95% (`PatternTrustPolicy`). If blu instead fails to be discovered at
all, or the promoted pattern reads worse than the ~94–99% already measured
for it, that is new information this toggle exists to surface.

### First real run, pure agent mode — 2026-09-10

**It worked — blu was rediscovered and relearned on a real mailbox, and
tagging read better than before.** The first actual evidence that "the agent
recognises the pattern on its own" is not just a claim this codebase makes
about itself. Reported directly: "it actually work quite well the tag is
better we just missed a bit more emails."

✅ **The missed emails, diagnosed and fixed.** Two gaps, both real:

- **Money mail from a known sender that matched no active layout was
  silently `.skipped`, with no queue row and no way to ever see it.** This
  is the gap one level earlier than the one Invariant 6's existing exception
  already covers — a template that matched but had a field missing
  (`.incomplete`) was already flagged; a template that matched NOTHING was
  not. Fixed: `GmailRail.sync()` now flags it instead
  (`RuleID.unclaimed`, a new `ParserOrigin.unclaimed` badge) — a person sees
  "no pattern claimed this" in the queue and can record it by hand, rather
  than the spend disappearing with only a debug log entry to show for it.
  Costs nothing structurally; it's the same fallback `.incomplete` already
  used, one branch earlier.
- **Rare layouts from an already-known sender couldn't clear the volume
  floor.** blu's refunds and other minority subjects are a small fraction of
  its mail (CLAUDE.md: 116 emails, ten subjects, 95 identical) — likely too
  few to reach the 10-email `evidenceFloor` (`maxExamples` 5 +
  `minimumProvisionalEvidence` 5) that gate was built to ask "is this sender
  even real". For a sender with an ALREADY active pattern, that question is
  already answered. Fixed: `PatternSynthesisPolicy
  .minimumProvisionalEvidenceForKnownSender` (2, floor 7 total) applies
  instead, for any sender in a new `knownSenders: Set<String>` parameter
  threaded through `PatternDiscovery.candidates`/`run` — computed by
  `DiscoverySync` from `patterns.active()`'s sender domains, and by
  `DebugView`'s manual discovery button from its own active-parser list, for
  the same behaviour in both places.

⚠️ **`minimumProvisionalEvidenceForKnownSender` is a judgment call, not a
measurement**, unlike the 5 it's relaxing from. A genuinely rare layout (1–3
emails total) still can't clear even the relaxed floor of 7, and correctly
falls back to the flagged-`.unclaimed` path above rather than being forced
through a synthesis attempt with no real holdout to verify against. Revisit
once there are real minority-layout runs to measure instead of one report.

### The ceiling: without an oracle, nothing is ever promoted

| candidate pattern | true accuracy | coverage — what the loop SEES | verdict |
|---|---|---|---|
| correct (the parser expressed as a pattern) | 100.0% | 100.0% | **provisional** |
| the model's real proposal | 94.0% | 94.0% | **provisional** |
| wrong anchor, right shape | 0.0% | 0.0% | rejected |
| merchant reads a label, not a name | **0.0%** | **81.9%** | rejected |

A **perfect** pattern — 100% correct over 116 emails — still only reaches
`.provisional`, because promotion runs through `verify`, and `verify` needs an
oracle. On a mailbox with no reference parser, `attempted == 0` for every
sender, forever.

So on unseen mail, **every row from every learned pattern arrives flagged.** Not
sometimes. The 0.95-over-≥20 bar is unreachable by construction, and the honest
description of what the loop delivers there is *a shape that fits, for a person
to check* — not a trusted rule.

This is the circularity the design has always had, now with a number on it:
`ParserOracle` makes the loop rigorously verifiable exactly where a hand-written
parser already covers the sender, i.e. exactly where the pattern is redundant.

**The queue is the only oracle an unseen mailbox generates.** Approving a
learned-pattern row is a vote that it read correctly; correcting the amount or
the merchant is a labelled failure with the right answer attached. That is the
same mechanism tool 2 already uses, pointed at tool 1 — and it retires
`labels.json` as a blocker, because the app produces labels as it is used.

### Coverage's blind spot, measured

The last row of that table is the one to worry about. It reads the **same string
out of every email** — a label, not a merchant — and scores 81.9% coverage at 0%
correctness. It was refused by an 8-point margin against a 0.90 threshold. That
is luck, not a safety margin.

> Coverage catches an anchor that reads NOTHING. It cannot catch an anchor that
> reads the SAME WRONG THING every time.

Cheap deterministic fix, and it belongs before the loop runs unattended: a
merchant that is identical across a sender's mail is a label. One pass, no
model, and it covers the case the existing plausibility rule (*runs to the
window edge*) does not.

### What generalises, and it is the half that was doubted

The discovery funnel is entirely deterministic and it holds up. Judged with no
oracle anywhere, and with blu treated as just another unknown sender:

| sender | Rp mail | layouts | qualifying | variance |
|---|---|---|---|---|
| blubybcadigital.id | 116 | 2 | **2** | 0.91, 0.88 |
| grab.com | 65 | 2 | **2** | 0.91, 1.00 |
| email.apple.com | 21 | 1 | 0 | 0.08 |
| your.traveloka.com | 16 | 2 | 0 | 0.08, 0.33 |

blu discovers itself. The two brochure senders are refused on variance, exactly
as designed. The executor, the schema, the queue and the tagger's accrual are
all sender-agnostic.

### What is hard-coded to THIS mailbox

- **`IndonesianMoney` is the only money parser.** 32 emails in this corpus carry
  `$`/USD that nothing can read, 2 carry `€`. On a non-Indonesian mailbox the
  pipeline reads **zero**. `Money` also assumes no minor units, which is right
  for IDR and wrong for almost everything else — USD and EUR need cents before
  they would even be right.
- **`LanguageGate` refuses 36% of money mail** (93 of 258) at the strict
  `.classification` setting the tagger uses. `supported = [.english]` was
  already documented as narrower than the model's 21 locales; this is the bill.

### Two things recorded earlier that the audit corrected

- **Replacing `BluReceiptParser` is nearly free — and "nearly" was itself a
  correction.** It was first written up as a trade (112/112 for ~99%); that
  figure belonged to a different anchor configuration. Expressed with its own
  terminator list and its own `Total`/`Amount` fallback, the parser is **exactly
  reproducible as a pattern on the four extracted fields** — 116/116, zero
  disagreement on amount, merchant, kind or subtype.

  Then the swap was run through the whole rail, and the audit's own blind spot
  showed up: comparing four fields cannot see a difference in the fifth thing.
  **Three fixture cases moved**, none of them losing a row or a number:

  | case | before | after | why |
  |---|---|---|---|
  | `blu-transfer-flags-ambiguous` | `ambiguousKind` | no flag | the parser INFERRED a transfer from a bank name beside an account number and flagged its own inference; a pattern matches the literal `Admin Fee` and types it, which is a stated fact |
  | `blu-transfer-to-another-person` | `ambiguousKind` | no flag | same |
  | `blu-promo-never-queued` | `notAPurchase` | `skipped` | the parser claimed every blu email and said no; the preset's `subjectContains` means nothing claims it at all |

  Both losses are of SIGNAL, not of correctness, and neither is recoverable
  inside the schema: the inference was `banks.contains && hasAccountNumber` and
  an anchor has no vocabulary for it. Pinned as `knownIssue` rather than quietly
  re-baselined, and `PipelineCaseRunner` now runs the SHIPPING configuration —
  a fixture on the old precedence would have been measuring a code path the app
  no longer takes, which is exactly how these three stayed invisible.
- **The direction markers were necessary and not sufficient.** Adding them to
  the model's real proposal changed nothing: 109/116 → 109/116. All seven
  failures are `unread`, not mislabelled — blu's refunds and incoming transfers
  never produce a row at all, because the proposal's merchant terminators
  (`Amount | bluVirtual | Admin Fee`) do not appear in those layouts. Add
  `Transaction Date` / `Transaction ID` and it goes **94.0% → 97.4%**, clearing
  the bar. The markers fix labelling; the reading was failing one step earlier.
  Good news: that is a retry, not a schema gap — the feedback reads
  `merchant: got nothing, expected "004502609698"`, the same concrete-miss form
  that corrected blu twice already.

### The discovery gate was measuring the wrong thing — found by the mock corpus

Building the empty-state fixture surfaced this before its runner even existed,
which is the fixture paying for itself on day one.

`amountVariance` is not a variance. Per email it collects the **set of every Rp
figure in the first 1500 characters** — total, fee, subtotal, anything — and then
divides the number of DISTINCT such sets by the email count. As a question
("did this document's figures differ from the sender's others?") that is well
chosen. As a **ratio** it had one structural fault:

> its denominator is your mail count, so it is bounded above by
> (distinct fingerprints) ÷ (how much you use the sender)

A warung with one line item and five prices scores 0.50 at ten receipts and
**0.10 at fifty** — indistinguishable from a brochure. The more you use a
merchant, the less learnable it becomes, which is backwards for an app whose
premise is learning the senders you actually transact with. The first draft of
the mock corpus hit it immediately: the happy-path sender scored 0.32 and was
refused.

**Fixed by gating on the absolute count instead.** Measured over the real corpus,
it separates the same senders more cleanly and does not move with volume:

| | distinct fingerprints |
|---|---|
| blu · blu/bluvirtual | 50 · 35 |
| grab/compliments · grab/diterbitkan | 10 · 10 |
| apple · traveloka · mandiri | **1 · 1 · 1** |

Every brochure produces exactly one. `minimumDistinctAmounts = 5` sits in a 10×
gap rather than on a tuned edge. Selection on the real corpus is **unchanged** —
blu and Grab, same as before — and the `pipeline-cases` fixture still picks
swiftpay and still refuses `deals.example.com`. So the fix costs nothing and
removes the volume coupling.

### A second "defect" that the measurement disproved

Worth recording because it is exactly the kind of thing a later session will
re-propose.

`hasCurrencyMarker` reads the whole email; `amounts` reads only the first 1500
characters. So a sender whose figures sit deeper yields an EMPTY set for every
email — one distinct set over n — and is refused at `1/n`. Traveloka scores
0.077, which is exactly 1/13, and **100% of its mail** has no figures in the
head. klikbca, a real bank, has a third of its mail in the same state. It looked
like a silent conflation of "unreadable" with "repeated", and the obvious fix was
to fall back to the whole body when the head yields nothing.

**Measured, that fix is wrong.** The fallback takes Traveloka from 1 fingerprint
to **14** and turns a brochure into a candidate — its body is full of
promotional prices that differ between campaigns.

So the head window is not a blind spot, it is the thing making the metric mean
something: it restricts attention to the transaction block, and **a promotion has
no transaction block**. Finding no figures there is the honest signal, not an
artefact. Traveloka is refused for the right reason after all.

The residual concern — a genuine receipt sender with a long HTML header being
refused the same way — has no example in the corpus: blu and Grab both have
zero blind emails, and klikbca's three are below every floor regardless. Left
alone, deliberately, and recorded so it is re-measured rather than re-argued.

### Tool 2, on the same mail

94 blu spend rows across 38 distinct merchants. The 12 merchants seen twice or
more cover 68 rows — **72% of tagging is eventually a lookup**; the other 26 are
one-offs needing a model call.

`MerchantID(normalizing:)` is doing the heavy lifting: it folds **22 distinct
spellings of `Grab* A-…` into one key**, plus the `bigA bakehouse` /
`BIGA BAKEHOUSE` case the design was written against. Without it those are 22
merchants seen once each — a model call every time. With it, one merchant seen
22 times, settled after two.

**And that same fold found a flaw.** All Grab spending collapses to `grab`,
rides and food together. Tag those into different buckets and `settled()`
correctly refuses to suggest — no bucket holds 60% — and then `tag` falls
through to the model, every sync, forever. **The most-seen merchant gets the
most model calls.** Two ways out:

- *cheap:* distinguish "no history" from "history that will not settle". 22
  decisions split 12/10 is not a merchant a model can help with; skip it rather
  than ask. Three lines, and clearly right under an unseen-mailbox target.
- *structural:* key on merchant AND layout, so `grab/ride` and `grab/food`
  accrue separately. Bigger, and the tag key stops being just the merchant.

---

## Stage 4.5 — The second tool

### 13. `tag_purchase` · **L** — ✅ built, ⚠️ never run against real mail
The agent's second tool. Given a transaction — merchant, amount, date, sender —
propose which bucket it belongs to.

**Scope, settled 2026-09-09:** the agent learns which *spending* belongs to each
tag. It does **not** invent tags. Assigning a purchase to a bucket you already
set up is a description of what you did; creating a bucket drags in a ceiling
the app would have to pick, which is Invariant 8, and a write to the canonical
budgets tab, which is Stage 0.5's whole cautionary tale. `unallocated` already
exists as the answer to "no bucket fits". If agent-proposed categories ever
happen, they take the shape Settings already uses for missing categories —
listed, one-tap add, ceiling from the person.

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

⚠️ **And the normalization found a flaw the design didn't anticipate.** Measured
over the real corpus: 72% of blu's spend rows are eventually answerable by
lookup, and `MerchantID(normalizing:)` is what buys that — it folds 22 spellings
of `Grab* A-…` into one key. But all Grab spending then collapses to `grab`,
rides and food together. Tag those into different buckets and `settled()`
correctly refuses to suggest (no bucket holds 60%), and `tag` falls through to
the model **every sync, forever**. The most-seen merchant gets the most model
calls. Fix is open — see the audit section for the two options.

⚠️ **The model half is gated out of 36% of money mail.** `FoundationModelTagger`
runs at `.classification`, the strict setting, and `DefaultLanguageGate` refuses
93 of 258 money emails in the corpus. That is the right strictness for an answer
nothing verifies, and it is also a measured ceiling on how much of the queue the
model half can ever reach.

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

✅ **The Grab merchant key — decided 2026-09-10: structural.** `MerchantID
(normalizing:)` folded 22 spellings of `Grab* A-…` into `grab`, which is what
made 72% of tagging a lookup — and also collapsed rides and food into one key,
so the most-seen merchant got a model call every sync forever, never able to
settle. Raised again independently via Shopee — the same shape of problem on a
second platform, not a Grab-only quirk.

Built: `TagKey` (`model/Contracts/TagMemory.swift`) — `merchant` AND `layout`
(the TEMPLATE `entry.readBy` names, not its raw RuleID — see the correction
below). `grab.com/compliments` (a ride) and `grab.com/diterbitkan` (a food
order) now accrue as two separate histories under the same merchant name
instead of one that could never settle. Sourced from `readBy` rather than
`provenance` deliberately — the same reason the rail already keeps the two
apart: `provenance` is overwritten by a retag, and the accrual key has to
describe what actually produced the row's content, not whatever it was last
corrected to. `TagContext`, `DefaultPurchaseTagger`, `SwiftDataTagMemory`,
`TagDecisionRecord` (new `layoutKey` column, defaults nil for every row
written before it existed) all follow this key now instead of bare
`MerchantID`.

⚠️ **Honest limit, not a bug:** this only recovers what the SOURCE EMAIL
actually distinguishes. Grab's own receipt differs by service; a bank's
generic notification for the same charge (`Grab* A-XXXX` via blu) does not
name a service at all, so rows read that way still share one layout — the
information was never captured to begin with, and no key scheme recovers what
isn't there. The cheap fix ("stop asking once history won't settle") was NOT
built on top of this — `worthAsking` already stops asking once a key's own
history is a genuine split, which is now scoped narrowly enough (per layout,
not per whole-merchant) that it should fire far less often than before.
Revisit if it doesn't.

**Correction, same day: the first version used the raw RuleID, and that
broke more than it fixed.** Reported as "the tag scope is smaller now" —
merchants that used to have a settled suggestion no longer did, and not just
Grab or Shopee. Cause: `ExtractionPattern.id` always carries a trailing
`:version`, so `entry.readBy?.rawValue` is not "which template read this
row", it's "which NUMBERED ATTEMPT at that template" — and a pattern gets a
new version every time it is re-synthesized, including by `DiscoverySync`
running unattended. Keying tag accrual on the raw RuleID meant EVERY
learned-sender merchant's whole tag history was silently orphaned on every
re-promotion, a far bigger and more general effect than the deliberate
Grab/Shopee split above. Fixed with `ExtractionPattern.templateIdentity(of:)`
— strips the same trailing `:N` `namesPattern` already knows how to find, so
`grab.com/compliments:1` and `grab.com/compliments:2` accrue as one key. Both
the read side (`TagContext.layout`) and the write side
(`DefaultApprovalService.recordDecisions`) have to agree on this or the bug
just moves; both now call the same function.


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
