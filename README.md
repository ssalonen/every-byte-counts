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
- **Mid-cycle calibration** — installed partway through a billing cycle? Enter
  the usage your carrier reports so far and the app counts on from that figure —
  totals, forecast, overage cost and alerts are all corrected, no need to wait
  for the next cycle to get accurate numbers.
- **Day-by-day history** — daily totals for the current cycle as a bar chart.
- **Month-by-month history** — past cycles as a trend, accumulating from install.
- **Forecasting** — a recency-weighted *remaining daily budget* ("you can use
  X GB/day and stay under"), a projected end-of-cycle total, and a
  safe / at-risk / over status.
- **Cumulative burn-up chart** — usage accumulating across the cycle with the
  projection continued to cycle end as a dashed status-coloured line against
  the cap line, so "where is this heading" is visible at a glance.
- **Overage cost (EUR)** — flat €/GB on the projected excess, behind a swappable
  cost-strategy abstraction.
- **Threshold alerts** — local notifications at 50 / 80 / 100 % (configurable).
- **Widgets** — Home Screen + Lock Screen glances that **double as the background
  sampling heartbeat**.

### Known limits (by platform, not by choice)

The interface counters are whole-device and cumulative-since-boot, so: usage is a
few-percent **estimate** vs. the carrier's billing; it **can't** be broken down
per-app or separate hotspot/tethering traffic; and history only accumulates
**from install onward** (the current cycle's *total* can be calibrated to the
carrier's figure, but per-day bars still start at install). These are permanent
iOS constraints (design §1/§3).

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
| Forecasting | `Forecasting/Forecaster.swift`, `CumulativeUsageSeries.swift` |
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
alert dedup/reset, persistence round-trips, and full sampling-engine scenarios
(first sample, deltas, reboot mid-cycle, cycle rollover, multi-cycle gaps, alert
firing, pruning) — all driven by a mock counter reader, so they run on any Swift
toolchain.

A lead-QE review of *whether those tests assert the right things* — plus the
substantive correctness findings it surfaced (notably the iOS 32-bit counter
wrap) — is in [`docs/TEST-ASSESSMENT.md`](docs/TEST-ASSESSMENT.md).

---

## CI/CD & releases

GitHub Actions (`.github/workflows/`), adapted from `ssalonen/unarchiver`:

| Workflow | What it does |
|----------|--------------|
| `ci.yml` | Runs `swift test --enable-code-coverage` on the core, **gates line coverage ≥ 95%**, posts a coverage table on PRs; builds the app + widget (XcodeGen → `xcodebuild`) against the iOS Simulator SDK; on green `main`, auto-computes the next version from **Conventional Commits** and triggers a release. |
| `release.yml` | Runs **fastlane** `beta`: [`match`](https://docs.fastlane.tools/actions/match/) syncs the distribution cert + profiles from a private signing repo, `gym` archives and signs, the declared entitlements Xcode strips are re-asserted, and the build is uploaded to **TestFlight**. Reusable via `workflow_call`. |
| `bump-version.yml` | Manual `workflow_dispatch` (patch/minor/major) — the first-release escape hatch. |
| `security.yml` | CodeQL (Swift, `security-extended`), a supply-chain guard that keeps the core dependency-free, and PR dependency review. |

Conventional Commits drive the auto-release: `feat:` → minor, `fix:`/`perf:` →
patch, `feat!:`/`BREAKING CHANGE:` → major; `chore/docs/test/ci`-only pushes
publish nothing (which also stops the release bot's own version-bump commit from
looping). Since the existing history isn't in Conventional-Commit form, the
**first** release is cut by running the *Bump version* workflow manually.

### Distribution: TestFlight / App Store

Releases are signed with a real Apple Developer Program identity and uploaded
to App Store Connect, where they're available to TestFlight testers within
minutes and can be submitted for App Store review whenever you're ready — the
same signed build serves both, there's no separate "beta" vs "release" build.

Signing is managed by fastlane [`match`](https://docs.fastlane.tools/actions/match/):
the distribution certificate and provisioning profiles live, encrypted, in a
separate private git repo, and both CI and local machines sync them with one
command. The full rationale and step-by-step is in
[`docs/FASTLANE-MIGRATION.md`](docs/FASTLANE-MIGRATION.md); the essentials:

1. **Register the App IDs** in the [Apple Developer
   portal](https://developer.apple.com/account/resources/identifiers/list),
   with the **App Groups** capability enabled **and the group
   `group.fi.mailhub.everybytecounts` associated** on both (associating the
   group — not just enabling the capability — is what makes the profiles carry
   it):
   - `fi.mailhub.everybytecounts` (app)
   - `fi.mailhub.everybytecounts.widget` (widget extension)
2. **Create the app record** in [App Store
   Connect](https://appstoreconnect.apple.com/apps) with bundle ID
   `fi.mailhub.everybytecounts` — it must exist before the first upload. Add a
   **1024×1024 App Icon** to the app target's asset catalog (required for
   TestFlight; CI can't generate it).
3. **Generate an App Store Connect API key** (Users and Access → Integrations →
   **Keys**) with the **Developer** role — enough to manage profiles and upload.
   Note the **Key ID** / **Issuer ID** and download the `.p8` (once only).
4. **Seed match once** from a Mac: create a private signing repo, add a
   read-only SSH deploy key, then `bundle exec fastlane certificates` to create
   and store the cert + profiles (see the migration doc for exact commands).
5. **Add repo secrets** (Settings → Secrets and variables → Actions):
   | Secret | Value |
   |--------|-------|
   | `APPLE_TEAM_ID` | Your Developer Program Team ID |
   | `APP_STORE_CONNECT_KEY_ID` | The API key's Key ID |
   | `APP_STORE_CONNECT_ISSUER_ID` | The API key's Issuer ID |
   | `APP_STORE_CONNECT_API_KEY_P8` | The full contents of the `.p8` file |
   | `MATCH_PASSWORD` | Passphrase encrypting the signing repo |
   | `MATCH_GIT_URL` | The signing repo's SSH URL (`git@github.com:…`) |
   | `MATCH_REPO_KEY` | The **private** SSH deploy key for the signing repo |
6. **Add yourself as an internal tester** in App Store Connect → TestFlight.

After that, every auto-release (or a manual tag push) runs `fastlane beta` to
sync signing, build, and upload — nothing Apple-specific is committed to the repo.

**Local development signing:** a teammate runs `bundle exec fastlane certificates`
once and has the exact same cert + profiles as CI — no portal clicking.

---

## Design

The full functional + architectural brief this was built from is preserved in
[`docs/DESIGN.md`](docs/DESIGN.md). Section references (§N) throughout the code
and this README point at it.
