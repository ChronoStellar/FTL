# FTL — continuing the agent's development

A session-starter prompt, not a third source of truth. Read `CLAUDE.md` (how to
work, the invariants) and `ROADMAP.md` (what's next and why) first — this file
exists only to answer one narrower question they don't organize around: **where,
exactly, does the model touch this codebase, and what is the state of each
place today.** Paste this whole file as your opening prompt when you want a
session to work specifically ON the agent, not just around it.

Last updated 2026-09-11. If it disagrees with the code, the code is current —
say so rather than trusting this file blindly.

---

## The shape, restated for this lens

Three model call sites exist in this app, and only three. Everything else —
capture, dedup, the ledger, the queue UI — is deterministic code or a human
gate, and stays that way (`CLAUDE.md`, *The design principle*). Development on
"the agent" means development on one of these three, or on the deterministic
machinery immediately around them (the loop driver, the verifier, the trust
ladder). If a change would route deterministic work through the model, or add
a fourth call site, stop and say so — that is the one rule everything below
sits inside.

---

## Entry point 1 — Pattern synthesis (tool 1: the agent reads mail)

**The model call itself**
`FoundationModelSynthesizer.propose(from:feedback:)` —
[services/Agent/FoundationModelSynthesizer.swift](services/Agent/FoundationModelSynthesizer.swift).
Reads ≤5 examples, emits an `ExtractionPattern`. Gated by `LanguageGate`
per-example (Invariant 9), not per-prompt — a boilerplate footer in one
language must not veto a whole sender.

**The loop that drives it**
`DefaultPatternLearner.learn(senderDomain:from:policy:)` —
[services/Pipeline/DefaultPatternLearner.swift](services/Pipeline/DefaultPatternLearner.swift).
propose → verify → feed back concrete misses → retry, bounded by
`PatternSynthesisPolicy.maxAttempts` (4). The model never decides when it's
done; this file does.

**The deterministic scorer that makes the loop safe**
`PatternVerifier` — [services/Pipeline/PatternVerifier.swift](services/Pipeline/PatternVerifier.swift).
Two oracle shapes, same protocol (`PatternOracle`): `ParserOracle` (a
hand-written parser as ground truth — only ever blu) and `NoOracle` (no ground
truth at all, forces the coverage-only path every genuinely unseen sender
takes). Plausibility checks live here too — the constant-merchant check, the
window-edge check — both deterministic, no model.

**Where it picks its own targets (no model call spent deciding)**
`PatternDiscovery.candidates(in:isRead:knownSenders:)` /
`.run(over:isRead:knownSenders:)` —
[services/Pipeline/PatternDiscovery.swift](services/Pipeline/PatternDiscovery.swift).
Deterministic funnel: currency marker → unclaimed by any active layout →
clusters into a template (`SenderTriage`) → its figures actually move
(`minimumDistinctAmounts`) → worth a call. `knownSenders` (added 2026-09-10)
relaxes the volume floor for a sender that already has one active pattern —
see *Recent, agent-relevant* below.

**Live, unattended trigger**
`DiscoverySync.runIfDue()` — [services/Capture/DiscoverySync.swift](services/Capture/DiscoverySync.swift).
Fetches its own 180-day window (`PatternDiscovery.discoveryQuery`), independent
of the ordinary sync. Bounded to `maxSendersPerRun: 1` and to once per launch
(a `hasRun` flag with no timer — the object's lifetime is the launch). Wired
into `ContentView`'s own `.task`, alongside `autoSync`, not chained after it.

**Manual/offline trigger** — Settings → Developer → Google API harness →
*Learn a pattern for blu* / *Discovery*. Runs against the frozen
`EmailCorpus`, not live Gmail — useful for repeatable testing, not for
extending real reach.

**The crutch-removal toggle**
`AppEnvironment.pureAgentMode` — [services/AppEnvironment.swift](services/AppEnvironment.swift).
Settings → Developer → Discovery. On: drops blu's preset from
`makeGmailRail`, swaps `ParserOracle(BluReceiptParser())` for `NoOracle()` in
`makeDiscoveryContext`. **Currently defaults ON for testing** — flip it or
remove the temporary default before treating OFF as the shipped behaviour
again (see `pureAgentMode`'s own doc comment).

**The trust ladder that makes a provisional pattern eventually stop being
flagged**
`PatternMemory` / `PatternTrustPolicy` — the approval queue is the only oracle
an unseen sender ever gets; ≥20 settled rows at ≥95% kept unflags a pattern's
`unverifiedPattern` rows. Read on every `GmailRail.sync()`
(`vouchedPatterns`).

---

## Entry point 2 — Purchase tagging (tool 2: the agent proposes a bucket)

**The model call itself**
`FoundationModelTagger.propose(for:among:)` —
[services/Agent/FoundationModelTagger.swift](services/Agent/FoundationModelTagger.swift).
Refuses (returns nil) rather than accepting a bucket outside the sheet's own
category list — no fuzzy matching.

**The expensive entry — may call the model, budgeted**
`DefaultPurchaseTagger.tag(_:)` —
[services/Pipeline/DefaultPurchaseTagger.swift](services/Pipeline/DefaultPurchaseTagger.swift).
Called from `GmailRail.sync()` on **new rows AND backlog rows together**
(fixed 2026-09-10 — it used to run only on the batch just parsed, so a row
that missed the budget on capture stayed untagged forever). Spends its
`maxModelCalls` (8) on whichever `TagKey`s have the most ROWS in the combined
set, not whichever is encountered first.

**The cheap entry — memory only, no model, runs on every queue open**
`DefaultPurchaseTagger.refresh(_:among:)` — same file. Called from
`ApprovalQueueViewModel.load()`. This is what makes settling one row visible
on the next one down in the same sitting.

**The accrual key**
`TagKey` (merchant + layout) —
[model/Contracts/TagMemory.swift](model/Contracts/TagMemory.swift). Layout is
`ExtractionPattern.templateIdentity(of:)` applied to `entry.readBy` — the
TEMPLATE a row was read by, version-stripped so re-promoting a pattern
doesn't orphan its merchant's whole tag history. This is what lets
`grab.com/food` and `grab.com/ride` settle independently instead of one
merged "grab" key that can never settle. Both the read side
(`TagContext.layout`) and the write side
(`DefaultApprovalService.recordDecisions`) must call the same function — they
already do, but any new write site has to too.

**The tagger's only oracle**
The approval queue itself — `DefaultApprovalService.recordDecisions`, run
after every ledger write. `TagScoreboard` reports the hit rate; nothing
routes on it yet (Auto-commit, ROADMAP #14, waits on a month of this).

---

## Entry point 3 — the smaller, third agent surface

`FailureExplainer` — [services/Agent/FailureExplainer.swift](services/Agent/FailureExplainer.swift).
Reads the evidence an `EndToEndRunner` failure already computed, narrates
where to look, forbidden to go past the evidence it's handed. The one place a
model's prose reaches a person directly — safe only because the false
positive is the cheapest kind (you open the file it named, find nothing,
ignore it; no row moves). Not part of the runtime loop; a diagnostic aid over
the harness in entry point 5 below.

---

## What carries the agent to the mailbox (not the agent itself, but nothing above runs without it)

- `AutoSync` — [services/Capture/AutoSync.swift](services/Capture/AutoSync.swift).
  Brings new mail to `GmailRail.sync()` (parse, dedup, tag). Throttled 15
  minutes; always runs once on first appearance.
- `DiscoverySync` — as above. Brings new SENDERS to the synthesis loop.
- Both live in `AppEnvironment` as lazy properties, both wired into
  `ContentView.swift`'s `.task` blocks, independent of each other.

---

## Entry point 5 — debug/manual surfaces that exercise the above directly

All Settings → Developer (DEBUG-only, gated in `SettingsView.swift`):

| Row | Exercises |
|---|---|
| Google API harness → Learn a pattern for blu | `DefaultPatternLearner` against blu, frozen corpus |
| Google API harness → Discovery | `PatternDiscovery` end to end, frozen corpus |
| Discovery section → Force a discovery sweep now | `DiscoverySync`, LIVE Gmail |
| Discovery section → Pure agent mode toggle | `AppEnvironment.pureAgentMode` |
| Auto-sync section → Force a sync now | `AutoSync` → `GmailRail.sync()`, LIVE Gmail |
| Evaluation → Score the tagger against your approvals | `TagScoreboard` |
| Evaluation → Score the learned patterns | `PatternMemory` / `PatternTrustPolicy` |
| Evaluation → End-to-end · empty state | `EndToEndRunner` — the WHOLE loop, but with `ScriptedSynthesizer`, not the real model. Proves the machinery, not the model. |

---

## Recent, agent-relevant (context for continuing, not a changelog)

- **`TagKey` (merchant + layout)** — fixes Grab/Shopee-style platforms
  collapsing into one unsettleable tag history. Version-stripped
  (`templateIdentity`) after a first cut fragmented history on every
  re-promotion — watch for the same trap if `layout` is ever derived a third
  way.
- **`DiscoverySync`'s row-count-priority tagger budget + backlog retagging** —
  the tagger's 8 calls now go to whichever `TagKey` has the most rows across
  new+backlog combined, not whichever is newest.
- **`AppEnvironment.pureAgentMode`** — first real-device run reported
  positive ("it actually work quite well the tag is better"), with a real gap
  (rare layouts from a known sender missed) diagnosed and fixed same day:
  `RuleID.unclaimed` (flag instead of silent skip) +
  `minimumProvisionalEvidenceForKnownSender` (relaxed volume floor for a
  sender that already has one active pattern). The relaxed floor is a
  judgment call, unmeasured — watch it.
- **Dedup's `manualDateSlackDays`** — not tagging, but agent-adjacent: a
  manual entry has no real timestamp to trust, same epistemic shape as "no
  oracle for tagging."

---

## Open, specifically about the agent (pulled from ROADMAP.md's own list)

- **Where synthesis runs** — on-device (privacy, current) vs. off-device (a
  larger model would likely help most here — five examples per sender, not
  the mailbox). Explicitly undecided; ROADMAP calls it "the single biggest
  lever on whether the thesis works."
- **Auto-commit (ROADMAP #14)** — blocked on a month of `TagScoreboard` shadow
  data. Nothing routes on the hit rate yet; don't build the auto-write path
  before there's a real number to pick a threshold from.
- **`PurchaseClassifier` (Phase 2, the fallback)** — not built. Only matters
  once #6 (labels) and the language-mix measurement exist; the loop is the
  better bet until senders stop clearing discovery's bars.
- **Widening `LanguageGate`** — refuses 36% of money mail at the strict
  setting the tagger uses; measured wrong (narrower than the model's 21
  locales) but not yet widened. Measure before widening, not the other way.
- **The 14-day backfill problem** — a promoted pattern never sees its
  sender's mail older than the rail's window. Unsolved; needs the capture log
  to know which domains it has seen before.
- **Grab's merchant anchors** — still wrong on 5 known fixture cases, pinned
  as they actually behave.

---

## Before you touch a threshold

Every number named above (`maxAttempts`, `promotionThreshold`,
`minimumProvisionalEvidence`, `minimumDistinctAmounts`, `maxModelCalls`,
`dateSlackDays`, `manualDateSlackDays`, `minimumProvisionalEvidenceForKnownSender`,
`PatternTrustPolicy`'s bar) is either **measured** against real data or
explicitly marked a **judgment call**. Two proposed fixes were killed by their
own measurements in an earlier session specifically so they'd be re-measured
rather than re-argued — don't re-derive a number from first principles when
the file already states where it came from. If you're about to change one,
measure first, or say plainly that you're making a judgment call and why.
