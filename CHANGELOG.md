# Changelog

All notable MacVigil changes are documented here.

## [0.6.0] - 2026-08-15

### Added

- **Job Guard** for job-aware Vigil sessions
- watch an existing PID and automatically release Vigil when that process exits
- launch a non-interactive `/bin/zsh -lc` command and keep Vigil active until the command finishes
- captured command output with an **Open Log** action
- a persistent Job Guard status bar in the menu-bar window plus a dedicated configuration sheet
- automatic restoration of the user's normal duration preference after a Job Guard completes

### Changed

- Job Guard switches the active session to an indefinite job-owned duration so a guessed timer cannot expire before the protected work finishes
- mode and protection controls remain live while Job Guard is active
- the public README now explains job-aware sessions without exposing implementation detail

### Safety

- stopping Vigil manually detaches Job Guard rather than pretending the job is still protected
- detaching Job Guard leaves the actual job running and leaves Vigil in its current state
- commands are explicitly non-interactive and run from the user's home directory; interactive terminal integration remains future work

## [0.5.0] - 2026-08-15

### Added

- a built-in GitHub release updater with automatic checks, update notifications, manual **Update Now**, and optional automatic installation when no Vigil session is active
- SHA-256 verification against the GitHub release asset digest before an automatic install is staged
- a visible update banner and menu-bar update indicator when a newer release is available
- stronger hover, press, tooltip, and row interaction feedback throughout the menu-bar UI

### Fixed

- changing mode or protection options during an active Vigil now preserves the exact running deadline instead of rounding the remaining time up to a new custom-minute timer
- the selected mode now has a persistent accent border, accent fill, and checkmark so the current mode is visually unambiguous

### Changed

- mode cards now animate on hover and press
- advanced option rows now respond visually to pointer hover
- automatic updates wait until an active Vigil session has ended; a manual update during an active session asks before stopping Vigil and restarting the app

## [0.4.1] - 2026-08-15

### Added

- modes can now be changed while a Vigil session is active
- protection and safety switches can now be changed while a Vigil session is active
- live mode/option changes preserve the remaining countdown instead of restarting the full timer
- changing duration while active intentionally starts a fresh countdown using the newly selected duration
- live changes preflight closed-lid authorization before interrupting a working session

### Safety

- MacVigil blocks removal or transition of lid/display protection while the physical lid is closed; open the lid first
- Closed-Lid Eco still keeps macOS Lock Screen and password policy unchanged

## [0.4.0] - 2026-08-15

### Added

- persistent user preferences for duration, protection switches, battery reserve, and safety options
- a compact Ready Check before starting and Live Confirmation while a session is active
- explicit confirmation of closed-lid authorization, display/Lock Screen policy, SleepDisabled readback, kernel lid-guard state, and safety cutoffs
- a first-use closed-lid safety confirmation without changing macOS password or Lock Screen settings
- a documented validation checklist covering open-lid idle, closed-lid continuity, battery, charger, external display, clean stop, and watchdog recovery tests
- CI checks that confirm plist/version consistency, universal arm64 + x86_64 binaries, DMG creation, checksum generation, and release metadata

### Changed

- the menu-bar interface is simplified around one main Vigil switch, three modes, duration, and a visible readiness card
- low-level switches are moved into an Advanced Controls disclosure while remaining independently configurable
- MacVigil now remembers the user's selected controls across relaunches
- release automation performs explicit validation before publishing a normal GitHub Release

## [0.3.0] - 2026-08-15

### Changed

- Closed-Lid Eco now enables display-sleep prevention by default while still darkening the built-in display on lid close. This avoids relying on display sleep, which can trigger the user's macOS Lock Screen policy.
- clarified in-app display and Lock Screen behavior without changing or weakening macOS security settings
- simplified and polished the public README, keeping implementation detail in the docs
- GitHub release workflow now publishes normal releases instead of marking every version as a pre-release

## [0.2.0] - 2026-08-15

### Added

- independent on/off switches for system sleep, idle system sleep, display sleep protection, and idle-sleep veto behavior
- independent closed-lid switches for global `SleepDisabled`, the experimental kernel clamshell guard, and built-in backlight darkening
- independent battery-reserve and critical-thermal safety switches
- Compute Guard, Closed-Lid Eco, and Full Awake as presets that populate the switches instead of locking users into fixed profiles
- explicit live readback for `SleepDisabled` and kernel lid-guard state
- `SYSTEM WILL SLEEP` tracking to distinguish real system-sleep transitions from display-only sleep
- a timestamped MacVigil runtime event trail in diagnostics

### Changed

- closed-lid protection is re-applied immediately on the physical lid-close edge and periodically while active
- the crash watchdog reinforces the protection layers selected by the user
- closed-lid sessions refuse to start if the crash-recovery watchdog cannot be launched

## [0.1.0] - 2026-08-15

### Added

- first MacVigil release
- native menu-bar interface
- Compute Guard, Closed-Lid Eco, and Full Awake presets
- timed, custom, and indefinite sessions
- closed-lid runtime protection
- built-in display darkening and restoration
- crash recovery watchdog
- battery reserve and thermal safeguards
- universal Apple Silicon + Intel builds

## Versioning

MacVigil remains in a pre-1.0 stabilization phase. Version 1.0 is reserved for broader closed-lid compatibility, recovery testing, power measurements, and signed/notarized distribution.
