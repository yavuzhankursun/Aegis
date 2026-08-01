# Changelog

All notable changes to Aegis are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
adheres to [Semantic Versioning](https://semver.org/).

## [1.1.0] - 2026-08-01

### Added
- `AEGIS_PRIVATE=1` — masks serial numbers at the source for shareable
  screenshots; README now ships masked screenshots
- Homebrew tap: `brew install yavuzhankursun/tap/aegis` (builds from source;
  `AEGIS_SWIFT_FLAGS` hook in `build_app.sh` for sandboxed environments)
- Social preview image generator (`Tools/makesocial.swift`)

### Changed
- Snapshot tool renders each tab at its full content height

## [1.0.0] - 2026-08-01

First public release.

### Added
- **Overview** tab: Aegis Score (weighted battery/memory/storage/energy/thermal),
  component breakdown, weakest-link display, system insights
- **Battery** tab: health, cycles, live power flow, wear forecast with honest
  reliability gating, gauge-chip lifetime log (operating hours, lifetime
  temperature range, peak currents, pack voltage range, daily charge window),
  per-cell voltages with imbalance detection
- **Performance** tab: Activity-Monitor-compatible memory breakdown
  (app/wired/compressed/cached/free), pressure estimate, swap, CPU load,
  RAM-hungry process list with polite Cmd+Q-equivalent quit
- **Energy** tab: process ranking by macOS's own Energy Impact metric
- **Storage** tab: volume usage with purgeable-aware available space, real
  user-folder sizes
- **Cleanup** tab: cache/log/build-output/leftover scanning, move-to-Trash
  cleanup guarded by `SafetyGuard.verify()` (36-case self-test,
  `AEGIS_SELFTEST=1`)
- **Startup** tab: launch agent/daemon inspector with ghost-target detection
  and spoof-resistant Apple badge
- **Hardware** tab: chip, P/E core layout, GPU cores, displays, SIP, uptime
- **Welcome screen** on first launch: explains the app, then walks through
  every permission — why it's needed, when macOS will ask, and what happens
  if you decline (nothing breaks; unreadable places are skipped). Reachable
  again via Help → "Hoş Geldin Ekranını Göster"
- Liquid Glass UI with measured self-footprint: ~5.6% CPU frontmost,
  ~0.1% occluded, sampling fully stopped while the window is hidden

### Security
- Deletion gate with symlink resolution, segment-boundary path matching,
  reverse-DNS-only rules for shared regions, container cache isolation,
  unconditional denial of user-data regions; all decisions pinned by the
  built-in self-test
- No network, no elevated privileges, no shell interpreter, allowlisted
  read-only external binaries only
