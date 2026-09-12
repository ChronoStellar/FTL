# FTL — what has actually been measured

Companion to `CLAUDE.md` (how to work) and `ROADMAP.md` (what next). This one is
the evidence: every harness that exists, what it covers, what it does **not**,
and the numbers each produced with the date they were taken.

Numbers here are facts about a run, not permanent properties. Where one is
re-measured and moves, the old figure stays with its date — a measurement that
quietly changes is worse than no measurement, because it destroys the record of
what was believed when a decision was made.

Last full re-verification against shipping source: **2026-09-10**.

---

## The four lanes, and why they are separate

| lane | tool | speed | determinism | what it can tell you |
|---|---|---|---|---|
| **1. Data prep, labelling** | Python, offline | — | n/a | what the corpus contains |
| **2. Pure rules, parsers, `Money`** | ⚠️ **no test target** | ms | total | nothing yet — see the gap below |
| **3. Pipeline harnesses** | Debug screen | seconds | total | does the wiring do what it claims |
| **4. Model measurement** | Debug screen, on device | ~minutes | **none** | what the model actually does |

Lane 4 is not a test. It is a measurement run whose product is a number you can
argue with, and it is nondeterministic by nature. Never assert on it.

> ⚠️ **Lane 2 does not exist.** There is no Unit Testing Bundle in this project
> — `xcodebuild -list` shows one target, `FTL`. Adding it is one click in Xcode
> and cannot be done from the CLI. Everything below in lane 3 therefore runs
> from a **debug screen, not CI**, which means nothing here can fail a build.
> This is `ROADMAP.md` Stage 2 #5 and it is the single largest gap in this file.

---

## Lane 3 — the harnesses that exist

All four live under `Settings → Developer`.

### 1. Fixture cases · `PipelineCaseRunner`

`Fixtures/pipeline-cases.json` — 26 synthetic emails with their answers
attached, run through the **real rail**: real parsers, real precedence, real
dedup, real reversal pairing, real provisional writes. Only the mailbox and the
stores are swapped.

Three properties it was built for:

- **Committable** — no merchant anyone visited, no names, no account numbers.
  `FTL/test/` is gitignored and 82 MB; this lives in the repo.
- **Expectations, not just data** — each case states the verdict, amount,
  merchant, kind and flags it must produce. `[]` for flags is a real assertion:
  a flag that fires on everything is worthless, so cases that must stay quiet
  say so.
- **Pinned patterns** — the learned Grab patterns are in the file, so the
  executor runs with no model, no device and no network.

**Result 2026-09-10: 26 cases, 0 unexpected failures.** Three are `knownIssue`
(see *What the preset swap cost*).

Since 2026-09-09 it runs the **shipping configuration** — `parsers: []`, blu via
its preset. A fixture on the old precedence would have been measuring a code
path the app no longer takes, which is exactly how three behavioural differences
stayed invisible until the swap was run end to end.

### 2. End-to-end from an empty state · `EndToEndRunner`

The only harness that starts at **nothing**: no preset, no hand-written parser,
no learned pattern, no memory, no capture log. `Fixtures/empty-state-corpus.json`
— 100 invented emails, six senders, each sitting on one side of one gate so a
failure names the gate rather than "the pipeline is off".

**Result 2026-09-10: all assertions held.**

| stage | asserted | result |
|---|---|---|
| ① empty state | 100 fetched, **0 read** | ✓ |
| ② discovery | 3 of 6 senders selected | ✓ |
| ③ learn | 3 patterns stored, 1 refused | ✓ |
| ④ sync again | 45 queued, **all flagged**, 0 refunds through | ✓ |
| ⑤ tag | *observed, never asserted* | — |
| ⑥ settling | not vouched at 19, vouched at 20, rows unflagged | ✓ |

The six senders and the gate each one tests:

| sender | n | gate |
|---|---|---|
| nusabank | 25 + 2 refunds + 2 incoming | happy path, plus two layouts below the volume floor |
| kirimin | 20 (10 + 10) | one subject is **not** one layout |
| promo.tokobagus | 15 | refused on **variance** — 1 distinct figure-set |
| warungkopi | 6 | refused on **volume** |
| kabar | 20 | refused by the **currency** filter |
| dompetku | 10 | qualifies, then the **constant-merchant** check refuses its pattern |

Three things it demonstrates that nothing else covers:

- **The constant-merchant check end to end.** dompetku is rejected after four
  attempts, every one anchored on `Tujuan`, which is followed by the same string
  in every email. No retry can fix an anchor with no better alternative.
- **The retry loop, visible in a version number.** nusabank promotes as `:2` —
  the scripted first attempt leaves the merchant anchor with no terminator, the
  value runs to the window edge, `implausibility` refuses it, and attempt two,
  fed that concrete miss, adds the terminator.
- **A sender's rare layouts are invisible.** nusabank's 2 refunds and 2 incoming
  never arrive: triage keeps the dominant subject cluster, so the model only saw
  purchases. Asserted at zero rather than discovered later.

> ⚠️ **The synthesizer is SCRIPTED** (`ScriptedSynthesizer`). This measures the
> machinery — verifier, retry, plausibility, promotion, trust — and says
> **nothing** about what a real model would propose. The repo already had
> `UncallableLearner`, which asserts the model is never reached; this is the
> first thing that exercises what happens when it is.
>
> ⚠️ **The tag column is observed, not asserted.** The tagger's model half runs
> for real when the device has one, so that column is not deterministic.

**Failures carry their evidence.** Every assertion attaches what the run itself
computed — per-sender triage counts against the live gate values, concrete
misses out of `PatternFeedback`, active patterns' provenance, the `PatternRecord`
behind a trust decision. Verified 2026-09-10 by raising `minimumDistinctAmounts`
5 → 11 in a scratch copy:

```
Stage ② discovery — "senders worth a model call" produced 1, expected 3
  - nusabank.example.com: 29 money mail · 25e/22d
  - kirimin.example.com:  20 money mail · 10e/9d 10e/10d
  - dompetku.example.com: 10 money mail · 10e/10d
  - gates — distinct ≥ 11, volume ≥ 10 per layout
```

The cause is readable off the page. `FailureExplainer` narrates exactly that and
is forbidden to go past it — it gets the evidence and a terse stage map, and is
never asked "why did the pipeline fail", which invites inventing a story about
code it cannot see. Its answer is **labelled a guess on every run**, because
nothing checks it.

### 3. Pipeline over the real corpus

The rail over `test/gmail_export.json` (1,000 real emails), exporting the ledger
rows it produced. Not assertion-based — it is for looking at what a real mailbox
does to the pipeline.

### 4. Coverage report

Which emails carry Rp, which are readable, and by what. Also not assertion-based.

---

## Lane 4 — model measurement

| harness | what it measures | determinism |
|---|---|---|
| **Pattern synthesis · blu / Grab** | what the on-device model proposes | none |
| **Learn what's unread** | discovery → synthesis over the corpus | none |
| **Model probe** | isolates one variable of a prompt at a time | none |
| **Tagging · shadow scoreboard** | how often the tagger matched *your* approvals | grows with use |
| **Patterns · what the queue said** | acceptance rate per learned pattern | grows with use |

> ⚠️ The last two measure an **acceptance rate, not an accuracy**. The queue
> cannot correct an amount or a merchant yet, so approving a row is a vote that
> it looked right, not a check that it was. Both screens say so.

---

## The measurements themselves

### Pattern direction — refunds and money arriving · 2026-09-10

`PatternVerifier.verify` compared amount and merchant only until 2026-09-09, so
a pattern could get the **direction of the money** wrong on every email and
still score 1.00. Measured on the fixture's blu subset, markers the only
difference:

| | |
|---|---|
| no direction markers | 7/12 · **58%** · 4 scored misses on `kind` |
| + refund / incoming / transfer markers | 11/12 · **92%** |

The four-email gap is the entire point: before the change both patterns scored
identically, because the four the first got wrong were never checked. (The
twelfth is a merchant anchor missing on one layout — the same in both runs, and
not what is being measured.)

### Coverage's blind spot · 2026-09-09, re-verified 2026-09-10

`coverage` judges a value in isolation, so it catches an anchor that reads
**nothing** and cannot catch one that reads the **same wrong thing every time**.
Measured against the real corpus:

| candidate pattern | true accuracy | coverage — before | coverage — after |
|---|---|---|---|
| preset (the parser as a pattern) | 100.0% | 100.0% | **100.0%** |
| the model's real proposal | 94.0% | 94.0% | **94.0%** |
| **anchored on a LABEL** | **0.0%** | **81.9%** | **0.0%** |

That last pattern was refused only by an 8-point margin against the 0.90 bar —
luck, not a safety margin. The threshold that closed it was chosen from a
measurement, not taste:

| pattern | reads | distinct merchant values | modal share |
|---|---|---|---|
| blu, correct | 116 | 66 | 0.08 |
| blu, model's real proposal | 109 | 64 | 0.08 |
| grab ride / food, learned | 11 / 10 | 11 / 10 | 0.09 / 0.10 |
| **blu, anchored on a label** | 95 | **1** | **1.00** |

`constantMerchantShare = 0.5` sits 5× clear of every real pattern and half of
the failure. The two plausibility rules are complementary: the window-edge rule
catches Grab (values vary, no terminator), this catches the label-reader (values
do not vary).

**Cost, stated rather than discovered later:** a sender whose counterparty
genuinely never changes is refused, and refused means no pattern rather than a
flagged one. Most such senders never reach here — a fixed counterparty usually
comes with fixed amounts, which the variance gate refuses first.

### The discovery gate was measuring the wrong thing · 2026-09-09

Found by building the mock corpus, before its runner existed.

`amountVariance` is not a variance. Per email it collects the **set of every Rp
figure in the first 1500 characters** and divides the number of distinct such
sets by the email count. As a question that is well chosen. As a **ratio** its
denominator is your mail count, so it is bounded above by (distinct
fingerprints) ÷ (how much you use the sender):

```
5 fingerprints, 10 receipts → 0.50 ✓     5, 20 receipts → 0.25 ✗
5 fingerprints, 50 receipts → 0.10 ✗  — indistinguishable from a brochure
```

**The more you use a merchant, the less learnable it becomes.** The first draft
of the mock corpus hit it immediately: the happy-path sender scored 0.32 and was
refused.

Fixed by gating on the absolute count. Measured over the real corpus:

| | distinct fingerprints |
|---|---|
| blu · blu/bluvirtual | 50 · 35 |
| grab/compliments · grab/diterbitkan | 10 · 10 |
| apple · traveloka · mandiri | **1 · 1 · 1** |

Every brochure produces exactly one. `minimumDistinctAmounts = 5` sits in a 10×
gap. **Selection on the real corpus is unchanged** — blu and Grab, same as
before — and `pipeline-cases` still picks swiftpay and still refuses the
brochure.

### A defect the measurement DISPROVED · 2026-09-09

Recorded because a later session will otherwise re-propose it.

`hasCurrencyMarker` reads the whole email; `amounts` reads only the first 1500
characters. A sender whose figures sit deeper yields an empty set for every
email — one distinct set over n — refused at `1/n`. Traveloka scores 0.077,
exactly 1/13, and **100% of its mail** has no figures in the head. klikbca, a
real bank, has a third of its mail in the same state.

It looked like a silent conflation of "unreadable" with "repeated". **The
obvious fix is wrong:** falling back to the whole body takes Traveloka from 1
fingerprint to **14** and turns a brochure into a candidate.

The head window is not a blind spot — it is what makes the metric mean
something. It restricts attention to the transaction block, and **a promotion
has no transaction block**. Traveloka was being refused for the right reason.

### What the preset swap cost · 2026-09-09

Retiring `BluReceiptParser` from the runtime path was measured as free on the
four extracted fields — 116/116, zero disagreement on amount, merchant, kind or
subtype. **Comparing four fields cannot see a difference in the fifth.** Run
through the whole rail, three fixture cases moved:

| case | before | after | why |
|---|---|---|---|
| `blu-transfer-flags-ambiguous` | `ambiguousKind` | no flag | the parser INFERRED a transfer from a bank name beside an account number and flagged its own inference; a pattern matches the literal `Admin Fee` and types it, which is a stated fact |
| `blu-transfer-to-another-person` | `ambiguousKind` | no flag | same |
| `blu-promo-never-queued` | `notAPurchase` | `skipped` | the parser claimed every blu email and said no; the preset's `subjectContains` means nothing claims it |

Both are losses of **signal**, not correctness, and neither is recoverable in
the schema — the inference was `banks.contains && hasAccountNumber`, and an
anchor has no vocabulary for that. Pinned as `knownIssue` rather than quietly
re-baselined.

### The merchant key · 2026-09-10

`MerchantID(normalizing:)` folds case, punctuation and trailing payment
references:

```
"bigA bakehouse SURABAYA"       → "biga bakehouse surabaya"
"BIGA BAKEHOUSE SURABAYA"       → "biga bakehouse surabaya"
"Grab* A-9MVBRDUGW7GDAV"        → "grab"
"Grab* A-7QQZZBBXX1PLMN"        → "grab"
"7ELEVEN KEMANG"                → "7eleven kemang"    (NOT treated as a reference)
```

Measured over blu's real spend rows: **94 rows across 38 distinct merchants; the
12 seen twice or more cover 68 rows — 72% of tagging is eventually a lookup.**
The fold does the heavy lifting: 22 spellings of `Grab* A-…` become one key.
Without it those are 22 merchants seen once each, and every one is a model call.

### The trust ladder · 2026-09-10

`PatternMemory` + `PatternTrustPolicy`, measured against a pattern's own rows:

```
start              no evidence
10 approvals       10/10 = 100%   not yet vouched
19 approvals       19/19 = 100%   not yet vouched
20 approvals       20/20 = 100%   VOUCHED — rows stop being flagged
then 2 drops       20/22 =  91%   not vouched — the ladder came back down
```

Reversible by construction, per Invariant 10. `ExtractionPattern.namesPattern`
correctly separates a learned pattern (`zenpay.example.com:1` → true) from a
hand-written one (`blu-receipt` → false), so queue evidence about somebody's
Swift never inflates the loop's number.

### Sequential accrual · 2026-09-10

Three rows from one merchant, nothing suggested at first. Settle two and the
third comes back `groceries · memory(2 of 2)` — **across a
`HOKKY SUPERMARKET` / `hokky supermarket` spelling difference**. This is the
`refresh()` path; before it existed, tagging ran once at capture and a decision
taught the rest of the queue nothing until the next fetch.

### First real-device run · 2026-09-10

The model half fired: **45 queued · 8 pre-tagged**, exactly the call budget.

| merchant | suggested | reading |
|---|---|---|
| `KEDAI KOPI LARAS` (coffee shop) | Food | right |
| `BENGKEL MOTOR RAPI` (motorbike workshop) | Transport | defensible |
| `APOTEK SEHAT JAYA` (pharmacy) | **Subscriptions** | wrong — and no Health bucket exists to be right with |

Cold-start quality on a four-bucket taxonomy. Not a defect; the first real data
point, and exactly what the shadow scoreboard exists to count.

**It also exposed a budget bug.** Every merchant appearing twice got a suggestion
on its first row and nothing on its second — the model was asked once per **row**,
so 45 rows across ~20 merchants spent all 8 calls on the first 8 rows and left
later rows from merchants it had already answered untagged. Fixed by caching the
answer per normalized merchant for the batch: the same 8 calls now buy 8
merchants instead of 8 rows.

### Ledger dedup — `capturedAt` is not a transaction time · 2026-09-12

Replayed the real 137-row ledger (`test/ftl-ledger-rows.tsv`) through
`LedgerDeduplicator`. Both reported symptoms — duplicates reaching the Sheet
AND legitimate rows being swallowed — were **one root cause**.

`SheetsSchema` writes the date with `dayFormatter` ("yyyy-MM-dd", fixed UTC),
so a purchase's time of day does not survive the write. Every row
`LedgerStore.all()` returns is at midnight, and the first version of the
matcher filled that gap with `capturedAt` — **the time the sync ran**. In this
ledger 130 of 137 rows share the single value `2026-09-08T08:47:47Z`.

| | old rule | shipped rule |
|---|---|---|
| matched as duplicate | 29 of 137 | **21 of 137** |
| provably wrong | **9** | **0** |
| cross-day matches | 9 (1–61 days apart) | 0 — all same-day |

The 9 wrong ones, all silently dropped: `Google YouTubePremium` Rp 76,590
matched against itself **31 days apart** (a monthly subscription), BCA
transfers 22 and 53 days apart, `WARUNG MBAK YULI` 8 days apart, `KAYABOYS1`
6 days apart, and two pairs 60–61 days apart.

Two directions, one cause:

- **Duplicate passed through.** Fresh entry carries a real time from the email
  (19:58); the stored row fell back to its sync stamp (08:47); the 15-minute
  proximity test saw an 11-hour gap on the same day and returned "distinct
  charges". The window was comparing a purchase against a sync.
- **Real spending swallowed.** Two stored rows both resolved to a nil stamp
  and fell through to `true`, while `capturedSameDay` — true for any pair from
  one sync — made the day gate unable to reject anything at all.

**Shipped:** exact amount + currency, matching merchant, same calendar day.
Nothing finer, because nothing finer survives the write. 21 matches, **19 of
them cross-rail** (blu's `Grab* A-…` card notification against Grab's own
`Pengemudi … Diterbitkan` receipt) — the double-count already measured at 10%
of spending in 2026-09-08's audit.

⚠️ **One case no threshold resolves:** two `Grab* 9879131c5fa5de5d` rows,
Rp 24,000, same day, identical merchant string. One ride counted twice and two
identical rides are the same bytes. Auto-drop is kept (decided 2026-09-12), so
this one is guessed — and every auto-drop now logs the ledger row it matched
(`PipelineDebugStub.recordSettlement`), because a dropped row is still marked
promoted and the log is the only route back to it.

**The same bug was in the capture gate, found by reading the fix back.**
`GmailRail.isPossibleLedgerDuplicate` compared `entry.transaction.date` (a real
purchase time) against `tx.capturedAt` (the sync clock) and refused the match
past 15 min same-rail / 2 h cross-rail. So the gate whose whole job is to
**show** you a duplicate had gone quiet:

| | flagged `possibleDuplicate` |
|---|---|
| with the `capturedAt` test | **2** of 137 |
| without it (shipped) | **22** of 137 |

Of the 22: 20 are the cross-rail Grab double-count, 2 are three identical
Rp 24,000 rows on one day — the case nothing can resolve, and the one a flag
rather than a drop exists for.

16% of the queue, against `isSameCharge`'s own 39/137 and the 48/137 already
rejected as too noisy — so it stays under this file's own bar, *"a flag that
fires on a third of the queue trains people to approve past it."*

⚠️ A first pass at this measurement read **42 of 137 (31%)** and nearly got the
fix abandoned as too noisy. That number used ledger rows as proxies for
incoming entries and so counted **both** members of every duplicate pair, where
the real flow only ever flags the second one to arrive. Simulating arrival in
date order gives 22. Worth recording: the noise bar and the measurement of it
have to agree about which side of a pair gets flagged.

**The merchant test was the real blocker, found from live sheet rows · 2026-09-12.**
Everything above matches *automated* rails against each other, where both sides
describe the merchant in the merchant's own words. The duplicates actually
sitting in the sheet were **manual ↔ email**, and no string rule reaches them:

```
"glazed donut"      ↔ MIDNIGHT DONUTCITRALAND SURABAYA    Rp 12,432  29 Aug
"MMBN Legacy Vol2"  ↔ WL *STEAM PURCHASE                  Rp 166,080 29 Aug
"salad"             ↔ HOKKY SUPERMARKET SURABAYA          Rp 38,000  30 Aug
```

You cannot derive "Steam" from "MMBN Legacy Vol2" lexically — that needs to know
what the game is. What identifies them is arithmetic: same amount, same day, one
typed and one parsed. **Shipped:** when a pair crosses the manual boundary the
merchant test is skipped rather than loosened — a test that can only ever answer
"no" is not evidence. Only when *exactly* one side is manual; two typed rows
should still resemble each other, two parsed rows always do.

Catches all 3 pairs. The 137-row corpus is unchanged at 21, because nothing in
it crosses that boundary.

⚠️ **The false-positive rate of this arm is UNMEASURED** — the recorded ledger
has no manual rows at all, so there is nothing to measure it against. The risk
is real and nameable: type Rp 50,000 on a day an unrelated Rp 50,000 email
lands, and they merge. Bounding it from the automated side, 4 of 24 same-amount
same-day clusters in the corpus are genuinely different merchants
(`GOOGLE *ANDROID TEMP` vs a Rp 10,000 refund; `BIGA BAKEHOUSE` vs
`WARUNG MBAK YULI`) — all email↔email, so out of scope here, but they are what
this arm would look like if it were wrong.

**Bank ↔ commerce, and the 1000× read hiding underneath it · 2026-09-12.**
The other duplicate class: the bank's card notification and the platform's own
receipt. Found the pair in the export —

```
bank      blu              WL *STEAM PURCHASE    Rp 166,080   29 Aug
commerce  steampowered.com "Mega Man Battle…"    Total: Rp 166 080   29 Aug 21:50
```

**The structure, which the Grab hardcode was hiding:** a bank descriptor names
the PLATFORM; the platform's receipt names the ITEM. `WL *STEAM PURCHASE` vs a
game title; `Grab* A-…` vs a driver's name. No lexical rule connects those. So
the hardcoded Grab arm is replaced by a general one: does a platform-shaped
token on one side (≥4 chars, not payment noise) appear in the OTHER side's rule
id — which is its sender domain? Reproduces all 20 Grab pairs the hardcode
caught (the other 2 are an identical-string triple the exact arm already
matches) and adds none — there is no commerce-side row in the 137-row corpus.

⚠️ **And dedup could never have worked for Steam anyway**, because the amount
was wrong before it got there. `IndonesianMoney` matched `([\d.]+)` — dots
only — and Steam writes `Total: Rp 166 080` with **spaces** grouping thousands.
So it read **Rp 166**, and the two sides of the pair were three orders of
magnitude apart. The same thousandfold error this file was written to prevent,
through a separator nobody had seen.

Measured over all 1,000 emails in the export before changing it:

| | |
|---|---|
| parses that change | **11** |
| of those, steampowered.com | **11** |
| blu emails affected | **0** — the 116/116 parser is untouched |

Every change is a 1000× correction (166 → 166,080; 519 → 519,000; 699 →
699,000). Only exact 3-digit groups extend a match, so an unrelated figure
sitting after an amount cannot be swallowed into it.

⚠️ **If a Steam pattern was ever promoted before today, the rows it wrote are
in the sheet at 1/1000th of their value** and no dedup pass will pair them with
the bank row. Those need finding and fixing by hand; the parser fix only
corrects what arrives from here.

⚠️ **Not tested:** whether the two rails ever disagree on the AMOUNT for one
purchase. On this corpus all 21 pairs agree exactly, so exact-amount matching
costs nothing here. A rail that rounds differently would slip through, and the
fix is not a tolerance — ±Rp5,000/±3d was already measured wrong (48/137
flagged, 29 of them incorrectly) in the 2026-09-08 audit.

### Temporal holdout, first real run · 2026-09-11

`TemporalHoldoutRunner`, live Gmail, `pureAgentMode`'s default (`NoOracle` —
no ground truth, coverage-only). Trained on 692 real July–September 1 emails,
tested on 114 real September 1–11 emails, compared against the real Sheet.

**Training: only blu cleared discovery.** `findings.count == 1` — no second
sender was even attempted in this window, Grab included. Two layouts learned,
both provisional, both **100% coverage**:

| layout | held out | coverage |
|---|---|---|
| `blubybcadigital.id/-` | 38 | 100% |
| `blubybcadigital.id/bluvirtual` | 26 | 100% |

0 promoted — expected, `NoOracle` never promotes (see *The ceiling* in
`ROADMAP.md`).

**Test: those two self-taught patterns read 21/114 September emails with zero
retraining.** This is the first real evidence the loop generalises **forward in
time** on live mail, not just across senders in the frozen 2026-09-07 export —
genuinely new, and worth recording as a positive result on its own.

**And it surfaced a real defect the frozen corpus never would have.** Two of
the 21 rows — both refunds (`kind: nonSpend`) — read `merchantRaw` as:

```
004502609698 Transaction Date & Time 08 Sep 2026 19:58:53 WIB Transaction
Type Online Debit Refund Location Domestic
```

The merchant field ran straight past the amount into the notification's own
metadata. This is the exact failure shape already named in *Two things
recorded earlier that the audit corrected* (`ROADMAP.md`) — a proposal whose
merchant terminators don't include `Transaction Date` / `Transaction ID`
misreads blu's refund/transfer layouts — fixed once, by hand, for a different
pattern instance. Because synthesis is a model call, a fresh, unconstrained
run on real mail regenerated the same gap on its own, and **coverage scored
both patterns 100% anyway** — coverage asks whether a field reads something at
all and looks distinct across merchants, not whether what it read is clean.
Nothing here currently checks merchant-field *quality*, only presence and
diversity.

Not a dedup break, at least: the second garbled row shares its date and exact
amount (Rp 38.687, 8 Sep) with a genuine Grab charge read the same day, so
Invariant 5's reversal pairing — fingerprint-based, not merchant-text-based —
should still catch it. It would just display terribly in the queue if this
pattern were ever promoted.

**Unconfirmed, worth a look:** one spend row, `HENDRIK NICOLAS... BCA 5271
9632 39` at Rp 400.000, reads as `.spend`. If that's a transfer to the user's
own account it should be `.nonSpend` under Invariant 5. Flagged, not
diagnosed — needs the user to confirm what the transaction actually was.

⚠️ **What this run did NOT show — do not read it as closing either open
gate:**

- **`minimumProvisionalEvidenceForKnownSender` was never exercised.** It only
  applies to a sender's *second* layout once one is already active, and only
  one sender cleared discovery at all in this window. Still unmeasured.
- **`TagKey` (merchant + layout) was not exercised.** `TemporalHoldoutRunner`
  checks tagging by merchant only, by its own design (see the file header) —
  and the compare step found **0 real spend rows in the Sheet's September
  window**, so the tag-accuracy number is undefined (0/0), not a pass.

Re-run once a training window produces a second sender or a known sender's
rarer second layout, and once September has real approved rows to compare
against.

---

## What is NOT tested, and what that costs

Ordered by how much it would hurt to be wrong.

1. **Almost nothing has run against live Gmail.** One real fetch (2026-09-09,
   confirmed the provenance line flips to `blubybcadigital.id:1`) and one
   on-device end-to-end run. Everything else is fixtures and the recorded
   corpus.

   **There is a precedent for why that matters.** A parser scored **116/116 on
   the recorded corpus and read 3 of 112 real emails**, because the live shape
   differed from the recorded one — same sender, same parser. Corpus-verified is
   the weakest verification in this repo's history. Treat "it passes the
   fixtures" as a hypothesis.

2. **Stage 0 #1 is still unverified.** Nobody has watched a provisional row
   survive a force-quit and relaunch. It is wired and it builds. That is not the
   same thing, and captured spending disappearing silently is the worst failure
   this app has.

3. **No test target, so nothing can fail a build.** Every harness here is a
   button on a screen a person has to remember to press.

4. **The model's own proposals are only measured on device, by hand.** The
   end-to-end harness scripts them. `AddSpendIntent.perform()` has never run at
   all.

5. **`AutoSync` has never been observed doing its job unattended.** It is the
   first thing in this app that runs without a tap, and its whole failure mode
   is silence.

6. **Auto-commit has no shadow data.** `TagScoreboard` and the pattern
   scoreboard are both near-empty. `ROADMAP.md` #14 is correctly blocked on a
   month of it.

---

## How to add a measurement here

The discipline this file exists to hold, in four lines:

- **Measure before changing a threshold.** Two proposed fixes were killed by
  their own measurements in one session.
- **Record what a change COSTS**, not only what it fixes. The preset swap's
  three moved cases were found by running the whole rail, not the four fields.
- **Keep a disproved idea with its evidence.** It gets re-measured rather than
  re-argued.
- **Never assert on the model.** Observe it, date it, and say which run it came
  from.
