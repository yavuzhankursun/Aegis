# Security Policy

## Reporting a vulnerability

Please **do not** open a public issue for security problems. Use GitHub's
private vulnerability reporting instead: **Security → Report a vulnerability**
on this repository. You will get a response within 7 days.

Relevant classes of issues (non-exhaustive):

- A path that `SafetyGuard.verify()` allows but that can contain real user
  data (false positive in the deletion gate)
- Symlink / path-traversal / TOCTOU tricks that route a deletion outside the
  allow-listed roots
- Command-injection vectors into `Shell.run` call sites
- Any way to make the app write to system state

## Threat model

Aegis runs unsandboxed as the logged-in user, unprivileged, with no network
access. The deletion gate defends against **bugs and confused-deputy
mistakes** (bad scan results, symlink traps in scanned directories, malformed
names), not against an attacker already executing arbitrary code as the same
user — such an attacker can trash files directly without involving Aegis.
Time-of-check/time-of-use windows between `verify()` and `trashItem` are
mitigated (verify runs again at deletion time, symlink leaves rejected) but
cannot be fully eliminated with `FileManager` APIs; deletions are trash-moves
precisely so that the residual window's worst case remains recoverable.

## Scope notes

- The app requests no entitlements beyond defaults and asks for Full Disk
  Access only optionally, for reading sizes.
- `Shell` executes only allowlisted absolute paths (`top`, `sysctl`,
  `system_profiler`, `csrutil`, `ioreg`, …) without a shell interpreter.
- The self-test (`AEGIS_SELFTEST=1`) pins the deletion gate's behavior;
  regressions exit non-zero.
