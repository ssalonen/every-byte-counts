# Mobile Data Tracker — iOS App Plan

A personal iPhone app that tracks **cellular** data usage against a monthly quota, shows
day-by-day and month-by-month history, forecasts whether you'll exceed the cap, and
estimates the cost of any overage in euros.

This document is a functional + architectural brief, not an implementation spec. It exists
to seed a Claude Code session. Code details (Swift APIs, schemas) are deliberately left open.

---

## 1. Core concept & hard constraints

Everything in this app is shaped by how iOS exposes data usage. These constraints are not
negotiable — design around them, don't fight them.

- **Data source:** iOS exposes a *system-wide* byte counter per network interface. The app
  reads the **cellular** interface separately from **WiFi**. This is on-device, requires
  **no VPN and no login**. This is the only sanctioned way to read usage.
- **Cumulative-since-boot:** the counter resets to zero on every device reboot. The app must
  detect resets (a new reading lower than the last means a reboot happened) and maintain its
  own running total across reboots.
- **No continuous background execution:** iOS will not let the app poll constantly. Usage is
  derived from **periodic snapshots** of the counter. The two reliable sampling moments are
  (a) when the app is opened and (b) **widget timeline refreshes**. The widget is therefore a
  core sampling mechanism, not just a display surface.
- **History starts at install:** there is no way to backfill usage from before the app was
  installed. All history accumulates going forward.
- **It's a calibrated estimate, not the carrier's number:** interface counters drift a few
  percent from operator billing. The app presents an estimate and should say so.
- **Whole-device only:** usage cannot be broken down per-app, and tethering/hotspot traffic
  cannot be separated out. Both share the same cellular counter. Out of scope, permanently.

---

## 2. MVP scope (functional)

### Quota & remaining allowance
- User configures: **monthly cap** (GB) and **billing-cycle reset day**.
- App shows **data used**, **data remaining**, **% consumed**, and **days left in cycle**.
- Usage **auto-resets** at the start of each billing cycle (snapshot a baseline at reset).
- Cellular is the metered figure. WiFi may be shown for context but does not count against the cap.

### Day-by-day history
- Daily usage totals for the current cycle, derived from stored snapshots.
- Simple per-day breakdown (e.g. a bar list).

### Month-by-month history
- Past billing cycles shown as a trend (bar chart), accumulating from install onward.
- Tap a cycle to see its total / detail.

### Forecasting
- Headline output is a **remaining daily budget**: "you can use X GB/day for the remaining
  N days and stay under the cap."
- Also surface a simple **projected end-of-cycle total** and a safe / at-risk / over status.
- Forecast should be **recency-weighted** (recent days count more than early-cycle days).
  Weekday/weekend awareness is a nice-to-have, not required for MVP.

### Overage cost estimate (EUR)
- If projected usage exceeds the cap, estimate the **excess GB** and convert to a euro cost.
- MVP uses a **simple flat €/GB** model (user enters the rate).
- See §5 — the cost model must be architected so richer models slot in later without rework.

### Alerts
- User-set **threshold alerts** (e.g. 50/80/100%) delivered as local notifications.
- A forecast-based alert ("on pace to exceed on the 24th") is desirable but can follow MVP.

### Widgets
- Home Screen + Lock Screen widget showing remaining data / % / days left.
- Doubles as the background sampling heartbeat (see §1).

---

## 3. Explicitly out of scope for MVP

Dropped by decision (keep architecture from blocking them later where noted):

- **Roaming / EU sub-meter** — out of MVP. Architecture should leave room for a future
  location-attributed roaming meter (see §6, "extensibility").
- **Per-app usage** — not possible on iOS. Permanently out.
- **Hotspot / tethering isolation** — not possible. Permanently out.
- **Carrier reconciliation** (manual calibration against operator's number) — dropped.
- **Dual-SIM / eSIM per-line tracking** — dropped.
- **Export / CSV / webhook** — not needed.
- **Apple Watch app/complication, Siri shortcut, themes** — post-MVP polish, not required now.

---

## 4. High-level architecture

Three pieces sharing one storage container:

```
┌─────────────────┐     ┌──────────────────┐
│   Main App      │     │  Widget Extension │
│  (SwiftUI UI)   │     │   (WidgetKit)     │
│  - dashboard    │     │  - glance display │
│  - history views│     │  - SAMPLES counter│
│  - settings     │     │    on refresh     │
└────────┬────────┘     └─────────┬────────┘
         │                        │
         │   both sample + read   │
         ▼                        ▼
   ┌──────────────────────────────────┐
   │   Shared Core (App Group)         │
   │  - counter reader (cellular/wifi) │
   │  - sampling + reboot handling     │
   │  - persistence (snapshots/cycles) │
   │  - forecasting engine             │
   │  - cost model                     │
   │  - alert evaluation               │
   └──────────────────────────────────┘
```

- **Shared Core** is a framework/module both targets link against. All logic lives here so the
  app and widget behave identically; neither owns business logic directly.
- **App Group container** is the shared persistence boundary — the only way the app and widget
  see the same data. Pick a lightweight store (SQLite or equivalent); avoid anything that needs
  a running process.
- **Sampling model:** both the app (on launch/foreground) and the widget (on each timeline
  refresh) call the same "take a sample" routine. The routine reads the counter, handles reboot
  resets, appends a snapshot, and updates derived totals. Sampling must be **idempotent and
  cheap** — it can fire at unpredictable times.
- **Alerts** are evaluated during sampling and fired as local notifications when a threshold or
  forecast condition is newly crossed (track last-fired state to avoid repeats).

---

## 5. Cost model (future-proofing)

MVP ships **flat €/GB on excess only**, but build it behind a small abstraction so the model
type is swappable. Anticipated future variants:

- **Stepped / bundle add-ons** — overage billed in fixed blocks (e.g. +1 GB for €X).
- **Throttle** — no charge, speed reduced past the cap (cost = €0).
- **Roaming-specific** rates with their own threshold (ties into the future roaming meter).

The right shape is a **cost strategy** that takes (projected/actual excess GB, plan config) and
returns a euro figure + a human-readable basis. MVP provides one strategy; the UI binds to the
abstraction, not the flat calculation.

---

## 6. Data model (high level)

Entities, not schemas:

- **Plan config** — cap (GB), cycle reset day, cost model type + parameters (flat €/GB for now).
- **Snapshot** — timestamp, raw cellular counter, raw WiFi counter, reboot-adjusted running totals.
- **Daily total** — date, cellular GB, (WiFi GB), derived from snapshots.
- **Cycle** — start/end dates, cellular total, cap at the time, overage GB, estimated cost.
- **Alert state** — which thresholds have fired this cycle (to prevent duplicate notifications).

**Extensibility hooks (don't build, just don't preclude):**
- Snapshots should be able to carry an optional **attribution tag** (e.g. home vs roaming) so a
  future roaming meter can classify deltas by location without a migration.
- Cost model stored as type + params, not a single hardcoded rate.

---

## 7. Open items to confirm at build time

- Exact cellular vs WiFi interface identifiers and the correct counter fields on current iOS.
- Widget refresh cadence in practice — how often timeline refreshes actually fire, and whether
  that's frequent enough for clean day boundaries (app-launch sampling backstops this).
- Reboot-detection edge case: usage that spans a reboot between two samples can't be split
  precisely; decide how to attribute it (acceptable minor inaccuracy).
- Notification permission flow and the minimal background mode (if any) worth enabling.

---

## 8. Suggested build order

1. Shared Core: counter reader + sampling routine + reboot handling + persistence.
2. Plan config + cycle reset logic.
3. Main app dashboard (remaining / % / days left) reading from Core.
4. Day-by-day and month-by-month history views.
5. Widget (display + sampling) — wire in early so background sampling exists.
6. Forecasting engine (recency-weighted daily budget + projection).
7. Cost model abstraction + flat €/GB strategy + overage display.
8. Threshold alerts.
