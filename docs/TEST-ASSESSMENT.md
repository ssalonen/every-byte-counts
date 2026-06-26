# Test Quality Assessment — MobileDataCore

*Reviewer role: lead quality engineer. Scope: the `MobileDataCore` unit suite.*

This document does three things the brief asked for:

1. Comes clean about the **process** (these tests were written *after* the code, not
   test-first) and what that costs us.
2. Assesses, behaviour by behaviour, whether each test asserts the **correct,
   specification-derived expected result** — i.e. whether the assertion would
   actually catch a real bug, or merely re-state what the code happens to do.
3. Records the **substantive correctness findings** that the test-writing exercise
   surfaced, including one real accuracy risk on iOS that the team should act on.

---

## 1. Process honesty: this was not red-green TDD

The implementation was written first and the tests added afterward. That makes them
**characterization tests**, and the failure mode of characterization tests is that
they encode *what the code does* rather than *what it should do* — they go green by
construction and catch nothing.

Two concrete symptoms were present in the first cut and have been fixed:

| Smell | Example (before) | Why it's weak | Fix |
|-------|------------------|---------------|-----|
| **Tautological assertion** | `XCTAssertEqual(forecast.overageCostEUR, forecast.projectedExcessGB * 4)` | Re-derives the expected value with the same multiplication the code uses; a wrong formula in *both* places still passes. | Assert a **concrete number reasoned from the spec**: projected 25, cap 20 → excess 5 → €20. |
| **Irrelevant fixture** | budget test fed `daily([1,1,1,1,1,1])` | The daily-budget formula doesn't read history at all, so the array implied a dependency that doesn't exist. | Pass `[]` and assert the budget is unchanged — proving independence. |

The right discipline going forward is **red-green**: write the failing assertion from
the spec first, watch it fail for the right reason, then implement. Where that didn't
happen, the mitigation below is to anchor every assertion to a value derived by hand
from the requirement, not from the code.

---

## 2. Behaviour-by-behaviour assessment

For each area: the **expected behaviour** (from `docs/DESIGN.md`, not from the code),
and whether the assertions are meaningful (would fail on a plausible bug).

### Sampling & reboot handling (the highest-risk logic) — §1, §4
- **Expected:** the cumulative cellular total is monotonic across reboots; on a
  reboot the counter restarts from zero and only post-reboot traffic is added;
  reading failures must not corrupt persisted state; first sample starts at zero
  (no pre-install backfill).
- **Assertions are meaningful:** the reboot test drives raw 1→4 GB, reboots, adds
  0.5 GB, and asserts cumulative **3.5 GB** — a number that is wrong under every
  plausible bug (forgetting to add the pre-reboot total, double-counting, or
  treating the drop as negative). `testReadFailureLeavesStateUntouched` asserts the
  *whole AppState is byte-for-byte unchanged*, which catches partial writes.
- **Verdict:** strong. These are the tests that matter most and they assert
  end-state values, not internal calls.

### Billing-cycle math — §2
- **Expected:** cycle is the half-open interval `[reset, nextReset)`; a reset day
  beyond month length clamps to the last day (31 → 28 in Feb); "days remaining" is
  ≥ 1 even on the last day.
- **Meaningful:** asserts exact `start`/`end` instants (Feb 28 clamp) and exact day
  counts (elapsed 10, remaining 22 for Mar 10 / reset 1). Off-by-one or wrong-month
  bugs fail.
- **Verdict:** strong, and now reinforced by `ModelsTests.testCycleContainsIsHalfOpenInterval`
  which pins the inclusive-start / exclusive-end contract that the whole
  used-this-cycle calculation depends on.

### Daily aggregation — §2, §6
- **Expected:** inter-snapshot deltas are distributed across spanned days *in
  proportion to elapsed time*; zero-traffic intervals create no day; equal
  timestamps don't divide by zero.
- **Meaningful:** the 22:00→02:00 case asserts a **0.5 / 0.5** split (proves
  proportional attribution, not "dump on the end day"); `dayFractions` sum is
  asserted to be exactly 1.0; the degenerate-interval and zero-delta guards are now
  covered.
- **Verdict:** strong. This is an *estimate* by design, and the tests assert the
  estimation rule rather than pretending to a precision the data doesn't have.

### Forecasting — §2
- **Expected:** headline budget = `(cap − used) / daysRemaining`, **independent of
  history** and never negative; projection = `used + recencyWeightedAvg ×
  daysRemaining`; status thresholds: over-cap → `over`, ≥ at-risk fraction → `atRisk`,
  else `safe`.
- **Meaningful (after fixes):** weighted average asserted to an **exact hand-computed
  value** (3 / 1.9375) for decay 0.5; equal-day input asserted to weight to that
  exact value (proves weighting is a true mean, not a drift); status tests pin the
  amber band (projected 18/20 → atRisk, €0) and the over case (projected 25 → €20).
- **Verdict:** strong after rework; previously contained the two tautologies above.

### Cost model — §5
- **Expected:** flat rate charges excess only and clamps negatives; stepped rounds
  **up** to whole blocks; throttle is always €0; the factory maps each config case
  to the right strategy.
- **Meaningful:** stepped asserts 0.2 GB → 1 block (rounding up, not down) and
  2.1 GB → 3 blocks; factory asserts each branch by output value.
- **Verdict:** strong, and exercises the swappable abstraction the design mandates.

### Alerts — §4
- **Expected:** fire each threshold at most once per cycle; cross a higher threshold
  later in the same cycle and it fires then; a new cycle resets the fired set.
- **Meaningful:** asserts the exact *set* of thresholds fired across a sequence of
  calls, including the no-refire and cycle-change-resets cases — the dedup contract,
  not an internal flag.
- **Verdict:** strong.

### Persistence, formatting, config, models
- Added round-trip tests prove the **extensibility hooks actually persist** (the
  snapshot `attribution` tag and the `type+params` cost model survive JSON), the
  file store degrades to defaults on a **corrupt/missing file** (no crash), and the
  reset-day / threshold-sort invariants hold. These are low-glamour but they protect
  real failure modes (a bad file bricking the widget) and the documented §5/§6
  promises.

---

## 3. Substantive correctness findings (beyond the tests)

Writing the tests surfaced issues that are **not** just test problems:

### 🔴 High — iOS interface counters are 32-bit and wrap (~every 4 GB)
`if_data.ifi_ibytes`/`ifi_obytes` are `u_int32_t`. The reader sums them into a
`UInt64`, but each underlying counter still wraps at 2³². The current
`RebootAdjuster` cannot distinguish a wrap from a reboot, and on a drop it re-bases
to the new low value, **under-counting by the pre-wrap remainder**. Worse, summing
two independently-wrapping 32-bit counters *before* diffing means the sum can fall
even when neither is a reboot, producing extra pseudo-reboots.

- **Impact:** for a 20 GB plan you can expect several wraps per cycle; each drops up
  to one sample-interval's traffic. Frequent sampling (the widget heartbeat) keeps
  the error small, but if >4 GB passes on one interface between two samples, a whole
  wrap is missed.
- **Recommended fix:** track **per-interface** cumulative counters (diff each
  interface before summing) and, on a detected drop, add `(2³² − previousRaw) +
  currentRaw` instead of just `currentRaw` when the gap is consistent with a wrap
  rather than a genuine boot (a boot zeroes *all* interfaces simultaneously).
- **Test to add when fixed (red first):** previousRaw = 2³²−100 MB, currentRaw =
  300 MB on one interface only → expected delta 400 MB, `didReboot == false`. This
  test would **fail today**, which is exactly why it's the right next red.

### 🟡 Medium — multi-cycle gaps lose intermediate months
If neither the app nor the widget samples for more than a full cycle, skipped cycles
are never reconstructed (there's no data for them anyway). This is now **pinned by a
test** (`testGapSpanningMultipleCyclesClosesOnlyTheOpenOne`) so the behaviour is a
deliberate contract, not an accident. Acceptable per §7; revisit only if month-by-
month history must show empty months explicitly.

### 🟡 Medium — reboot/wrap traffic that spans two samples can't be split
Per §7 this is accepted. The closing-cycle attribution dumps gap traffic onto the
old cycle. Pinned by the rollover test. Fine as documented.

### 🟢 Low — DST and the proportional day-split
The day-split divides by absolute seconds, so a 23/25-hour DST day skews a single
day's estimate by ≤ ~4%. Day *counts* use calendar components and are unaffected.
Acceptable for an estimate; noted so nobody "fixes" it as a bug later.

---

## 4. Coverage: what's measured and why

- **Measured:** the `MobileDataCore` package (all business logic) via
  `swift test --enable-code-coverage`, gated at **≥ 95% line coverage** in CI.
- **Excluded from the metric:** `InterfaceCounterReader.swift` — a thin `getifaddrs`
  device adapter that can only be meaningfully validated on real hardware. It still
  has a smoke test that runs on the macOS CI host. Excluding pure platform I/O from a
  *unit* coverage number is deliberate, not a dodge; its correctness is an
  integration/on-device concern (see finding 🔴 above).
- **Not in scope of unit coverage:** the SwiftUI app and WidgetKit views. These are
  view code; they belong under snapshot/UI tests (as the unarchiver project does for
  its viewers), not unit tests. The CI `app-build` job at least guarantees they
  compile against the iOS SDK on every push.

> Honest caveat: the 95% gate could not be executed in the authoring environment
> (no Swift toolchain on the Linux box). The number will first be produced by the
> `core-tests` CI job. The gate is set to 95 as the *target*; if the first green run
> reports lower because of a branch I mis-estimated, the fix is more tests, not a
> lowered bar.

---

## 5. Recommendations (prioritised)

1. **Fix the 32-bit wrap handling** (finding 🔴) — it's the single biggest threat to
   the product's core promise of an accurate estimate. Do it test-first.
2. **Add property-based tests** for the sampling engine: random sequences of
   (+traffic / reboot / time-advance) operations, asserting the invariant
   *cumulative is monotonic and equals the sum of all positive deltas* — this would
   have caught the wrap issue generatively.
3. **Snapshot-test the widget glance and dashboard** so the read-side rendering is
   covered, mirroring unarchiver's UI-test + coverage approach.
4. **On-device validation harness:** compare the app's cycle total against the iOS
   Settings → Cellular figure over a week to calibrate the few-percent drift the
   design acknowledges.
