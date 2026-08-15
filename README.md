<div align="center">

# MacVigil

### Local work, uninterrupted.

Keep AI agents, local models, builds, servers, transfers, renders, and other long-running work alive when you step away from your Mac.

[![Release](https://img.shields.io/github/v/release/LotfyAymanElnaggar/MacVigil)](https://github.com/LotfyAymanElnaggar/MacVigil/releases)
[![Build](https://github.com/LotfyAymanElnaggar/MacVigil/actions/workflows/build.yml/badge.svg)](https://github.com/LotfyAymanElnaggar/MacVigil/actions/workflows/build.yml)
[![macOS](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)](#requirements)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

[Download](https://github.com/LotfyAymanElnaggar/MacVigil/releases) · [Roadmap](ROADMAP.md) · [Docs](docs/README.md) · [Changelog](CHANGELOG.md)

</div>

---

## Why MacVigil?

A Mac can still be doing important work after you stop touching the keyboard: an AI coding agent may be editing files, a local model may be generating, a build may be compiling, a local server may be listening, or a transfer may still be running.

MacVigil keeps that work protected while letting you choose exactly what stays awake.

**Keep the work running. Not everything else.**

## Native macOS interface

On **macOS 26 and later**, MacVigil uses Apple's SwiftUI Liquid Glass APIs selectively for important menu controls while Settings follows a native macOS Settings-style hierarchy. It does not imitate Liquid Glass with custom blue/purple gradients, and it does not place giant glass surfaces behind the entire Settings sidebar or content pane.

The design uses native system behavior throughout:

- native `NavigationSplitView` + integrated sidebar `List` for Settings
- native grouped `Form` sections on the stable Settings content surface
- system toggles, sliders, labels, buttons, navigation titles, focus, and selection behavior
- native Liquid Glass for important menu controls such as mode cards, duration choices, Start/Stop, update actions, and quick destinations on macOS 26+
- native `GroupBox` and system controls in Statistics instead of custom glass dashboard cards
- no custom full-pane glass slab around the Settings sidebar, title, or detail content
- compatibility with standard macOS appearance on macOS 13–15

The interaction rule remains simple: **the whole visible control is clickable**. You do not need to aim directly at its label text.

The menu-bar panel keeps the everyday workflow compact and now tells you **why** Vigil is active:

- **Timer · Compute Guard · 52:14** for a normal timed session
- **Job Guard · Port 3000 · listening** for a protected local server
- **Job Guard · 3 jobs protected** for multi-workload sessions
- **CLI · Compute Guard** for future command-line-owned sessions

Your configured global shortcut is shown in the panel instead of a hard-coded key combination.

## Settings

Settings is built to feel structurally close to macOS System Settings rather than like a stack of custom glass cards. The sidebar is integrated into the `NavigationSplitView`, the selected section title is the native navigation title, and grouped `Form` content sits directly on the normal system content surface.

There is deliberately **less glass in Settings**. Liquid Glass is allowed to come from the operating system where appropriate instead of wrapping the sidebar, title, and complete detail pane in separate rounded glass containers. The bottom Vigil status is integrated into the sidebar with a standard bar-style footer rather than a floating glass card.

Settings has dedicated sections for:

- **General** — launch at login, mode, duration, battery reserve
- **Vigil** — every major protection behavior independently controllable
- **Job Guard** — multi-job session ownership and management
- **Statistics** — local session history and filters
- **Hotkeys** — customize global shortcuts
- **Updates** — background checks and installation preferences
- **Power & Safety** — battery, thermal, authorization, and external-power policy
- **Appearance** — native system appearance and Liquid Glass availability
- **About** — version and project information

## Choose how your Mac stays awake

### Compute Guard

Keep the Mac available for long-running work while allowing the display to behave normally. Best for AI agents, local models, builds, tests, servers, downloads, and remote access.

### Closed-Lid Eco

Keep work running with the MacBook lid closed while darkening the built-in display and applying battery and thermal safeguards.

MacVigil keeps display sleep logically blocked while the lid is dark so the protected workload is not dependent on ordinary display-sleep behavior. It does **not** change or weaken your macOS password or Lock Screen settings.

### Full Awake

Keep both the Mac and display awake. Best for presentations, dashboards, demos, monitoring, and kiosk-style use.

Mode changes can be applied while Vigil is active without resetting an existing timer or discarding a Job Guard-owned session.

## Duration and battery reserve

Choose a quick duration or tune it with the duration slider. The custom duration is shown both compactly and in plain language — for example **`2h 30m`** and **`2 hours 30 minutes`** — so long durations are easier to read while adjusting the slider.

Timed sessions can be intentionally changed while active; simply switching protection mode preserves the existing deadline.

Job Guard is different: while Job Guard owns the session lifetime, ordinary duration controls cannot replace that ownership.

The battery reserve slider configures the cutoff used by battery safety. Mandatory macOS battery and thermal protections always remain in control.

## Job Guard

A timer is useful when you know how long work will take. **Job Guard** is for when you do not.

One Job Guard session can protect several kinds of work at the same time:

- running apps and processes
- manually entered PIDs
- non-interactive shell commands
- **TCP listening ports** for local servers

MacVigil keeps one Job Guard session active while any protected item is still running and releases protection only after the **last protected item** finishes naturally.

### Port watching

Enter a TCP port such as **3000**, **5173**, **8000**, or **8080**. MacVigil verifies that a local listener exists and keeps Vigil active while that TCP port remains in the listening state. Port checking is local and uses the system `lsof` tool; it is not network traffic inspection.

### Actionable workload detection

MacVigil locally recognizes likely long-running developer workloads such as AI agents, local AI runtimes, builds, containers, dev servers, and transfers. Suggestions are heuristic and are never silently protected.

You can protect one suggestion at a time or choose **Protect Suggested** to add the currently detected suggestions to the same Job Guard session.

### Commands and project folders

Commands still run non-interactively through `/bin/zsh -lc`, but you can now choose the project folder they run from instead of being limited to your home directory. Each launched command keeps its own log.

When the final protected item finishes naturally, Job Guard releases Vigil and posts a local completion notification when notification permission is available. Detaching one or all items never terminates the underlying workload.

## Statistics

The Statistics dashboard summarizes Vigil activity locally on your Mac and retains up to **200 recent session records**.

You can view and filter:

- **7 Days**, **30 Days**, or **All** retained history
- protected time, session count, average session, and longest session
- activity by day
- protection-mode usage
- session owner: **Timer**, **Job Guard**, or CLI-owned sessions when available
- battery change when recorded
- peak thermal state
- recent session history

History can be filtered by mode and owner and exported to a local **CSV** file. MacVigil does not upload statistics telemetry. Battery changes are observational rather than an efficiency benchmark because charging state and workload intensity also affect them.

## Customizable global hotkeys

Global hotkeys work without opening the MacVigil menu first and can be disabled or customized from **Settings → Hotkeys**.

Defaults are:

| Action | Default shortcut |
| --- | --- |
| Start / Stop Vigil | **⌥⌘V** |
| Compute Guard | **⌥⌘1** |
| Closed-Lid Eco | **⌥⌘2** |
| Full Awake | **⌥⌘3** |

Click **Change**, press the new combination, and MacVigil saves and re-registers it immediately. At least one modifier key is required. Duplicate MacVigil shortcuts are rejected, system registration conflicts are reported, and each shortcut — or all shortcuts — can be reset to its default.

Mode hotkeys change only the protection profile underneath the current session, so they do not detach Job Guard or replace its lifetime ownership. Closed-lid authorization and safety rules still apply.

## Updates

MacVigil can check GitHub for releases in the background, notify you when one is available, and optionally install verified updates when Vigil is inactive.

If Vigil is active, MacVigil presents a separate update confirmation window before stopping protection and installing the update.

## Built for local work

MacVigil is useful for AI coding agents, Ollama/LM Studio/MLX/llama.cpp, Xcode and other builds, tests, containers, local development servers, migrations, indexing, remote development, transfers, backups, renders, notebooks, simulations, and other long-running local workloads.

## Install

1. Download the newest DMG from [Releases](https://github.com/LotfyAymanElnaggar/MacVigil/releases).
2. Drag **MacVigil** into **Applications**.
3. Launch it from Applications.
4. For optional closed-lid protection, install authorization from **Settings → Power & Safety**.

MacVigil is currently distributed with ad-hoc signing rather than Apple Developer ID notarization. On first launch, macOS may require **Right-click → Open** or approval in **System Settings → Privacy & Security**.

## Safety

Closed-lid workloads can generate significant heat. Do not run a heavily loaded MacBook inside a bag, sleeve, drawer, or other poorly ventilated space. Use a hard, ventilated surface.

MacVigil keeps battery and thermal safeguards available and does not attempt to override mandatory macOS thermal, critical-battery, shutdown, or other safety behavior.

Brightness/backlight control should not be interpreted as a guarantee that the physical display panel is electrically powered off.

## Requirements

- macOS 13 or later
- Apple Silicon or Intel Mac
- macOS 26 or later for native system Liquid Glass effects
- administrator approval only for optional closed-lid protection

Closed-lid behavior is still being tested across Mac models and macOS versions. See the [compatibility guide](docs/COMPATIBILITY.md) for current results.

## Privacy

MacVigil works locally. No account or cloud service is required to keep your Mac awake. Job detection, port checks, session statistics, and CSV export remain local. Update checks contact GitHub only when update checking is enabled.

## Project status

MacVigil is currently **pre-1.0** and under active testing. The focus is reliable runtime protection, job-aware sessions, closed-lid compatibility, energy-aware behavior, safe recovery, and a polished native macOS experience.

The standalone `macvigil` CLI is still future work; the GUI session-ownership model is being kept ready for that control surface.

See the [roadmap](ROADMAP.md) for upcoming work.

## Contributing

Issues, compatibility reports, testing results, and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT. See [LICENSE](LICENSE).

---

<div align="center">

**MacVigil** · Keep your work running. Not your screen.

</div>
