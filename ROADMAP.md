# MacVigil Roadmap

MacVigil is becoming an **energy-aware local runtime guard for macOS**: protect the work that matters, avoid keeping unnecessary components awake, and release protection when the work is done.

Legend: ✅ shipped · 🧪 experimental · 🚧 next · 💡 later

## Product principles

1. **Protect the job, not every component.**
2. **End when the work ends.** A 40-minute job should not need a guessed four-hour timer.
3. **Safety wins.** Battery, thermal, shutdown, and mandatory macOS protections remain in control.
4. **Restore state cleanly.** MacVigil should leave normal macOS behavior behind when Vigil ends.
5. **Measure before claiming.** Power-efficiency comparisons require repeatable measurements.
6. **Explain the state.** Users should always be able to see what is protected and why.
7. **One runtime, many control surfaces.** GUI, hotkeys, and CLI must operate the same Vigil / Job Guard state rather than create competing protection sessions.

## Shipped foundation

- ✅ native SwiftUI menu-bar app
- ✅ native macOS Settings-style hierarchy
- ✅ selective native Liquid Glass controls on macOS 26+
- ✅ Compute Guard, Closed-Lid Eco, and Full Awake
- ✅ fixed, custom, and indefinite sessions
- ✅ human-readable custom duration in hours and minutes
- ✅ live mode and protection changes without resetting the active timer
- ✅ independent system, idle, display, lid, battery, and thermal controls
- ✅ closed-lid crash recovery watchdog
- ✅ built-in GitHub release checking and verified update flow
- ✅ background update notifications and optional automatic installation
- ✅ Launch at Login
- ✅ customizable global hotkeys
- ✅ curated GitHub release notes and automated changelog synchronization
- ✅ local Statistics with filters and CSV export
- ✅ universal Apple Silicon + Intel builds
- ✅ diagnostics for runtime, lid, display, battery, thermal, and sleep state
- 🧪 experimental closed-lid kernel guard and built-in display darkening

## Job Guard

- ✅ choose running apps or processes from a searchable native picker
- ✅ show app icon, PID, and CPU activity when available
- ✅ surface likely long-running workloads as opt-in suggestions
- ✅ Protect Suggested group action
- ✅ categorize detected AI, local-model, build, container, server, and transfer workloads
- ✅ protect multiple processes, commands, and ports in one Job Guard collection
- ✅ release Vigil only after the final protected item finishes naturally
- ✅ explicit single-item and Detach All controls that never kill workloads
- ✅ run non-interactive shell commands under Vigil
- ✅ selectable working directory for launched commands
- ✅ capture separate command logs
- ✅ remember recent commands
- ✅ local completion notification when the final protected item finishes
- ✅ watch TCP listening ports with local `lsof` checks
- 💡 combine multiple process conditions with explicit AND / OR rules
- 💡 dedicated Docker container and Compose lifecycle triggers
- 💡 smarter parent/child process grouping

## CLI and developer automation

- ✅ universal `macvigil` command-line client bundled with the app
- ✅ GUI and CLI share one local MacVigil runtime
- ✅ `macvigil status` and JSON status output
- ✅ `macvigil start`, `stop`, and `mode`
- ✅ `macvigil run -- <command>` with terminal stdin/stdout/stderr and child exit status
- ✅ `macvigil run --cwd ... --env KEY=VALUE -- <command>`
- ✅ `macvigil watch-pid 43127 44102`
- ✅ `macvigil watch-port 3000 5173`
- ✅ `macvigil protect-suggested`
- ✅ saved local workflows combining ports, commands, cwd, environment, and detected workloads
- ✅ Settings toolbar install/remove for `/usr/local/bin/macvigil`
- ✅ app auto-launch attempt when the CLI needs the MacVigil runtime
- 🚧 shell completion
- 🚧 Homebrew Cask
- 💡 Shortcuts support
- 💡 URL scheme / structured local automation endpoint
- 💡 editor and Raycast integrations

## AI and local-agent workflows

AI is a first-class use case, not a hard-coded dependency.

- ✅ opt-in detection of common local AI runtimes and agent processes
- ✅ identify likely AI/build/server workloads from running processes
- ✅ add detected workloads to an existing Job Guard collection
- 🚧 Agent Session saved-workflow template
- 🚧 Local Model Server saved-workflow template
- 🚧 smarter grouping of parent/child agent processes
- 💡 repository indexing / embedding preset
- 💡 agent completion integration

## Statistics

- ✅ retain up to 200 local session records
- ✅ 7-day, 30-day, and all-history ranges
- ✅ protected time, session count, average, and longest session
- ✅ mode and lifetime-owner breakdown
- ✅ mode / owner filters
- ✅ battery delta and peak thermal state when available
- ✅ local CSV export
- 🚧 record richer Job Guard member metadata for process / command / port breakdowns
- 💡 JSON export
- 💡 compare saved workflows over time

## Power safety

- ✅ battery reserve cutoff for closed-lid operation
- ✅ critical thermal cutoff
- ✅ prominent serious/critical thermal-pressure warning state
- ✅ estimated time to battery reserve when macOS provides a usable discharge estimate
- ✅ optional closed-lid protection only on external power
- ✅ recent session duration, battery delta, and peak thermal statistics
- 💡 session energy budget
- 💡 configurable serious-thermal action beyond warning

## Power measurements

MacVigil should earn efficiency claims with data.

- ✅ repeatable local benchmark data-collection harness
- 🚧 collect baseline normal macOS runs
- 🚧 benchmark `caffeinate`
- 🚧 benchmark equivalent Amphetamine configurations
- 🚧 benchmark Compute Guard and Closed-Lid Eco
- 🚧 publish battery delta, elapsed time, temperature, and available system-power measurements
- 💡 estimate energy avoided when Job Guard ends earlier than a timer would have

See [docs/POWER-BENCHMARKS.md](docs/POWER-BENCHMARKS.md).

## v0.15 — reliability and distribution

The next major release track is deliberately less feature-heavy and more about trustworthiness:

- 🚧 deliberate crash-recovery testing
- 🚧 harden app-termination, lid/wake, update, Job Guard, and CLI race handling
- 🚧 validate multiple Apple Silicon generations
- 🚧 validate Intel hardware
- 🚧 maintain a Mac model × macOS compatibility matrix
- 🚧 Developer ID signing
- 🚧 Apple notarization
- 🚧 updater validation against signed/notarized artifacts
- 🚧 CLI installation/update validation across app upgrades
- 🚧 Homebrew Cask after signed/notarized distribution is ready

## 1.0 criteria

MacVigil should not call itself 1.0 until:

- open-lid protection is broadly validated
- closed-lid compatibility and unsupported cases are documented
- crash recovery is deliberately tested
- battery and thermal safeguards are reliable
- GUI, hotkeys, Job Guard, and CLI lifetime ownership are deliberately stress-tested
- power benchmarks are reproducible
- the app is Developer ID signed and notarized
- installation, updating, CLI installation, and authorization cleanup are tested and documented

## Not goals

MacVigil will not:

- defeat mandatory thermal or critical-battery safety behavior
- silently modify macOS password or Lock Screen policy
- claim private or undocumented APIs are stable Apple contracts
- claim lower power usage than another product without reproducible measurements
- expose a network control server merely to support the local CLI
- keep the machine awake indefinitely after a known protected job has finished
