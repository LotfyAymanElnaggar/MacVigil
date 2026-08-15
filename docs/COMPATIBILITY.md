# Compatibility

MacVigil's ordinary Compute Guard and Full Awake profiles use standard macOS power-management mechanisms and should be significantly less sensitive to hardware/OS differences than Closed-Lid Eco.

Closed-Lid Eco is experimental because it currently combines `pmset disablesleep` with an internal IOPM clamshell selector and private display-brightness functions.

## Test matrix

| Mac model | Chip | macOS | Compute Guard | Full Awake | Closed-Lid Eco | Backlight restore | Notes |
|---|---|---|---|---|---|---|---|
| Test data needed | — | — | — | — | — | — | Please submit compatibility reports |

## What counts as a successful Closed-Lid Eco test

A useful compatibility report should verify all of the following:

1. Vigil is active before closing the lid.
2. `SleepDisabled` is confirmed when MacVigil owns that state.
3. the kernel selector reports success.
4. a real workload continues for at least several minutes with the lid closed.
5. networking remains available if the workload needs it.
6. battery/thermal safety remains functional.
7. opening the lid restores brightness and ordinary sleep behavior after Vigil ends.
8. `pmset -g log` does not show an unexpected Clamshell Sleep during the test window.

## Report format

```text
Mac model:
Chip:
RAM:
macOS version/build:
Power source:
External display(s):
Profile:
Test workload:
Test duration:
Result:
Diagnostics attached: yes/no
```

## Important limitation

A single successful model/OS test does not prove compatibility with a future macOS build. Internal clamshell and DisplayServices behavior can change independently of MacVigil.
