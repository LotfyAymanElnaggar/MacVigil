# Changelog

All notable MacVigil changes will be documented here.

## [0.2.0] - 2026-08-15

### Added

- independent on/off switches for system sleep, idle system sleep, display sleep protection, and idle-sleep veto behavior
- independent closed-lid switches for global `SleepDisabled`, the experimental kernel clamshell guard, and built-in backlight darkening
- independent battery-reserve and critical-thermal safety switches
- Compute Guard, Closed-Lid Eco, and Full Awake as presets that populate the switches instead of locking users into fixed profiles
- explicit live readback for `SleepDisabled` and kernel lid-guard state
- `SYSTEM WILL SLEEP` tracking to distinguish real system-sleep transitions from display-only sleep
- a timestamped MacVigil runtime event trail in diagnostics
- clearer authorization status when another compatible sudoers rule already grants the two exact `pmset disablesleep` commands

### Changed

- closed-lid protection is re-applied immediately on the physical lid-close edge and periodically while active
- the crash watchdog now reinforces the protection layers actually selected by the user
- when MacVigil owns `SleepDisabled`, the watchdog also reinforces it during the session and restores it after a crash
- closed-lid sessions refuse to start if the crash-recovery watchdog cannot be launched
- diagnostics now retain the last 120 lines of the `pmset` log for better sleep/wake investigation
- the menu-bar window has been reorganized around visible switches rather than hidden profile behavior

### Notes

This release hardens the closed-lid path, but closed-lid behavior remains experimental and must be validated across macOS and Mac hardware combinations. A display turning off or a Lock Screen appearing is not by itself proof of full system sleep; the new sleep-transition diagnostics are intended to make that distinction explicit.

## [0.1.0] - 2026-08-15

### Added

- fresh MacVigil repository and product identity
- new `com.lotfy.macvigil` bundle identity
- redesigned SwiftUI menu-bar interface
- Compute Guard, Closed-Lid Eco, and Full Awake runtime profiles
- timed, custom, and indefinite sessions
- modular IOKit power assertion controller
- active system idle-sleep veto
- experimental root-domain clamshell guard
- narrowly scoped `pmset disablesleep` authorization
- experimental built-in backlight darkening/restoration
- crash-safe `MacVigilWatchdog`
- low-battery reserve and critical thermal-pressure closed-lid shutdown
- detailed diagnostics
- universal Apple Silicon + Intel GitHub Actions builds
- release workflow with downloadable DMG and SHA-256 checksum
- power-efficiency philosophy and benchmark methodology
- use-case, architecture, security, troubleshooting, and compatibility documentation

## Versioning

MacVigil is in a pre-1.0 stabilization phase. The project will not tag 1.0 until closed-lid compatibility, crash recovery, safety behavior, power benchmarks, and signed/notarized distribution meet the criteria in [ROADMAP.md](ROADMAP.md).
