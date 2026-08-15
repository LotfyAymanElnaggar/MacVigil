# Contributing to MacVigil

Thanks for helping improve MacVigil.

Power-management code deserves more caution than an ordinary UI utility because a bug can leave system-wide sleep behavior changed after the app exits.

## Before changing power code

Please understand the ownership and cleanup rules documented in:

- [Architecture](docs/ARCHITECTURE.md)
- [Security Model](docs/SECURITY-MODEL.md)
- [Power Efficiency](docs/POWER-EFFICIENCY.md)

## Core invariants

A change should preserve these rules:

1. Ordinary Compute Guard / Full Awake operation must not require administrator privileges.
2. Closed-lid authorization remains limited to the two exact `pmset disablesleep` commands.
3. MacVigil must not disable a pre-existing `SleepDisabled` state it did not create.
4. Every experimental/global state change needs a cleanup path.
5. The crash watchdog must remain ownership-aware.
6. Mandatory battery/thermal/shutdown safety must remain authoritative.
7. Lock Screen/password policy must not be silently weakened.
8. Private/internal macOS mechanisms must be described as experimental.
9. Power-efficiency claims require measurements, not architectural guesses.

## Build

GitHub Actions builds universal Apple Silicon + Intel artifacts on `macos-15`.

The project intentionally does not require an `.xcodeproj` for CI; the workflow compiles the Swift source files directly with `swiftc`.

Before opening a pull request, make sure the **Build MacVigil** workflow succeeds.

## Code organization

Keep responsibilities separated:

```text
MacVigil/App          app lifecycle
MacVigil/UI           SwiftUI presentation
MacVigil/Models       user-facing/session models
MacVigil/Core/Power   power assertions and sleep notifications
MacVigil/Core/Lid     clamshell/root-domain behavior
MacVigil/Core/Display display/backlight behavior
MacVigil/Core/Runtime session policy/orchestration
MacVigilWatchdog      crash cleanup companion
```

Avoid moving low-level IOKit/DisplayServices implementation directly into SwiftUI views.

## Testing closed-lid changes

Closed-lid changes should be tested deliberately, not first tried with valuable work running.

Record:

- Mac model
- chip
- exact macOS version/build
- power source
- external display configuration
- battery reserve
- thermal state
- copied diagnostics

Prefer external power and a well-ventilated surface while testing experimental lid behavior.

## Power benchmark changes

If a PR makes an efficiency claim, follow [docs/POWER-BENCHMARKS.md](docs/POWER-BENCHMARKS.md).

A fair comparison must hold hardware, OS, workload, duration, display state, and power source constant.

## Pull requests

Keep PRs focused. In the description include:

- problem being solved
- behavior before/after
- safety/cleanup implications
- testing performed
- hardware/macOS build for lid or display changes

## Security issues

Do not place passwords, credentials, or sensitive logs in public issues. See [docs/SECURITY-MODEL.md](docs/SECURITY-MODEL.md).
