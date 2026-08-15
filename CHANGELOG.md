# Changelog

All notable MacVigil changes are documented here.

## [0.9.2] - 2026-08-15

### Job Guard now survives live mode changes

This patch fixes a session-ownership bug in Job Guard.

When Job Guard is protecting a PID or a command, changing the active MacVigil mode now changes only the underlying power-protection profile. Job Guard stays attached to the same job and continues to own the session lifetime.

For example, this is now supported without detaching Job Guard:

**Compute Guard → Closed-Lid Eco → Full Awake**

The protected PID/command, Job Guard elapsed time, and "run until the job finishes" behavior remain intact through the change.

### Safer live handoffs

MacVigil now distinguishes an intentional internal live reconfiguration from a real user-requested Stop Vigil action.

This prevents the brief low-level stop/restart used to apply a new mode or option from being misinterpreted as the end of Job Guard.

If the protected job finishes during that short handoff, MacVigil waits for the handoff to complete and then releases Vigil normally, so an indefinite session is not left behind.

The updater also treats a live reconfiguration as an active session, preventing an automatic update from starting in the middle of a mode change.
## [0.9.1] - 2026-08-15

### Easier Stop Vigil and Update controls

This patch focuses on the two actions that must always be easy to reach: stopping an active Vigil session and installing an available update.

#### Larger critical actions

When Vigil is active, MacVigil now exposes a large **Stop Vigil** button with a full-width hit target instead of relying only on the small Vigil switch.

When an update is available, a large **Update to <version>** action is shown alongside it. These controls remain visually separated from the smaller configuration controls so they are easier to target with the pointer.

#### Reliable stop-and-update confirmation

If an update is requested while Vigil is active, the decision is now handled in a normal standalone macOS window rather than depending on a confirmation alert attached to the transient menu-bar panel.

The window provides large buttons for:

- **Stop Vigil & Update**
- **Keep Vigil Running**
- **View Release**

It also shows the current Vigil mode and remaining timer before you stop the session.

MacVigil restores normal sleep behavior before beginning the update. If the update cannot continue, the window stays open and reports the error instead of disappearing.

### Interaction details

- Stop and Update actions use larger native controls and explicit rectangular hit targets.
- The buttons expose visible working states such as **Stopping…** and **Updating…**.
- Update installation remains SHA-256 verified before the app is replaced.
- Existing automatic-update behavior is unchanged: automatic installation still waits until no Vigil session is active.
## [0.9.0] - 2026-08-15

### Power Intelligence

v0.9 adds a dedicated **Power Intelligence** view for understanding what a Vigil session is doing to the Mac over time.

It shows:

- current battery percentage and power source
- current macOS thermal-pressure state
- an estimated time to the configured battery reserve when macOS provides a usable discharge-time estimate
- live Vigil session duration and starting/current battery state
- the highest thermal-pressure state seen during the active session
- lightweight history for recent Vigil sessions, including duration, battery change, and peak thermal pressure

A compact Power Intelligence row is also available directly from the menu-bar panel.

### Safer sustained closed-lid work

A new **Require external power** option can be enabled for closed-lid protection.

When enabled, MacVigil releases an active closed-lid Vigil if the Mac switches to battery power. This is useful for sustained local-AI, build, render, and other high-load workloads that you only want to run closed-lid while plugged in.

The existing configurable battery reserve remains available when closed-lid operation on battery is allowed.

### Thermal warnings

While Vigil is active, MacVigil now surfaces **Serious** and **Critical** macOS thermal-pressure states more prominently and can send a local notification when thermal pressure rises.

MacVigil still does not attempt to override mandatory macOS thermal, critical-battery, shutdown, or hardware safety behavior.

### Repeatable benchmark harness

The repository now includes `scripts/power-benchmark.sh` for repeatable baseline data collection.

The harness records:

- hardware and macOS metadata
- current power settings and power assertions
- timed battery-percentage samples
- power-source state
- macOS-reported remaining-time text
- `pmset` thermal snapshots
- initial and final raw battery-registry information when available

See `docs/POWER-BENCHMARKS.md` for the comparison protocol.

The harness is deliberately conservative: coarse battery-percentage sampling is **not** presented as precise whole-system energy measurement, and MacVigil still makes no blanket claim that it uses less power than another utility without reproducible measurements.

## [0.8.0] - 2026-08-15

### Added

- local smart workload suggestions in Job Guard for common AI agents, local-AI runtimes, build tools, container runtimes, development servers, and transfer jobs
- workload-category labels and icons in both suggested and full process lists
- background process scan at app launch so likely workloads can be surfaced before Job Guard is opened
- curated, versioned GitHub release notes under `release-notes/`

### Changed

- Job Guard now places likely long-running developer workloads at the top as opt-in suggestions while keeping the full process picker available
- process search can match workload categories as well as process names, paths, and PIDs
- the main menu-bar panel can indicate when Job Guard has likely workloads ready for review
- release automation uses human-written notes for a version when they are available and falls back to GitHub-generated notes otherwise

### Safety & privacy

- workload detection is advisory only: MacVigil never starts Vigil or attaches to a detected process without explicit user action
- detection uses the local process list and does not require telemetry, an account, or a cloud service
- heuristic matches may be incomplete or imperfect; users can always choose any process manually

## [0.7.0] - 2026-08-15

### Added

- a searchable **Job Guard process picker** so users can protect running apps and processes without finding a PID manually
- app icons, PID, and current CPU usage in the process picker when available
- one-click refresh plus manual PID entry for advanced cases
- live Job Guard elapsed time in both the main panel and Job Guard window
- recent command history with quick reuse and clear-history controls
- last-job duration and command exit status feedback
- actionable update notifications with **Update Now**, **Later**, and **View Release** actions
- explicit Launch at Login success/failure status in the updater
- the updater records its most recent background check time for UI/diagnostic use

### Changed

- Job Guard is now centered on choosing the work to protect rather than asking users to understand process IDs
- the main menu-bar panel exposes Job Guard log and detach actions while a job is active
- command and process jobs show a clearer active state, elapsed runtime, and protected PID
- update notifications are presented even while the menu-bar app is already running in the foreground
- the README now describes Job Guard and background updates at a product level without implementation-heavy detail

### Safety

- selecting a process never terminates or modifies that process; MacVigil only watches for its exit
- detaching Job Guard leaves both the protected process and the current Vigil session running
- **Update Now** from a notification does not interrupt an active Vigil session; the update waits for the user to end Vigil first

## [0.6.2] - 2026-08-15

### Fixed

- automatic update checks now start from the MacVigil application lifecycle instead of waiting for the menu-bar panel to be opened
- update notifications no longer depend on clicking or interacting with the MacVigil UI first
- automatic installation can proceed in the background once Vigil becomes inactive

### Added

- an immediate update check when MacVigil launches
- hourly background release checks while MacVigil is running
- a fresh release check after the Mac wakes from sleep
- notification authorization is prepared at app startup when automatic update checking is enabled
- **Launch MacVigil at Login** using the macOS ServiceManagement API, available from the bottom-bar options menu

### Changed

- GitHub update requests bypass stale local cache data so the latest release is discovered promptly
- the updater keeps its background monitoring alive independently of the transient MenuBarExtra content view

## [0.6.1] - 2026-08-15

### Fixed

- Job Guard no longer uses a transient SwiftUI sheet attached to the menu-bar window
- PID and command text fields now live in a dedicated MacVigil window so they keep keyboard focus and remain interactive
- pressing Return in either Job Guard field now starts the corresponding action when the input is valid

### Changed

- **Configure / Manage Job Guard** opens a normal macOS window that can stay open independently of the menu-bar panel
- Job Guard continues to share the same live Vigil, PID, command, log, and completion state with the menu-bar app

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
