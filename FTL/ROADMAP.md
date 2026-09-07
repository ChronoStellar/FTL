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

### 1. Persist the provisional cache · **M**
`InMemoryProvisionalStore` → `GRDBProvisionalStore` in `services/Persistence/`.

Rows awaiting approval do not survive a relaunch. Captured spending silently
disappearing is the worst failure this app has, and it lands on the human gate
every safety guarantee depends on. It is also where synthesized patterns will
eventually be stored — the loop needs somewhere durable to keep what it learned.

*Done when:* add an expense, force-quit, relaunch, it's still queued.

### 2. Verify the live Sheets path · **S**
Sign in, add one expense, approve it, look at the sheet.

`SheetsLedgerStore` builds but has **never run authenticated**. Until a row
round-trips, the foundation is unproven. Likely failure points: tab bootstrap,
column mismatch — both obvious from the error.

### 3. Get `sample.json` out of the shipping bundle · **S**
6.6 MB of your real email metadata compiled into the app. `#if DEBUG`, or move it
to a test-only target.

---

## Stage 1 — Get real emails flowing

### 4. Gmail rail, blu only · **M**
Not "email capture". One sender.

`BluReceiptParser` already handles **116/116** sub-millisecond, so every remaining
unknown is plumbing rather than extraction. Two payoffs at once: the app starts
working while you aren't looking, **and** fresh emails start arriving for the loop
to learn from later. A pattern learner with no incoming mail is a demo.

Needs: `GmailRail` (incremental sync via `historyId`), a cursor in the persistent
store, a way to trigger a fetch.

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
