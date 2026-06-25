# Every Byte Counts

A personal iPhone app that tracks **cellular** data usage against a monthly quota,
shows day-by-day and month-by-month history, forecasts whether you'll exceed the
cap, and estimates the cost of any overage in euros.

This is the MVP implementation of the [design brief](#design). It reads the
on-device, system-wide cellular byte counter — **no VPN, no login, no carrier
account** — and presents a calibrated *estimate* of usage.

---

## What it does (MVP)

- **Quota & remaining allowance** — configure a monthly cap (GB) and a billing
  reset day; see used / remaining / % consumed / days left, auto-resetting each
  cycle.
- **Day-by-day history** — daily totals for the current cycle as a bar chart.
- **Month-by-month history** — past cycles as a trend, accumulating from install.
- **Forecasting** — a recency-weighted *remaining daily budget* ("you can use
  X GB/day and stay under"), a projected end-of-cycle total, and a
  safe / at-risk / over status.
- **Overage cost (EUR)** — flat €/GB on the projected excess, behind a swappable
  cost-strategy abstraction.
- **Threshold alerts** — local notifications at 50 / 80 / 100 % (configurable).
- **Widgets** — Home Screen + Lock Screen glances that **double as the background
  sampling heartbeat**.

### Known limits (by platform, not by choice)

The interface counters are whole-device and cumulative-since-boot, so: usage is a
few-percent **estimate** vs. the carrier's billing; it **can't** be broken down
per-app or separate hotspot/tethering traffic; and history only accumulates
**from install onward**. These are permanent iOS constraints (design §1/§3).

---

## Architecture

Three pieces share one App Group container (design §4):

```
  Main App (SwiftUI)            Widget Extension (WidgetKit)
  - dashboard / history         - glance display
  - settings                    - SAMPLES counter on refresh
        \                              /
         \   both sample + read       /
          v                          v
        +----------------------------------+
        |  MobileDataCore (Swift package)   |
        |  counter reader · sampling+reboot |
        |  persistence · forecasting · cost |
        |  alerts · usage/cycle math        |
        +----------------------------------+
```

**All business logic lives in `MobileDataCore`** so the app and widget behave
identically; neither owns logic directly. The single shared entry point is
`MobileDataService` (`sample()` + `report()` + `cycleHistory()`).

### How sampling works

iOS won't let the app poll continuously, so usage is derived from **periodic
snapshots** taken at the two reliable moments: **app foreground** and **widget
timeline refresh**. Both call the same idempotent `SamplingEngine.sample()`,
which:

1. reads the cellular/WiFi counters (`getifaddrs` -> `if_data`),
2. detects reboots (a reading *lower* than the last -> counter reset) and keeps a
   monotonic running total across reboots,
3. rolls the billing cycle over when due (rebasing on a baseline rather than ever
   zeroing the counter),
4. appends a snapshot, evaluates threshold alerts, and persists — all in one
   cheap synchronous pass.

### Key source map

| Area | File(s) |
|------|---------|
| Units | `Sources/MobileDataCore/Models/DataSize.swift` |
| Entities | `Models/PlanConfig`, `Snapshot`, `DailyTotal`, `Cycle`, `AlertState` |
| Counter reader | `Counter/InterfaceCounterReader.swift` (Darwin), `CounterReading.swift` |
| Sampling + reboot | `Sampling/SamplingEngine.swift`, `RebootAdjuster.swift` |
| Persistence | `Persistence/DataStore.swift`, `AppState.swift` |
| Cycle/usage math | `Usage/BillingCycleCalendar.swift`, `DailyAggregator.swift`, `UsageCalculator.swift` |
| Forecasting | `Forecasting/Forecaster.swift` |
| Cost model | `Cost/CostStrategy.swift`, `CostStrategies.swift` |
| Alerts | `Alerts/AlertEvaluator.swift` |
| Facade | `MobileDataService.swift` |
| App | `App/EveryByteCounts/**` |
| Widget | `Widget/EveryByteCountsWidget/**` |

The cost model is stored as **type + params** and resolved through
`CostStrategyFactory`, so the planned stepped / throttle / roaming variants
(design §5) slot in without a migration. Snapshots also carry an optional
`attribution` tag for a future roaming meter (design §6) — defined, not built.

---

## Building

The shared logic is a Swift package you can test today; the app + widget are
assembled into an Xcode project with [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
# 1. Run the Shared Core unit tests (no Xcode needed):
swift test

# 2. Generate the Xcode project for the app + widget:
brew install xcodegen      # if needed
xcodegen generate
open EveryByteCounts.xcodeproj
```

In Xcode, set your **Development Team** on both targets and confirm the **App
Group** capability (`group.fi.mailhub.everybytecounts`) is enabled on both, then
run on a device. (The cellular counter only moves on a real iPhone, not the
Simulator.)

### Tests

`MobileDataCore` ships an XCTest suite covering the pieces that carry risk:
reboot detection, billing-cycle boundaries (incl. short months), daily delta
splitting across midnight, recency-weighted forecasting, the cost strategies,
alert dedup/reset, and full sampling-engine scenarios (first sample, deltas,
reboot mid-cycle, cycle rollover, alert firing, pruning) — all driven by a mock
counter reader, so they run on any Swift toolchain.

---

## Design

The full functional + architectural brief this was built from is preserved in
[`docs/DESIGN.md`](docs/DESIGN.md). Section references (§N) throughout the code
and this README point at it.
