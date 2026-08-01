## What & why

<!-- Short description of the change and its motivation. -->

## Safety checklist

- [ ] `swift build -c release` succeeds with no new warnings
- [ ] `AEGIS_SELFTEST=1` exits 0
- [ ] If `SafetyGuard` / `CleanupService` / `LeftoverService` changed: new
      self-test cases pin the behavior (both allow- and deny-side)
- [ ] No new dependencies, no network calls, no elevated privileges,
      no additions to `Shell.allowedBinaries` (or justified below)

## Performance

<!-- If this adds sampling/animation: `ps -o time` delta before vs after. -->
