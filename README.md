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

## Fine-grained control

Presets are only a starting point. Before starting a Vigil session, you can independently choose whether MacVigil should:

- prevent system sleep
- prevent idle sleep
- prevent display sleep
- protect closed-lid operation
- darken the built-in display when the lid closes
- stop at a battery reserve
- release protection under critical thermal pressure

Sessions can run for a fixed duration, a custom duration, or indefinitely.

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

MacVigil works locally. No account or cloud service is required to keep your Mac awake.

## Project status

MacVigil is currently **pre-1.0** and under active testing. The focus is reliable runtime protection, closed-lid compatibility, energy-aware behavior, safe recovery, and a polished native macOS experience.

See the [roadmap](ROADMAP.md) for what is coming next.

## Contributing

Issues, compatibility reports, testing results, and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT. See [LICENSE](LICENSE).

---

<div align="center">

**MacVigil** · Keep your work running. Not your screen.

</div>
