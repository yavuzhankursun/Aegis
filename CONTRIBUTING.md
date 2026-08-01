# Contributing to Aegis

Thanks for your interest! Aegis is a safety-critical utility — it enumerates
and (with user confirmation) trashes files — so contributions are reviewed
with that lens first.

## Building

```bash
git clone https://github.com/yavuzhankursun/Aegis.git
cd Aegis
swift build -c release        # compile
./build_app.sh release        # full .app bundle
```

Requirements: macOS 26 (Tahoe), Xcode 26 or Command Line Tools, Swift 6.2
toolchain. No external dependencies — please keep it that way; PRs adding
third-party packages will not be merged.

## The safety contract (non-negotiable)

1. **Every deletion goes through `SafetyGuard.verify()`** — no exceptions,
   no alternate code paths to `trashItem`/`removeItem`.
2. **Any PR touching `SafetyGuard`, `CleanupService`, or `LeftoverService`
   must pass and extend the self-test:**

   ```bash
   AEGIS_SELFTEST=1 ./build/Aegis.app/Contents/MacOS/Aegis   # exit 0 required
   ```

   If you change a rule, add cases to `SafetyGuardSelfTest.swift` that pin
   the new behavior — both the "must allow" and the "must deny" side.
3. **Deny by default.** When a rule is ambiguous, the answer is "deny".
   A false negative (not offering a cache for cleanup) is a cosmetic bug;
   a false positive (offering user data) is a critical one.
4. **Read-only telemetry.** No writes to system settings, plists, SMC, or
   IORegistry. No new entries in `Shell.allowedBinaries` unless the binary
   is strictly read-only, and never `/bin/sh -c`.
5. **No elevated privileges, no network.** PRs adding `sudo` helpers,
   privileged helpers, analytics, or any network call will not be merged.

## Code style

- Swift 6 strict concurrency; services are `Sendable`, UI state lives in
  `@MainActor @Observable SystemMonitor`.
- Small views: one file per tab, cards as separate `View` structs (this is
  a measured performance requirement, not aesthetics — see README).
- Stable identity for `Identifiable` models — never `UUID()` per compute.
- Compare-before-assign for `@Observable` state:
  `if value != new { value = new }`.
- Comments explain **why**, in the codebase's existing style.

## Performance bar

The app must stay under ~6% CPU frontmost and ~0.1% occluded (see README
measurements). If your change adds sampling or animation, measure with
`ps -o time` deltas before and after, and include the numbers in the PR.

## PR checklist

- [ ] `swift build -c release` succeeds with no new warnings
- [ ] `AEGIS_SELFTEST=1` exits 0 (36+ cases)
- [ ] New SafetyGuard rules have both allow- and deny-side test cases
- [ ] No new dependencies, no network, no privileged operations
- [ ] Commit messages: `type: description` (feat, fix, refactor, docs, test, chore, perf)
