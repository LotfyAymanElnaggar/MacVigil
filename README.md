<div align="center">

# MacVigil

### Local work, uninterrupted.

**Energy-aware runtime protection for macOS. Keep AI agents, local models, builds, dev servers, renders, transfers, and long-running jobs alive without keeping everything else awake.**

[![macOS](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-native-orange?logo=swift)](#architecture)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

[Why MacVigil](#why-macvigil) · [Power philosophy](#power-first-by-design) · [Roadmap](ROADMAP.md) · [Docs](docs/README.md)

</div>

---

## Why MacVigil

Your Mac can be more than an interactive desktop. It can run a coding agent, local LLM, Docker stack, build, test suite, render, transfer, notebook, remote-development session, or temporary server.

Those jobs should not fail just because you stopped touching the keyboard.

MacVigil is designed around a simple idea:

> **Protect the work. Do not waste power keeping components awake that the work does not need.**

That makes MacVigil different from treating “stay awake” as one global switch. Compute, display, lid behavior, battery safety, and eventually the lifetime of the actual job are separate concerns.

## Power-first by design

MacVigil is being built around three runtime profiles:

| Profile | System | Built-in display | Best for |
|---|---|---|---|
| **Compute Guard** | Protected | May sleep normally | AI agents, builds, servers, downloads |
| **Closed-Lid Eco** | Protected | Darkened when possible | headless MacBook workloads |
| **Full Awake** | Protected | Kept awake | presentations, dashboards, demos |

The goal is not to claim “zero display power” without evidence. Brightness `0`, display sleep, panel power state, GPU activity, and system sleep are different things. MacVigil will publish repeatable measurements before making comparative energy claims.

See [Power Efficiency](docs/POWER-EFFICIENCY.md) and [Power Benchmarks](docs/POWER-BENCHMARKS.md).

## Built for modern local work

Typical use cases include:

- AI coding agents implementing, testing, reviewing, or refactoring a project
- Ollama, LM Studio, MLX, llama.cpp, and other local-model runtimes
- Xcode, Swift, Rust, C/C++, Node, Python, Android, and container builds
- Docker / Docker Compose and local development servers
- long-running tests, migrations, indexing, embeddings, and data processing
- SSH, Tailscale, Screen Sharing, and remote-development access
- large downloads, uploads, backups, model files, and repository clones
- video, audio, photography, 3D, CAD, and batch renders
- Jupyter, MATLAB, R, simulations, and research workloads

Read the full [use-case guide](docs/USE-CASES.md).

## Current project status

MacVigil is a **fresh production-oriented codebase** built from lessons learned in the earlier KeepAwakeMac prototype. The old repository remains separate as development history and compatibility research.

The initial MacVigil milestone focuses on:

- native menu-bar UX
- timed and indefinite runtime protection
- independent display policy
- experimental closed-lid runtime protection
- low-battery safety
- crash-safe restoration
- transparent diagnostics
- a clean foundation for job-aware and energy-aware automation

Closed-lid behavior depends on macOS implementation details and should be treated as experimental until the compatibility matrix is broad enough.

## Product direction

The long-term UX is not:

> “Keep my Mac awake for four hours.”

It is:

> **“Protect this job until it is done.”**

Planned examples:

```bash
macvigil run -- npm test
macvigil watch-pid 43127
macvigil watch-port 3000
```

When the protected process/server finishes, MacVigil can release its power assertions immediately instead of leaving the machine awake for the remainder of a guessed timer.

See the complete [roadmap](ROADMAP.md).

## Safety

Closed-lid compute creates real heat. Never run an actively loaded MacBook in a bag, sleeve, drawer, or other poorly ventilated space.

MacVigil must never try to defeat mandatory safety behavior such as thermal emergency, critical-battery handling, shutdown, or other system-protection events.

The project also does **not** silently weaken macOS password or Lock Screen security settings.

## Requirements

- macOS 13 or later
- Apple Silicon or Intel Mac
- administrator approval only for the narrowly scoped closed-lid `pmset disablesleep` authorization

## Architecture

MacVigil is native Swift / SwiftUI and intentionally keeps power-management responsibilities separated:

```text
MacVigil UI
    │
    ▼
VigilManager
    ├── Power assertions
    ├── System sleep veto
    ├── Root-domain lid guard
    ├── Display/backlight controller
    ├── Battery + thermal safety
    └── Crash watchdog
```

See [Architecture](docs/ARCHITECTURE.md) for implementation details and compatibility caveats.

## Privacy

MacVigil is intended to work locally. It does not need an account or cloud service to keep a runtime alive.

## Contributing

Power-management bugs can leave a machine in an unexpected system-wide state, so changes to lid, privilege, watchdog, and cleanup behavior require extra care. Read [CONTRIBUTING.md](CONTRIBUTING.md) before submitting changes.

## License

MIT. See [LICENSE](LICENSE).

---

<div align="center">

**MacVigil** · Keep your work running. Not your screen.

</div>
