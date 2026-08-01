# Aegis — Mac Control Center

**English** | [Türkçe](README.tr.md)

![Platform](https://img.shields.io/badge/platform-macOS%2026-blue)
![Swift](https://img.shields.io/badge/Swift-6.2-orange)
![License](https://img.shields.io/badge/license-MIT-green)
![Dependencies](https://img.shields.io/badge/dependencies-none-brightgreen)

A single-window system console for macOS 26 (Tahoe): battery health and
cycles, hardware identity, memory/CPU telemetry, energy-hungry processes,
storage analysis, safe cleanup, and a launch-item inspector.

Native SwiftUI + Liquid Glass. No external dependencies, no background
service, no network access, no elevated privileges.

> **Disclaimer:** Aegis only ever moves files to the Trash and routes every
> deletion through a multi-layer safety gate — but the software is provided
> "as is", without warranty of any kind (see [LICENSE](LICENSE)). Review the
> cleanup list before confirming.

---

## Install

No prebuilt binaries are distributed — you build the app from source on your
own machine. This is deliberate: instead of asking you to run an unsigned
download, you compile ~6,400 lines of source you can read. An app you built
yourself also raises no Gatekeeper warnings.

Requirements: macOS 26 (Tahoe) and Xcode 26 (or Command Line Tools).

```bash
git clone https://github.com/yavuzhankursun/Aegis.git
cd Aegis
./build_app.sh release       # builds, bundles the .app, renders the icon, ad-hoc signs
open build/Aegis.app
```

To install into `/Applications`:

```bash
cp -R build/Aegis.app /Applications/
```

**Full Disk Access (optional):** for the Storage and Cleanup tabs to read
some folders, you may need to add Aegis under System Settings → Privacy &
Security → Full Disk Access. Without it the app does not crash; it silently
skips what it cannot read and excludes it from totals.

---

## Tabs

| Tab | What it does |
|---|---|
| **Overview** | Aegis Score, battery/memory/storage summary, system assessment |
| **Battery** | Health, cycles, live power flow, wear forecast, gauge lifetime log, cell balance |
| **Performance** | Memory breakdown, pressure, swap, CPU load, RAM-hungry apps |
| **Energy** | Process ranking using macOS's own Energy Impact metric |
| **Storage** | Volume usage, real size of user folders |
| **Cleanup** | Cache/log/build-output scan with move-to-Trash cleanup |
| **Startup** | Launch agent/daemon inspector, ghost-agent detection |
| **Hardware** | Chip, core layout, GPU, displays, SIP, serial number |

---

## What sets it apart

Four things typical cleaner/monitor apps don't show:

**1. Gauge lifetime log and cell balance** — the raw record the battery's
gauge chip (`AppleSmartBattery → BatteryData → LifetimeData`) keeps for its
entire life: total operating time, lowest/highest temperature ever seen,
lifetime average temperature, peak charge/discharge current, pack voltage
range, daily charge window. On top of that, per-cell voltage and the spread
between cells (Δ mV) — catching a weak cell before capacity collapses. This
data appears in neither System Information nor Activity Monitor.

**2. Wear forecast** — from capacity lost per cycle, it computes the cycles
and calendar date remaining until the 80% service threshold. The daily cycle
rate is derived from the gauge's reported total operating time. If wear is
below measurement resolution it says so instead of inventing a forecast.

**3. Leftover Hunter** — collects the bundle identifiers of every `.app` on
disk, then compares reverse-DNS-named entries under `Application Support`,
`Containers`, `Preferences`, `Saved Application State`, `HTTPStorages`,
`WebKit`, and `Caches` against that set. No match = residue from an
uninstalled app.

**4. Ghost launch agents** — reads `LaunchAgents` / `LaunchDaemons` plists
and checks whether the program they point to still exists on disk.
Definitions with a missing target are left behind by sloppy uninstalls, and
launchd retries them on every boot for nothing.

**Aegis Score** — a single 0–100 value weighing battery (25%), memory (25%),
storage (20%), energy (18%), and thermals (12%). The component breakdown and
the weakest link are always shown next to the number; the score is not a
black box.

---

## Safety model

Not being able to harm the Mac is the design's starting point.

**No deletion, only moving.** Every item goes to the Trash via
`FileManager.trashItem` and can be restored from Finder. The only exception
is items already in the Trash; permanent deletion is unavoidable there and
the confirmation dialog warns about it separately.

**One gate: `SafetyGuard.verify()`.** Every path slated for deletion passes
through it once at scan time and once more at deletion time:

- The path is resolved with `resolvingSymlinksInPath()` first — a
  `Caches/evil → /` trap doesn't work. Symlink leaves are additionally
  rejected at deletion time.
- It must be a **child** of an allow-listed root. The root itself can never
  be deleted.
- `Documents`, `Desktop`, `Photos`, `Movies`, `Music`, iCloud Drive,
  Keychain, Mail, Messages, Safari, `/System`, `/usr`, `/bin` are rejected
  unconditionally.
- Under `Containers`, only `Caches` / `tmp` subtrees are touched — matched
  on exact path-segment boundaries, so a name like `CachesEvil` cannot slip
  through. One exception: an orphaned container itself, when it is a
  **reverse-DNS-named direct child** found by the Leftover Hunter (Apple
  identifiers excluded).
- Under `Application Support`, `Preferences`, `Saved Application State`,
  `HTTPStorages`, `WebKit`, only **reverse-DNS-named direct children** can
  be deleted. A free-named folder like `Application Support/MyNotes` — i.e.
  potentially real user data — is rejected.

**No signals are sent to processes.** Quitting an app uses
`NSRunningApplication.terminate()`, which is identical to Cmd+Q — the app
can prompt about unsaved data. There is no `kill`. Processes that keep the
session alive (`loginwindow`, `Finder`, `Dock`, `WindowManager`,
`SystemUIServer`, …) are blocked in two separate layers.

**No elevated privileges.** No `sudo`, no helper tool, no
`launchctl`/`diskutil`/`rm`. External process execution is limited to the
`Shell.allowedBinaries` allowlist (`top`, `sysctl`, `system_profiler`,
`csrutil`, `ioreg` — all read-only) and since `/bin/sh -c` is never used,
command injection is impossible.

**No writes.** The app never modifies a system setting, plist, or IORegistry
value. All telemetry is read-only.

**Verifiable.** The deletion gate's decisions are pinned by a self-test:

```bash
AEGIS_SELFTEST=1 ./build/Aegis.app/Contents/MacOS/Aegis
# ── all 36 cases passed ──
```

24 of the 36 cases are "must deny" (Documents, iCloud, Keychain, Mail,
Photos, `/System`, `/usr`, path traversal, the protected roots themselves,
free-named folders in `Application Support`, the `CachesEvil` segment trap,
Apple containers…), 12 are "must allow" (caches, logs, build output,
reverse-DNS leftovers, orphaned containers…). Any regression exits with
code 1. Every change touching `SafetyGuard` must pass this test — see
[CONTRIBUTING.md](CONTRIBUTING.md).

---

## Its own resource footprint

An app that monitors the system must not slow down the system it monitors.
Measurements were taken on a MacBook Air (M5, 16 GB) over 30–40 second
windows using `ps -o time` deltas.

**Current state:**

| Condition | CPU |
|---|---|
| Window frontmost, Overview open (3 s sampling) | **5.6%** |
| Window hidden / occluded | **0.1%** |
| RSS | ~140 MB |

**Regressions measured and fixed along the way:**

| Finding | Effect |
|---|---|
| Animated + `blur(60)` full-screen mesh gradient | 19.7% → 16.6% (made static) |
| Whole page in one body (every tick redrew everything) | cards split into separate `View`s |
| `ForEach` identity minted a fresh `UUID` per compute | 19.7% → 0.8% |
| Score card detail text changed every tick | 12.3% → 1.3% |
| `.symbolEffect(.variableColor.iterative)` (looping symbol) | **16% on its own** |
| 0.3 s pulse animation per sample | 1.7% → 6.1% |

Lessons learned are recorded as comments in the code. Summary:

- **Unstable identity is the most expensive mistake.** If an `Identifiable`
  model regenerates `let id = UUID()` on every compute, SwiftUI thinks every
  row changed and rebuilds the list each tick. That alone was a ~19× swing.
  Identity can't be derived from a title carrying live measurements either —
  it must be a stable key.
- **Never run periodic animation over glass/material surfaces.** Even a
  6-pixel moving dot forces the background to be re-blurred at display
  refresh rate for the animation's duration. Measured: a looping symbol
  animation costs 16%, one pulse per sample 4.4%. Animations run only on
  **user action** (tab switch, hover, an actual value change).
- **`@Observable` fires on assignment, not on equality.** Passing via
  `inout` (`assign(&memory, value)`) invokes the `_modify` accessor and
  publishes even when the value is identical. The right way:
  `if memory != new { memory = new }`.
- **Precision you don't display still hurts.** If the screen shows whole
  numbers, round in the model too; decimal noise means constant redraws.
- **Don't run blocking work on the cooperative pool.** Waiting on the `top`
  subprocess starves Swift concurrency's thread pool and freezes unrelated
  `await`s; `Shell.offloaded` moves every blocking call to a separate queue.
- **Nothing samples while the window is invisible.**
  `applicationDidChangeOcclusionState` stops the whole loop; measured result
  is 0.1%.
- The sampling interval adapts to the active tab (2–10 s); expensive work
  (process list, disk scan) runs only while its tab is open.

---

## Architecture

```
Sources/Aegis/
  App/        AegisApp, RootView (sidebar + page scaffold), Snapshot (dev tool)
  Design/     Theme (palette + formatting), GlassKit (glass surfaces, background, meters)
  Components/ Gauges (ring/arc gauge, sparkline, StatBlock)
  Models/     Pure data structures (all Equatable + Sendable)
  Services/   Measurement and business logic — fully UI-independent
  Views/      One file per tab
```

Data flow is one-directional: `Services` → `SystemMonitor`
(`@MainActor @Observable`) → `Views`. All sampling happens on background
tasks via `Task.detached`; the main thread only writes state.

### Data sources

| What | Where from |
|---|---|
| Battery health, cycles, current, voltage, temperature | IOKit `AppleSmartBattery` |
| Battery lifetime log, cell voltages | IOKit `AppleSmartBattery → BatteryData` |
| Battery condition | `IOPSCopyPowerSourcesInfo` |
| Memory | Mach `host_statistics64(HOST_VM_INFO64)`, `sysctl vm.swapusage` |
| CPU | Mach `host_processor_info(PROCESSOR_CPU_LOAD_INFO)`, `getloadavg` |
| Process energy impact | `top -stats power` (no root required) |
| Process name | `proc_pidpath`, falling back to `sysctl KERN_PROCARGS2` (argv[0]) |
| Hardware | `sysctl`, `IOServiceMatching("AGXAccelerator")`, `system_profiler` (once) |
| Storage | `URLResourceValues` (volume keys), file enumeration |
| Startup items | `LaunchAgents` / `LaunchDaemons` plists |

### How every metric is computed

No black boxes — what each number is based on and how it is derived:

| Metric | Formula / Source |
|---|---|
| **Charge percent** | `AppleRawCurrentCapacity / AppleRawMaxCapacity × 100` (mAh ratio); falls back to the system's `CurrentCapacity` percentage. May differ from the menu bar by ±1–2 points — the OS smooths its SOC. |
| **Battery health** | `NominalChargeCapacity / DesignCapacity × 100`, capped at 100%. Falls back to `AppleRawMaxCapacity`. |
| **Battery temperature** | `Temperature / 100` (centi-°C). In the gauge lifetime log, min/max are whole °C and the average is 0.1 °C resolution — validated against real hardware readings. |
| **Wear forecast** | Loss per cycle = `(100 − health%) / cycles`. Cycles to 80% = `(health% − 80) / loss per cycle`. Daily rate = `cycles / (gauge operating hours / 24)`. A **linear model** with two honesty gates: if total loss is under 1 percentage point (inside the gauge's recalibration noise band) no forecast is produced at all; if the computed horizon exceeds 10 years no date is given ("10+ years") — at that scale calendar aging dominates, not cycling. Fewer than 25 cycles is additionally flagged "unreliable". |
| **Memory used** | `app + wired + compressed` — the same definition Activity Monitor uses. App memory = `internal_page_count − purgeable_count`; cached files = `external_page_count + purgeable_count`; free = `free_count − speculative_count` (matching `vm_stat`). |
| **Memory pressure** | Floor from `kern.memorystatus_vm_pressure_level` (normal=0, warning=50, critical=80), plus `(wired + compressed) / total` and a swap weight capped at 25 points. An **estimate** converging on Activity Monitor's graph. |
| **CPU usage** | Delta of `host_processor_info` tick counters between samples: `(user + nice + system) / total`. The first sample is the reference. |
| **Energy Impact** | `top -stats power` — macOS's own Energy Impact metric (CPU time + wakeups + disk/GPU activity). Aegis reads this number; it does not invent it. |
| **Storage** | `volumeAvailableCapacityForImportantUsage` includes purgeable space, which is why "Available" can exceed "Free". Folder sizes count allocated blocks (`totalFileAllocatedSize`). |
| **Aegis Score** | Weighted average: battery 25% (`(health−70)/30×100 − cycle penalty`), memory 25% (`100 − pressure`), storage 20% (100 up to 70% full, 0 at 95%), energy 18% (`100 − min(60, worst) − min(40, total/8)`), thermal 12% (nominal=100, fair=78, serious=45, critical=10). On Macs without a battery (Mac mini/Studio) the weights renormalize over the remaining components. |

---

## Development

```bash
swift build -c release                  # compile only
./build_app.sh release                  # produce the .app bundle

# Renders every tab to PNG (for UI verification)
AEGIS_SNAPSHOT=/tmp/aegis-shots ./build/Aegis.app/Contents/MacOS/Aegis

# Disable transparency (the system's "Reduce transparency" is also honored)
AEGIS_PLAIN=1 ./build/Aegis.app/Contents/MacOS/Aegis

# Deletion-gate self-test (0 = all cases passed)
AEGIS_SELFTEST=1 ./build/Aegis.app/Contents/MacOS/Aegis
```

---

## License

[MIT](LICENSE) — Copyright © 2026 Yavuzhan Kurşun. See
[CONTRIBUTING.md](CONTRIBUTING.md) for contributions and
[SECURITY.md](SECURITY.md) for vulnerability reports.
