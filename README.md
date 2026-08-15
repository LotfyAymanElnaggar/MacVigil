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

Modern Macs often keep doing useful work long after you stop touching the keyboard: an AI coding agent may still be editing files, a local model may be generating, a build may be compiling, or a transfer may still be running.

MacVigil keeps that work protected while giving you control over what stays awake.

**Keep the work running. Not everything else.**

## Choose how your Mac stays awake

### Compute Guard
Keep the Mac available for long-running work while allowing the display to behave normally.

Best for AI agents, local models, builds, tests, servers, downloads, and remote access.

### Closed-Lid Eco
Keep work running with the MacBook lid closed while darkening the built-in display and applying battery and thermal safeguards.

MacVigil can keep the display logically awake while the lid is dark, helping avoid Lock Screen behavior that can be triggered by display sleep. It does **not** change or weaken your macOS password or Lock Screen settings.

### Full Awake
Keep both the Mac and display awake.

Best for presentations, dashboards, demos, monitoring, and kiosk-style use.

## Job Guard

A timer is useful when you know how long work will take. **Job Guard** is for when you do not.

Choose one or more running apps/processes from the built-in picker, enter PIDs manually, or launch multiple commands directly with Vigil. MacVigil keeps one Job Guard session active while any selected job is still running and releases protection only after the **last protected job** finishes.

Each job is tracked independently. You can add more work while Job Guard is already active, open individual command logs, or detach one job without affecting the others. Detaching never terminates the underlying process.

Job Guard can also suggest likely long-running local workloads such as AI runtimes, builds, containers, servers, and transfers. Suggestions are local and opt-in.

That means several overlapping builds, agents, and local services do not need one guessed awake timer.

## Power Intelligence

MacVigil shows current battery and thermal state, estimates time to your configured battery reserve when macOS provides a usable discharge estimate, and keeps lightweight statistics for recent Vigil sessions.

For sustained closed-lid workloads, you can optionally require external power so MacVigil releases closed-lid protection if the Mac switches to battery.

## Fine-grained control

Presets are only a starting point. Protection options and modes can be changed while Vigil is running, including system sleep, idle sleep, display sleep, closed-lid protection, display darkening, battery reserve, and thermal safety.

Sessions can run for a fixed duration, a custom duration, indefinitely, or under Job Guard until every selected protected job has finished.

## Built for local work

MacVigil is useful for:

- AI coding agents and autonomous development tasks
- Ollama, LM Studio, MLX, llama.cpp, and other local AI runtimes
- Xcode, Swift, Rust, Node, Python, Android, and container builds
- Docker and local development servers
- tests, migrations, indexing, embeddings, and data processing
- SSH, Tailscale, Screen Sharing, and remote development
- large downloads, uploads, backups, and model transfers
- video, audio, 3D, CAD, and batch rendering
- notebooks, simulations, and research workloads

## Install

1. Download the newest DMG from [Releases](https://github.com/LotfyAymanElnaggar/MacVigil/releases).
2. Drag **MacVigil** into **Applications**.
3. Launch it from Applications.
4. If you want closed-lid protection, install the optional authorization from inside MacVigil.

MacVigil can check GitHub for new releases in the background, notify you when one is ready, and optionally install verified updates automatically when Vigil is idle. Launch at Login is optional.

MacVigil is currently distributed with ad-hoc signing rather than Apple notarization. On first launch, macOS may require **Right-click → Open** or approval from **System Settings → Privacy & Security**.

## Safety

Closed-lid workloads can generate significant heat. Do not run a heavily loaded MacBook inside a bag, sleeve, drawer, or other poorly ventilated space.

MacVigil keeps battery and thermal safeguards available and does not attempt to override mandatory macOS safety shutdown behavior.

## Requirements

- macOS 13 or later
- Apple Silicon or Intel Mac
- administrator approval only for optional closed-lid protection

Closed-lid behavior is still being tested across Mac models and macOS versions. See the [compatibility guide](docs/COMPATIBILITY.md) for current results.

## Privacy

MacVigil works locally. No account or cloud service is required to keep your Mac awake. Update checks contact GitHub only when update checking is enabled.

## Project status

MacVigil is currently **pre-1.0** and under active testing. The focus is reliable runtime protection, job-aware sessions, closed-lid compatibility, energy-aware behavior, safe recovery, and a polished native macOS experience.

See the [roadmap](ROADMAP.md) for what is coming next.

## Contributing

Issues, compatibility reports, testing results, and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT. See [LICENSE](LICENSE).

---

<div align="center">

**MacVigil** · Keep your work running. Not your screen.

</div>
