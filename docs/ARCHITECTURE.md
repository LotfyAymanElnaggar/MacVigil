# Architecture

MacVigil separates the user-facing runtime profile from the low-level mechanisms used to keep macOS available.

## High-level flow

```text
MacVigilApp / MenuBarView
          │
          ▼
     VigilManager
          │
          ├── PowerAssertions
          ├── SystemPowerVeto
          ├── RootDomainLidGuard
          ├── BacklightController
          ├── ShellRunner / pmset
          └── MacVigilWatchdog
```

## `VigilManager`

`VigilManager` owns session lifecycle and policy. It decides which mechanisms are needed for the selected runtime profile and publishes observable state to SwiftUI.

It is responsible for:

- start/stop lifecycle
- duration timers
- process activity token
- low-battery reserve
- thermal-pressure response
- closed-lid ownership state
- watchdog heartbeat
- diagnostics
- restoration order

It should not grow into a collection of duplicated low-level IOKit code; those operations live in dedicated controllers.

## Power assertions

`PowerAssertions` creates IOKit assertions for:

- `kIOPMAssertionTypePreventSystemSleep`
- `kIOPMAssertionTypePreventUserIdleSystemSleep`
- `kIOPMAssertionTypePreventUserIdleDisplaySleep` only when the selected profile requires the display to stay awake

Compute Guard intentionally omits the display assertion.

The manager also uses `ProcessInfo.beginActivity` with `.idleSystemSleepDisabled`, and `.idleDisplaySleepDisabled` only for Full Awake.

## System sleep veto

`SystemPowerVeto` registers with `IORegisterForSystemPower`.

While a Vigil session is active, an ordinary `kIOMessageCanSystemSleep` request is cancelled. Mandatory `kIOMessageSystemWillSleep` notifications are acknowledged rather than defeated.

After `kIOMessageSystemHasPoweredOn`, the manager re-applies closed-lid state if needed.

This is not intended to override mandatory safety behavior.

## Closed-Lid Eco

Closed-Lid Eco currently combines multiple layers because lid closure is not equivalent to ordinary idle sleep.

### `pmset disablesleep`

MacVigil can install one sudoers fragment:

```text
/etc/sudoers.d/macvigil
```

The generated rule grants only:

```text
/usr/bin/pmset -a disablesleep 1
/usr/bin/pmset -a disablesleep 0
```

MacVigil records whether **it** turned on `SleepDisabled`. If the setting was already enabled by another tool, MacVigil does not claim ownership and should not turn it off later.

### Root-domain clamshell guard

`RootDomainLidGuard` opens `IOPMrootDomain` and currently calls external selector `12` with scalar `1`/`0` to arm/release the clamshell-sleep override.

This is an internal/undocumented mechanism and is treated as experimental. It may change across macOS versions.

The guard is re-applied:

- when Closed-Lid Eco starts
- on a detected lid-close edge
- periodically while armed
- after a system powered-on notification

## Display/backlight behavior

`BacklightController` loads the private DisplayServices framework at runtime and resolves brightness functions dynamically.

When Closed-Lid Eco is active, the physical lid is closed, and no external display is online, MacVigil can:

1. save built-in display brightness,
2. persist that saved value for crash recovery,
3. request brightness `0`,
4. restore the saved brightness when the lid reopens or the mode ends.

This is **not** documented as true panel power-off. The power benchmark plan treats brightness 0 and display sleep as separate states.

External displays are not deliberately blanked by this mechanism.

## Watchdog

`MacVigilWatchdog` is a small companion executable packaged in the app bundle.

Arguments include:

- parent PID
- random heartbeat token path and contents
- saved-brightness file path
- built-in display ID
- whether MacVigil owns `SleepDisabled`

The GUI refreshes the heartbeat periodically. If the parent disappears, the token vanishes, or the heartbeat becomes stale, the watchdog attempts to:

- release root-domain selector 12
- restore `SleepDisabled=0` only if MacVigil owned it
- restore saved brightness
- remove temporary recovery files

This protects against leaving global state behind after a crash.

## Safety timer

The manager periodically refreshes:

- battery level and power source
- thermal pressure
- `SleepDisabled` readback
- root-domain clamshell guard
- lid/display state

Current closed-lid policy:

- stop at the selected battery reserve while on battery
- disarm Closed-Lid Eco at critical thermal pressure

Mandatory macOS safety behavior remains authoritative.

## Diagnostics

Diagnostics intentionally expose low-level truth rather than only a green/red UI state. They include:

- selected runtime profile
- IOKit/pmset authorization state
- physical lid state
- external display detection
- kernel selector state and return code
- `AppleClamshellCausesSleep`
- `SleepDisabled`
- backlight state
- battery and thermal state
- recent sleep veto/wake timestamps
- `pmset -g`
- `pmset -g assertions`
- `pmset -g batt`
- clamshell I/O Registry output
- recent `pmset -g log`

## Distribution

The GitHub Actions build produces a universal arm64 + x86_64 app and companion watchdog.

Until Developer ID signing and notarization are configured, builds are ad-hoc signed. The roadmap treats proper direct-distribution signing/notarization as a 1.0 requirement.

## Compatibility rule

Private/internal behavior must be isolated, observable, and reversible. If a future macOS version rejects a private mechanism, MacVigil should report that fact rather than silently claiming closed-lid protection is active.
