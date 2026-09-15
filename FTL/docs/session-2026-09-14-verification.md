# Verification report — 2026-09-13/14

**Build:** 0.7 (1) · iOS 26.5 · iPhone 17 Pro simulator (26.5)
**Lane:** manual, on-device, against `AppEnvironment.sample()` fixtures.
**Companion to:** `TESTING.md`, which holds the measured lanes. This file holds
what was *exercised by hand*, because the work in this window shipped no
automated coverage and pretending otherwise is how a file like this stops being
worth reading.

---

## Read this first — what this report is worth

Every row below was driven through the real UI on a real simulator and observed,
not asserted. That is genuinely stronger than nothing, and it is genuinely weaker
than a test. Specifically:

- **It ran once.** No repetition, no randomisation, no adversarial input.
- **It ran against fixtures**, not a real Google Sheet. Every Sheets round trip
  was an `InMemory*` store. Nothing here exercised the network, auth token
  refresh, quota, or a partial write.
- **It is not a regression net.** None of it will notice if a later change
  breaks it. There is still **no test target** in the project — five targets,
  none of them tests.
- **The arithmetic was checked by eye**, from figures on screen. Where a number
  is quoted below it was verified against the rest of the screen (a bucket
  moving by exactly the amount that left another), which catches gross errors
  and not off-by-one in an edge case.

Treat this as *"the happy path and several unhappy ones were walked"*, and not
as *"this is covered"*.

---

## 1 · Ledger editing

| What | How it was driven | Observed |
|---|---|---|
| Amount correction reaches the Sheet | Gojek 34.500 → 345.000, Save | Row shows 345.000; hero recomputed |
| Kind correction excludes from spend | Same row → Not a spend / Transfer | Hero **dropped by exactly 34.500**; Transport gained it back; row amount unchanged |
| Bucket retag moves the money | Grab 574.000, Transport → Food | Transport 612.000 → 38.000; Food flipped to **19.000 over** in the signal colour; **hero total unchanged** (correct — a retag moves money between buckets, it does not change total spend) |
| Merchant correction | INDOMARET → "Indomaret Kemang", approve | Ledger row reads "Indomaret Kemang"; `merchantRaw` untouched |
| Editor opens from both lists | Home → Recent, and Bucket detail | Same sheet, same fields, both routes |

**Bug found and fixed during this:** retagging from the bucket screen left
**Home stale behind the push** — the pushed screen reloaded itself, the hero and
meters did not. Re-verified after the fix: Food → 19.000 over, Transport →
862.000 left, hero correctly unchanged.

---

## 2 · Approval queue

| What | How it was driven | Observed |
|---|---|---|
| Amount correction before approval | INDOMARET 88.000 → 880.000 | Card shows 880.000 with **"read Rp 88.000" struck through**; provenance flipped 🤖 model → ✍️ you |
| Corrected figure reaches the ledger | Approve to Food | Hero +880.000 (not +88.000); Food → 325.000 over; queue 3 → 2 |
| Merchant correction before approval | TOKOPEDIA → "Tokopedia Marketplace" | Title updated, **"read TOKOPEDIA"** beneath, not struck through (the raw is preserved, not replaced) |
| Auto-dropped duplicate is visible | Queue footer | "1 dropped as a duplicate", expandable, reason names the twin |
| Restore puts it back | Tap Restore | Queue 3 → **4 to review**; dropped section disappeared |

---

## 3 · Merchant memory — the one that needed a second row

The only assertion here that required two *different* rows to prove:

1. Renamed one TOKOPEDIA row to "Tokopedia Marketplace".
2. Settled it, then reached the **restored duplicate** — a different entry id,
   from `tokopedia-receipt`, never touched.
3. It arrived already showing **"Tokopedia Marketplace"** with "read TOKOPEDIA"
   beneath.

That is the feature working: keyed on `MerchantID(normalizing:)`, applied on
queue load, surviving to a row the correction never saw.

---

## 4 · Error surfacing — verified by forcing a failure

Method: `InMemoryProvisionalStore.update` was temporarily patched to
`throw LedgerError.transport("simulated write failure")`, rebuilt, driven, then
reverted (confirmed reverted — no diff on `InMemoryStores.swift`).

- Correcting an amount raised **"Couldn't save — Couldn't reach the sheet."**
- `LocalizedError` conformance confirmed: the alert rendered a sentence, not
  `transport("…")`.
- The card correctly **still showed the old figure**, so the failure and the
  displayed state agreed.

Before this, `ApprovalQueueViewModel` set `phase = .failed` in ten places and
`ApprovalQueueSheet` read `phase` in none. Every one of those failures was
silent.

---

## 5 · Budget allocation

| What | Observed |
|---|---|
| Raising a bucket draws only from Unallocated | Food 37% → 56%; Unallocated 26% → 7%; **Transport, Shopping, Subscriptions unmoved** |
| The cap holds | Dragging Food to the far right stopped at **63%** (56 + the 7 left); Unallocated 0%; footer switched to "Unallocated is empty…" |
| Lowering returns it | Food 63% → 18% put all 45 points back into Unallocated; others still unmoved; total 100% |

---

## 6 · Widgets — the App Group

The failure this uncovered is the most important line in this report.

**There were no entitlements files in the project at all.** `UserDefaults(suiteName:)`
returned nil, the code fell back to `?? .standard`, and the app and the widget
extension read and wrote two different containers. Every figure on those widgets
had been the hardcoded `.placeholder` for the whole of their existence, with
nothing visibly broken anywhere.

Verified after wiring entitlements into both targets — the shared container now
exists and decodes to live data:

```
monthTitle      September        pendingApprovalCount  3
monthCeiling    6 500 000        dailyAllowance        124 588
monthRemaining  2 118 000        todaySpent             62 500
topBuckets      Food, Transport, Shopping, Subscriptions   (Unallocated excluded)
```

Cross-checked against the Home screen — same figures.

⚠️ **Not verified:** the widget actually *rendering* this. That needs the widget
placed on a simulator home screen, which was not done. The shared store is
confirmed populated and both targets carry identical entitlements, so the
remaining risk is in the extension's own rendering path.

---

## 7 · Background fetch and notifications

| What | Observed |
|---|---|
| Permission prompt | "FTL Would Like to Send You Notifications" fired on enabling |
| Setting persists | `backgroundRefreshEnabled => true` in the app's defaults |
| Digest schedules | `dailyDigestEnabled => true`, `dailyDigestHour => 8` |
| The request really exists | `PendingNotifications.plist` contains `ftl.digest.daily`, `NS.hour => 8`, `TriggerRepeats` |

⚠️ **Not verified, and not verifiable this way:** that `BGAppRefreshTask` ever
actually *fires*. iOS schedules it opportunistically; a simulator will not
reproduce real-world timing. What is verified is that it registers, that the
Info.plist carries `UIBackgroundModes` and the permitted identifier, and that
scheduling is re-requested on every background transition. **Whether it runs on
a real device over days is unmeasured.**

---

## 8 · Bugs found by driving the UI, not by reading it

Recorded because each cost real time and none would have been caught by reading
the diff:

1. **Home stale behind a push** after editing from a bucket (§1).
2. **A `Toggle` inside `PanelRow` renders correctly and swallows every tap.**
   Took several passes to isolate — taps on the same screen were confirmed
   working first. Settings rows are Buttons now.
3. **`TimelineView` proposes an unspecified size to its content**, so a `Shape`
   fell back to its 10×10 ideal: the loading beam's rungs drew into a tiny box
   at the centre while the saucer around them filled the frame.
4. **`.tint` does not reach a `role: .destructive` button** — Sign out was the
   one hue in the app that was not `FTLColor`, and it looked correct in code.

All four are now in `CLAUDE.md` → *Gotchas already paid for*.

---

## What this session did NOT test

Stated plainly, because the list above is long enough to look like coverage.

- **Anything against a real Google Sheet.** No network, no auth refresh, no
  quota, no partial write, no concurrent edit from the web UI.
- **Anything against real Gmail.** The whole capture rail — fetch, parse,
  discovery, synthesis — ran zero times in this window.
- **The tagger and the synthesizer.** Both model jobs were untouched; no model
  call was made at any point.
- **`SheetsLedgerStore.delete`,** which is still clear-then-rewrite: a failure
  between the two calls leaves the transactions tab empty. Untested against a
  real sheet and the highest-consequence path in the app.
- **Rate limiting.** `LedgerError.rateLimited` is declared and never thrown;
  there is no 429 handling anywhere.
- **Dynamic Type, VoiceOver, and reduced motion** beyond the one `BeamActivity`
  branch — 48 fixed-size fonts and 11 accessibility labels across 112
  interactive elements.
- **Every pure function added in this window** — `apportion`, `setPercent`,
  `verdict(for:)`, `merchantWasMisread`, `Fingerprint` recomputation on a
  corrected amount. All are trivially table-testable and none is tested.

---

## The one recommendation

A Unit Testing Bundle, and the first four cases are already written above:
`setPercent` draws only from the buffer and clamps at it; `verdict(for:)`
returns `correctedAmount` over `correctedMerchant` over `correctedKind`;
`merchantWasMisread` is false for a rename that normalizes to the same
`MerchantID`; `Fingerprint` changes when a corrected amount crosses a bucket
edge. All four are pure, all four took manual driving to check this time, and
all four will silently rot without it.
