# Changelog

All notable MacVigil changes are documented here.

## [0.14.2] - 2026-08-16

### Settings usability cleanup

This release is based directly on hands-on screenshots from v0.14.1 and focuses on removing dead UI, fixing cramped views, and exposing features that already existed in the runtime but were difficult to discover from the app.

#### Appearance page removed

The Settings sidebar no longer contains an Appearance page with no actionable controls.

MacVigil follows the active macOS appearance. Native macOS 26 Liquid Glass remains used selectively where the operating system provides it, but there is no pretend appearance setting for behavior the app does not actually control.

#### Start and Stop Vigil from Settings

Settings → General now contains a dedicated **Vigil now** section with:

- current active/idle state
- current protection profile and remaining timer when active
- a large **Start Vigil / Stop Vigil** button
- visible startup errors when a session cannot begin

The sidebar status footer also has a compact Start/Stop action, so Settings is no longer only a configuration window.

#### Hotkey readability

Shortcut glyphs in Settings are now spaced for readability, for example:

```text
⌥ ⌘ V
⌥ ⌘ 1
⌥ ⌘ 2
⌥ ⌘ 3
```

This is a display-only improvement; registered key combinations and saved custom hotkeys are unchanged.

### Responsive Statistics layout

The Statistics dashboard no longer relies on a single fixed-width filter row.

The previous layout could squeeze labels such as **Range** into vertical letter-by-letter text when Statistics was embedded in the narrower Settings detail pane.

The dashboard now uses:

- a dedicated Filters group
- full-width segmented range control
- separate Mode and Owner controls with labels above them
- adaptive metric cards
- adaptive mode/owner/battery summary groups
- responsive recent-session actions
- safer line wrapping for battery, thermal, owner, and status text

The standalone Statistics window is slightly wider as well, while the same dashboard continues to work inside Settings.

### Rebuilt Job Guard window

Job Guard has been rebuilt around the capabilities that are actually available in the current controller instead of hiding several of them.

The new window includes:

- a clearer protected-work summary
- per-item Detach and Log controls
- **Protect Suggested** when local workload suggestions are available
- an explicit loading state while the process list refreshes
- clearer empty/search states
- manual PID entry
- a dedicated **Watch a local TCP port** section
- command working-directory display
- **Choose Folder…** and **Home** controls
- recent command history
- clearer command logging text
- a larger 760 × 780 layout to reduce cramped controls

Port rows identify both the watched TCP port and current listener PID. Detach continues to stop monitoring without terminating the underlying process.

### In-app CLI guide

Settings now has a dedicated **CLI** page.

It explains how to install `/usr/local/bin/macvigil` from the Settings toolbar and includes copyable examples for:

```sh
macvigil status
macvigil status --json
macvigil start --mode compute --duration 2h
macvigil mode full-awake
macvigil stop
macvigil run -- npm test
macvigil run --cwd ~/Projects/app -- npm run build
macvigil watch-pid 43127
macvigil watch-port 3000 5173
macvigil protect-suggested
```

A saved-workflow example is included in the app as well.

The guide also explains that CLI control stays local, shares the same Vigil runtime and Job Guard collection as the GUI, and does not expose a network control server.

### Expanded About page

About now explains more than the version number. It includes:

- MacVigil's runtime-continuity purpose
- common local workload categories
- the lifetime-owner vs protection-profile model
- local-data and telemetry behavior
- closed-lid heat guidance
- physical-display caveat
- current ad-hoc signing / notarization status
- GitHub repository, releases, and issue links

### Documentation

README has been synchronized with the Settings cleanup, responsive Statistics behavior, visible Job Guard controls, spaced shortcut presentation, and in-app CLI guide.

### Release validation

The v0.14.0 packaging regression cannot pass the current workflow: both normal CI and release CI now launch the built `MacVigil` executable and require it to remain alive before packaging or publishing succeeds.

The GUI, watchdog, and CLI also continue to use separated build and bundle paths so the case-insensitive `MacVigil` / `macvigil` executable collision cannot recur.

### Safety and distribution

Closed-Lid Eco remains experimental. Long-running closed-lid workloads can generate significant heat; keep a MacBook on a hard, ventilated surface and never run sustained workloads in a bag, sleeve, drawer, or other enclosed space.

Brightness 0 is not a guarantee that the physical display panel is electrically powered off. Mandatory macOS battery, thermal, shutdown, and Lock Screen behavior remains in control.

MacVigil remains ad-hoc signed rather than Developer ID signed and notarized.

## [0.14.1] - 2026-08-15

### Critical launch hotfix

v0.14.1 fixes a packaging regression in v0.14.0 that caused the installed MacVigil app to exit immediately instead of opening.

#### Root cause

The v0.14.0 build produced the GUI executable as `MacVigil` and the new command-line executable as `macvigil` in the same directories.

macOS uses a case-insensitive filesystem by default, so those two names resolve to the same path. The CLI therefore overwrote the GUI executable during the build. The resulting `MacVigil.app/Contents/MacOS/MacVigil` was actually the command-line program, which printed CLI help and exited successfully when Finder attempted to launch the app.

This was a build/package layout bug, not a Vigil runtime or user preference problem.

### Fix

The three executables now have fully separated build paths:

- the GUI app is built as `MacVigil`
- the crash-recovery helper is built separately as `MacVigilWatchdog`
- the CLI is built in its own per-architecture directory and bundled at `MacVigil.app/Contents/Library/Helpers/macvigil`

The CLI is still copied to the DMG root as `macvigil`, and Settings still installs `/usr/local/bin/macvigil` as a symlink to the helper inside the installed app.

The GUI and CLI therefore no longer share any case-colliding filesystem path.

### New launch gate

CI now does more than compile and verify code signatures.

After building the app, the workflow launches `MacVigil.app/Contents/MacOS/MacVigil`, waits six seconds, and fails if the process exits during startup. The release workflow has the same launch gate before it is allowed to create or publish release assets.

This test reproduced the v0.14.0 failure immediately: the supposed app executable printed `macvigil` CLI help and exited with status 0. After separating the executable paths, the same launch smoke test succeeds and the MacVigil process remains alive.

### CLI installation path

The CLI installer now points to:

```text
/Applications/MacVigil.app/Contents/Library/Helpers/macvigil
```

The user-facing command remains:

```text
/usr/local/bin/macvigil
```

The command-line client also resolves symlinks when locating its containing app, so an installed `/usr/local/bin/macvigil` command can still find the MacVigil bundle reliably.

### v0.14 features retained

This hotfix keeps the v0.14 developer workflow features:

- `macvigil status` and `status --json`
- start / stop / live mode commands
- `macvigil run -- ...`
- working-directory and environment-variable support
- PID watching
- TCP port watching
- Protect Suggested
- saved workflows
- GUI and CLI sharing one Job Guard collection and one Vigil runtime
- Settings-based CLI installation and removal

## [0.14.0] - 2026-08-15

### `macvigil` command-line client

MacVigil now ships a universal command-line client for Apple Silicon and Intel Macs.

The CLI controls the **same running MacVigil app, Vigil session, and Job Guard collection** used by the menu-bar interface. It does not create a second set of power assertions and it does not expose a TCP or HTTP control server.

The local control transport uses macOS `DistributedNotificationCenter` with property-list-safe JSON payloads.

Available commands include:

```sh
macvigil status
macvigil status --json
macvigil start --mode compute --duration 2h
macvigil stop
macvigil mode full-awake
macvigil watch-pid 43127 44102
macvigil watch-port 3000 5173
macvigil protect-suggested
macvigil detach-all
```

If a CLI command needs the MacVigil runtime and the app is not already running, the client attempts to open the installed MacVigil app and waits briefly for the local control channel to become available.

### Protect a terminal command

`macvigil run` launches a command from Terminal and immediately adds the child PID to the existing Job Guard collection:

```sh
macvigil run -- npm test
macvigil run --cwd ~/Projects/app -- npm run build
macvigil run --cwd ~/Projects/app --env NODE_ENV=test -- npm test
```

The child keeps the current Terminal stdin, stdout, and stderr. `macvigil` waits for the child and exits with the child's termination status.

Protection uses the same Job Guard lifetime rule as the GUI: if other protected processes, ports, or commands remain, the Vigil session continues. If the process is the final protected item, Job Guard releases Vigil when it finishes naturally.

If the command starts successfully but Job Guard cannot attach, the CLI reports a warning instead of terminating the workload.

### Saved workflows

Reusable local workflows can combine:

- one or more TCP ports
- one or more commands
- a working directory
- environment variables
- the opt-in Protect Suggested action

Example:

```sh
macvigil workflow save local-stack \
  --port 3000 \
  --port 11434 \
  --command "npm run dev" \
  --cwd ~/Projects/app \
  --env NODE_ENV=development

macvigil workflow run local-stack
```

Workflow management commands:

```sh
macvigil workflow list
macvigil workflow show local-stack
macvigil workflow delete local-stack
```

Saved workflows are stored locally in:

```text
~/Library/Application Support/MacVigil/workflows.json
```

Workflow members join the same Job Guard collection. MacVigil does not create a separate protection session for each member.

### CLI installation from Settings

The Settings toolbar now includes a native **CLI** menu.

After MacVigil is installed in `/Applications`, choose **CLI → Install macvigil CLI** to create:

```text
/usr/local/bin/macvigil
```

The installed command is a symlink to the universal CLI bundled inside `MacVigil.app`. macOS administrator approval is requested only for creating or removing that symlink.

The installer refuses to replace an unrelated non-symlink command. Removal also refuses to delete a symlink that does not point to a MacVigil app bundle.

The release DMG contains a root-level `macvigil` helper as well, but `macvigil install` deliberately refuses to create a persistent symlink back into a temporary mounted DMG. Move MacVigil to `/Applications` first.

### Same Job Guard ownership from GUI and CLI

`watch-pid`, `watch-port`, `protect-suggested`, `run`, saved workflows, and GUI-added workloads all use the same Job Guard collection.

This means:

- adding work from Terminal while GUI Job Guard is active extends the same session
- adding work in the GUI while CLI-started work is protected extends the same session
- changing Compute Guard / Closed-Lid Eco / Full Awake changes only the protection profile underneath Job Guard
- finishing one item does not release Vigil while another protected item remains
- manual Detach does not kill workloads
- manual Stop Vigil stops protection without terminating user processes

### Start, stop, mode, and status automation

The CLI can control ordinary timed Vigil sessions as well:

```sh
macvigil start --mode compute --duration 30m
macvigil start --mode full-awake --duration infinity
macvigil mode compute
macvigil status
macvigil stop
```

Duration values support common forms such as `30m`, `2h`, `150m`, and `infinity`.

`macvigil status --json` provides a machine-readable local response for scripts.

A normal CLI `start` intentionally uses the same Timer-owned session semantics as starting Vigil from the menu. Job-aware CLI commands use Job Guard ownership.

### Closed-Lid Eco safety remains unchanged

The CLI does not bypass closed-lid requirements.

Closed-Lid Eco still requires the same authorization as the GUI. Before the first CLI-started closed-lid session, the first-use heat and ventilation acknowledgement must already have been accepted in the MacVigil interface.

Mandatory macOS battery, thermal, shutdown, Lock Screen, and other safety behavior remains in control.

### Universal release packaging

CI now builds three universal executables for every release:

- `MacVigil`
- `MacVigilWatchdog`
- `macvigil`

All contain both arm64 and x86_64 slices. The CLI is bundled inside the app and copied to the root of the DMG for convenience.

### Documentation and roadmap

The README now documents CLI installation, command examples, local control behavior, saved workflows, working directories, environment variables, and the single-runtime ownership model.

The roadmap has also been refreshed so already-shipped Job Guard and CLI work no longer appears as future work. The next major development track is reliability and distribution hardening.

### Safety and distribution status

MacVigil remains ad-hoc signed rather than Developer ID signed and notarized.

Closed-lid workloads can generate significant heat. Keep a MacBook on a hard, ventilated surface and never run sustained closed-lid workloads in a bag, sleeve, drawer, or other enclosed space.

Brightness/backlight darkening is not a guarantee that the physical display panel is electrically powered off.

## [0.13.0] - 2026-08-15

### Customizable global hotkeys

Global shortcuts are no longer fixed.

Open **Settings → Hotkeys**, click **Change**, and press the key combination you want for:

- Start / Stop Vigil
- Compute Guard
- Closed-Lid Eco
- Full Awake

MacVigil saves the shortcut locally and re-registers the global hotkey immediately. At least one modifier key is required. Duplicate MacVigil shortcuts are rejected, and registration conflicts with macOS or another app are reported instead of silently failing.

Each shortcut can be reset individually, or all shortcuts can be restored to the defaults.

The menu-bar panel now displays the configured shortcuts rather than hard-coded defaults.

### Workflow-aware Job Guard

Job Guard now protects more kinds of local work inside the same multi-job session.

A single Job Guard session can contain:

- running processes
- manual PIDs
- launched commands
- TCP listening ports

The existing ownership rule remains unchanged: finishing one item never releases Vigil while another protected item is still running. Vigil releases naturally only after the final protected item finishes.

Running and recent items are separated visually, and each running item keeps an explicit **Detach** action. Detaching never terminates the underlying workload.

### TCP port protection

Job Guard can now watch a local TCP listener.

Enter a port such as `3000`, `5173`, `8000`, or `8080`. MacVigil checks for a local listening process with the system `lsof` tool and keeps Vigil active while that port remains in the listening state.

When the listener disappears, that port member finishes. If other protected jobs remain, Vigil continues. If it was the final protected item, Job Guard releases Vigil.

Port watching checks local listener presence only. It does not inspect network traffic.

### Actionable workload detection

Likely developer workloads are still detected locally with heuristic process matching, but suggestions are now actionable as a group.

The Job Guard window includes **Protect Suggested**, which can add the currently detected AI agents, local AI runtimes, builds, containers, dev servers, and transfer processes to the same protected session.

Suggestions are never silently protected. The user still chooses when to add them.

### Project working directories

Commands launched from Job Guard are no longer restricted to the user's home directory.

Choose a project folder before launching a command, return to Home at any time, and MacVigil remembers the selected directory locally. Commands remain non-interactive and run through `/bin/zsh -lc`, with separate output logs for each launched command.

### Job completion notification

When the final Job Guard item finishes naturally, MacVigil posts a local completion notification when notification permission is available, then releases Vigil and restores the user's normal duration preference.

A deliberate **Stop Vigil** or **Detach** remains different and does not terminate the underlying work.

### Richer local Statistics

Statistics now retains up to 200 recent session records and uses native macOS `GroupBox` and system controls instead of custom dashboard glass cards.

The dashboard now includes:

- 7-day, 30-day, and all-history ranges
- protected time
- completed session count
- average and longest session
- daily activity
- protection-mode breakdown
- lifetime-owner breakdown such as Timer and Job Guard
- battery change when available
- peak thermal state
- recent session history
- mode and owner filters
- local CSV export

Existing saved statistics remain readable. The new owner field is optional for older records and defaults to Timer when it was not previously stored.

Statistics remain local. Battery deltas are observational and are not an efficiency benchmark because charging state and workload intensity also affect them.

### Clearer active-session status

The menu-bar panel now tells you why Vigil is active instead of showing only a protection profile.

Examples include:

- `Timer · Compute Guard · 52:14`
- `Job Guard · Port 3000 · listening`
- multi-item Job Guard summaries

This preserves the architectural separation between **session lifetime owner** and **protection profile**.

### Native UI refinement

Settings keeps the System Settings-style native hierarchy introduced in v0.12.4. Statistics now follows that same direction with system grouping and controls, while Liquid Glass remains selective in the menu-bar control layer on macOS 26 and later.

### Runtime ownership unchanged

Live mode changes still change only the underlying protection profile. They do not reset a timer deadline or detach Job Guard.

Job Guard still owns the lifetime of its session until its last protected item finishes naturally. Manual Stop Vigil still stops protection without killing user workloads.

### README

The README now documents customizable hotkeys, TCP port watching, actionable workload suggestions, selectable command working directories, richer Statistics, CSV export, and active-owner status.

### Safety

MacVigil does not weaken macOS Lock Screen, password, thermal, battery, shutdown, or other mandatory system safety behavior.

Closed-lid workloads can generate significant heat. Keep a MacBook on a hard, ventilated surface and never run sustained closed-lid workloads in a bag, sleeve, drawer, or other enclosed space.

Brightness/backlight darkening is not a guarantee that the physical display panel is electrically powered off.

## [0.12.4] - 2026-08-15

### Settings now follows the native macOS hierarchy

This release corrects the Settings design after comparing MacVigil directly with macOS System Settings.

The previous layout applied Liquid Glass to entire panes. That made the sidebar, title area, and content feel like stacked translucent cards rather than a native macOS Settings-style window.

MacVigil now uses a much more system-native structure:

- integrated `NavigationSplitView` sidebar
- native sidebar `List` without a custom rounded glass slab
- native navigation title instead of a separate glass title card
- grouped `Form` content directly on the normal system content surface
- standard macOS buttons for Settings actions, mode selection, and duration presets
- standard sidebar footer for Vigil status instead of a floating glass status card
- no custom full-pane glass wrapper around the detail content
- no decorative “Liquid Glass” badge

On macOS 26 and later, Liquid Glass remains available where the operating system and MacVigil's important controls use it naturally. The menu-bar panel continues to use selective native glass controls. Settings deliberately uses less custom glass so that it feels closer to System Settings.

### Better visual hierarchy

The new Settings structure removes multiple nested rounded surfaces and reduces visual haze. Text, toggles, grouped rows, and section spacing now inherit standard macOS behavior and contrast more directly.

The complete sidebar row remains selectable, and keyboard navigation, focus, hover, switch behavior, and grouped-form layout remain system-driven.

### Duration readability retained

The custom duration control continues to show both forms while adjusting the slider:

- `2 hours 30 minutes`
- `2h 30m`

The menu-bar slider also keeps the human-readable hours/minutes value and accessibility value introduced in v0.12.3.

### Runtime behavior unchanged

This is a presentation and interaction-structure release. It does not change Vigil power behavior or session ownership.

Job Guard still owns its session until the final protected job finishes. Live mode changes preserve ownership and timer continuity. Battery, thermal, closed-lid, authorization, update-safety, and mandatory macOS safety behavior remain unchanged.

### README

The README now describes the System Settings-style hierarchy and explicitly documents why Settings uses less custom glass than the menu-bar controls.

### Safety

MacVigil does not weaken macOS Lock Screen, password, thermal, battery, shutdown, or other mandatory system safety behavior.

Closed-lid workloads can generate significant heat. Keep a MacBook on a hard, ventilated surface and never run sustained closed-lid workloads in a bag, sleeve, drawer, or other enclosed space.

Brightness/backlight darkening is not a guarantee that the physical display panel is electrically powered off.

## [0.12.3] - 2026-08-15

### Liquid Glass Settings

Settings now carries the native macOS 26 Liquid Glass treatment throughout the Settings chrome instead of limiting glass to the menu-bar controls.

On macOS 26 and later, MacVigil now uses Apple's real `glassEffect` for:

- the Settings sidebar surface
- the live Vigil status surface
- the Settings detail header
- the main Settings detail pane
- major Settings actions
- mode and duration controls

The sidebar remains a native macOS `List` and preference content remains grouped `Form` content, so keyboard navigation, focus, selection, switches, sliders, and accessibility continue to use system behavior while the window itself has a consistent Liquid Glass identity.

On macOS 13–15, these surfaces continue to fall back to standard system materials.

### Clearer custom duration

Custom duration is now written in plain hours and minutes while the slider is adjusted.

Examples:

- `45 minutes`
- `1 hour`
- `1 hour 30 minutes`
- `4 hours`
- `11 hours 15 minutes`

Settings also keeps the compact representation such as `2h 30m` underneath the full wording, making longer durations easier to scan precisely.

The menu-bar duration slider now shows the same human-readable wording and exposes that value to accessibility.

### Runtime behavior unchanged

This release does not change Vigil ownership or power behavior. Job Guard still owns its session until the last protected job finishes, live mode changes preserve ownership and timer continuity, and battery/thermal/closed-lid safety behavior remains unchanged.

### README

The README now documents Liquid Glass Settings surfaces and the human-readable custom duration display.

### Safety

MacVigil does not weaken macOS Lock Screen, password, thermal, battery, shutdown, or other mandatory system safety behavior.

Closed-lid workloads can generate significant heat. Keep a MacBook on a hard, ventilated surface and never run sustained closed-lid workloads in a bag, sleeve, drawer, or other enclosed space.

Brightness/backlight darkening is not a guarantee that the physical display panel is electrically powered off.

## [0.12.2] - 2026-08-15

### Native macOS 26 Liquid Glass

MacVigil now uses Apple's actual SwiftUI Liquid Glass APIs on macOS 26 and later instead of imitating the look with custom gradient-and-blur layers.

The everyday menu uses native glass button styles and `glassEffect` for important interactive controls such as Start / Stop Vigil, mode selection, quick duration choices, update actions, and quick destinations.

Content surfaces deliberately use standard system materials rather than turning every card into glass. This follows Apple's Liquid Glass hierarchy: glass is reserved for controls and navigation while content remains visually stable underneath it.

### Native Settings architecture

Settings has been rebuilt around standard macOS components:

- `NavigationSplitView`
- native sidebar `List`
- grouped `Form` sections
- system toggles
- system sliders
- system buttons
- system labels and selection behavior

The hand-built colored glass sidebar has been removed. Sidebar selection, keyboard navigation, row interaction, focus, hover behavior, and spacing now come from macOS itself.

### Better click targets

The native sidebar makes the complete row selectable instead of requiring a click directly on the text.

Settings toggle labels also claim the full available row width, so users do not need to target only the switch or title.

Mode controls, duration controls, Start / Stop, update actions, and quick destinations retain full-surface hit targets.

### System app icon usage

The menu header and About page now render the actual bundled MacVigil application icon instead of recreating a colored symbol in SwiftUI.

### Compatibility

Native Liquid Glass is available on macOS 26 and later.

MacVigil still supports macOS 13 and later. On older macOS releases, the same interface falls back to standard system materials and controls without requiring a separate build.

The GitHub build and release workflows now use the macOS 26 runner/SDK so the native Liquid Glass APIs are compiled into the app while the deployment target remains macOS 13.

### Runtime behavior unchanged

This release is an interface architecture change. Job Guard ownership, live mode switching, timer continuity, battery safety, thermal safety, closed-lid authorization, update safety, and mandatory macOS safety behavior remain unchanged.

### Safety

MacVigil does not weaken macOS Lock Screen, password, thermal, battery, shutdown, or other mandatory system safety behavior.

Closed-lid workloads can generate significant heat. Keep a MacBook on a hard, ventilated surface and never run sustained closed-lid workloads in a bag, sleeve, drawer, or other enclosed space.

Brightness/backlight darkening is not a guarantee that the physical display panel is electrically powered off.

## [0.12.1] - 2026-08-15

### Real liquid-glass visual pass

The menu-bar panel and primary windows now use a deeper layered glass treatment instead of flat dark translucent panels.

The new presentation combines native macOS material with subtle blue/violet depth fields, highlighted glass edges, floating rounded surfaces, softer shadows, and clearer selected states. The same visual system is used across the main panel, Settings, Job Guard, Statistics, and the update confirmation window.

### Full-surface click targets

MacVigil no longer requires users to aim directly at label text for common controls.

Full visible surfaces are now the hit target for:

- Settings sidebar tabs
- mode cards
- quick duration pills
- main Start / Stop Vigil control
- update surfaces
- Job Guard / Statistics / Settings navigation cards
- Settings toggle rows
- protection option rows
- update actions in Settings
- Job Guard process Add rows
- command actions
- individual Log and Detach buttons

Hover, pressed, selected, and active states now apply to the whole interactive surface.

### Easier Settings navigation

The Settings sidebar now uses full-width glass navigation rows with stronger selected states and hover feedback. Toggle and protection rows are also full-surface controls: clicking anywhere on the row changes the setting while the switch remains the state indicator.

### Job Guard interaction polish

Job Guard now uses the same liquid-glass design language as the rest of MacVigil.

Running/suggested process rows use the full row as the Add target. Individual Detach remains a dedicated explicit control so a destructive detach cannot happen accidentally from a general row click. Detach All, command launching, manual PID entry, Stop Vigil, and other actions use larger hit targets.

The multi-job ownership model is unchanged: Vigil releases naturally only after the last protected job finishes.

### Update interaction polish

Update actions are presented as large glass surfaces. When Vigil is active, the separate update window keeps Stop Vigil & Update as an explicit full-width action before installation.

Automatic updates still respect active Vigil sessions and live mode reconfiguration.

### README

The README now documents the layered Liquid Glass interface, the full-surface interaction rule, Job Guard interaction behavior, Settings navigation, Statistics, hotkeys, and update behavior.

### Safety and compatibility

This release does not weaken macOS Lock Screen, password, thermal, battery, shutdown, or other mandatory system safety behavior.

Closed-lid workloads can generate significant heat. Keep a MacBook on a hard, ventilated surface and never run sustained closed-lid workloads in a bag, sleeve, drawer, or other enclosed space.

Brightness/backlight darkening is not a guarantee that the physical display panel is electrically powered off.

## [0.12.0] - 2026-08-15

### Easier everyday UI

The menu-bar panel is now organized around one obvious primary action: **Start Vigil** when idle and **Stop Vigil** when protection is active.

The everyday panel keeps only the controls that need to be fast:

- Start / Stop Vigil
- Compute Guard, Closed-Lid Eco, and Full Awake
- quick duration buttons
- custom duration slider
- battery reserve slider
- Job Guard
- Statistics
- Settings

Advanced protection switches remain in Settings instead of competing with the main workflow. Status text is shorter, selected modes remain visually clear, and the most important controls use larger hit targets.

### Statistics dashboard

MacVigil now includes a dedicated **Statistics** window and a Statistics section in Settings.

The dashboard summarizes retained local Vigil history, including:

- total recent protected time
- completed session count
- average session duration
- longest session
- a last-seven-days activity view
- protection-mode usage
- current battery and thermal state
- recent sessions with duration, recorded battery change when available, and peak thermal state

The dashboard is local. MacVigil does not upload statistics telemetry.

Battery-change values are observational rather than an efficiency benchmark because charging state and workload intensity also affect them.

### Global hotkeys

Global shortcuts now work while the MacVigil menu is closed:

- **⌥⌘V** — Start / Stop Vigil
- **⌥⌘1** — Compute Guard
- **⌥⌘2** — Closed-Lid Eco
- **⌥⌘3** — Full Awake

Global hotkeys are enabled by default and can be disabled from **Settings → Hotkeys**.

Mode hotkeys preserve the current session owner. If Job Guard is protecting work, switching modes changes only the underlying protection profile and does not detach the protected jobs.

Closed-lid safety and authorization rules still apply to hotkey actions.

### Settings improvements

Settings now includes dedicated **Statistics** and **Hotkeys** sections alongside General, Vigil, Job Guard, Updates, Power & Safety, Appearance, and About.

General also exposes the global-hotkey master switch so the most common preferences are easier to find.

### README and release workflow

The README now documents the simplified everyday controls, Statistics dashboard, privacy behavior, and global hotkeys.

The existing release workflow continues to synchronize these curated notes into `CHANGELOG.md` before publishing.

## [0.11.0] - 2026-08-15

### Liquid Glass control panel

MacVigil's menu-bar interface has been redesigned around a native translucent glass presentation with layered cards, clearer selected states, larger hit targets, and a simpler everyday control flow.

The main panel now puts the most-used controls together: Vigil on/off, mode selection, duration, battery reserve, Job Guard status, Stop Vigil, and Settings.

### Faster duration control

The main panel now includes quick duration choices for **15m, 30m, 1h, 2h, 4h, and Infinity** plus a slider for custom durations from 5 minutes to 12 hours.

Changing protection mode while a timed Vigil session is active continues to preserve the existing countdown. When Job Guard owns the lifetime, the duration controls do not silently replace that ownership.

### Battery reserve slider

Battery reserve is now adjustable with a dedicated 5–30% slider in both the main control panel and Settings.

The configured reserve continues to feed MacVigil's existing battery safety behavior.

### Separate Settings window

Advanced controls have moved into a dedicated Settings window with sections for:

- General
- Vigil
- Job Guard
- Updates
- Power & Safety
- Appearance
- About

This keeps the menu-bar panel focused on fast interaction while leaving every major protection option independently configurable.

### Job Guard integration

The glass control panel shows Job Guard state and the number of currently protected jobs. Job Guard still owns one multi-job Vigil session and releases only after the final protected job finishes naturally.

Mode changes continue to modify the protection profile underneath Job Guard without discarding the protected jobs.

### New app icon

MacVigil now ships with a generated macOS app icon using the new blue-violet guardian/shield identity with an activity pulse and energy badge. The universal build and release workflows generate and package the `.icns` resource automatically.

### README and release workflow

The README now documents the Liquid Glass interface, duration and battery sliders, dedicated Settings window, and current Job Guard ownership behavior.

Curated release notes remain the source for the GitHub Release body and are synchronized into `CHANGELOG.md` by the release workflow.

## [0.10.1] - 2026-08-15

### Visible per-job detach controls

Protected Job Guard rows now use explicit text **Detach** buttons instead of relying on a small symbol-only control.

Each running job can be detached independently. Detaching one job leaves the other protected jobs attached, does not terminate the underlying process or command, and does not release Vigil while other protected jobs are still running.

**Detach All** remains available for intentionally leaving the whole Job Guard collection while keeping the actual workloads running.

### Reliable Stop Vigil controls

The critical **Stop Vigil** action is now a large full-width native button with its own layout space instead of being placed in an overlay above the menu-bar UI.

The same Stop Vigil control is also available inside the normal Job Guard window. This gives Job Guard users a stable non-transient window for stopping protection without having to target the small Vigil switch in the menu-bar panel.

Stopping Vigil restores normal macOS sleep behavior and detaches Job Guard, but does not terminate protected jobs.

### Reliable update controls

When an update is available, the main critical-action area uses a large full-width **Update to <version>** button.

If Vigil is active, that action opens the standalone **Update MacVigil** window, where **Stop Vigil & Update** has a larger full-width hit target. This avoids relying on a confirmation attached to the transient menu-bar popover.

The same update action is surfaced inside the normal Job Guard window when an update is available.

### Explicit process actions

Job Guard process lists now use visible **Add** / **Protected** buttons instead of making the entire process row responsible for the action. This makes selecting workloads clearer and reduces accidental or missed clicks.

## [0.10.0] - 2026-08-15

### Multi-job Job Guard

Job Guard can now protect **multiple processes and commands in one Vigil session**.

Add another running process, PID, or shell command while Job Guard is already active. Every protected job is tracked independently with its own PID, runtime state, elapsed time, command log when applicable, and exit result.

Vigil remains active while **at least one protected job is still running**. Finishing one job no longer releases protection if another selected job still needs it. When the final protected job finishes naturally, Job Guard releases Vigil and restores the user's normal duration preference.

### Session ownership

MacVigil now explicitly separates **session lifetime ownership** from the active protection mode.

A normal timer owns a normal Vigil session. Job Guard owns a job-aware session. Changing Compute Guard, Closed-Lid Eco, Full Awake, or individual protection switches changes the power-protection profile underneath the existing owner instead of replacing the session.

While Job Guard owns the lifetime, changing the normal duration cannot silently replace the job-aware lifetime with a timer.

### Per-job control

- detach one protected job without affecting the others
- detach all jobs without terminating them and without forcibly stopping Vigil
- open the captured log for each command independently
- see running, finished, and detached jobs together while the Job Guard session is active
- prevent the same PID from being added twice
- keep adding jobs from smart suggestions, the full process picker, manual PID entry, or command runner

Manual **Stop Vigil** remains an explicit override: it restores normal macOS sleep behavior and detaches Job Guard, but it never terminates the user's running processes or commands.

### Interaction cleanup

The Job Guard window no longer hides the process picker and command runner while a job is active. They stay available so more work can be added to the same protected session.

The compact menu-bar Job Guard row no longer uses a parent row tap gesture that could compete with its buttons; Configure/Manage, logs, detach, and options keep their own explicit hit targets.

### Reliability

If the final protected job finishes during a live mode handoff, Job Guard waits for that internal handoff to finish before releasing Vigil. Automatic updates continue to treat live handoffs as active protection and do not start in the middle of a reconfiguration.

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
