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

## Shipped foundation

- ✅ native SwiftUI menu-bar app
- ✅ Compute Guard, Closed-Lid Eco, and Full Awake
- ✅ fixed, custom, and indefinite sessions
- ✅ live mode and protection changes without resetting the active timer
- ✅ independent system, idle, display, lid, battery, and thermal controls
- ✅ closed-lid crash recovery watchdog
- ✅ built-in GitHub release checking and verified update flow
- ✅ universal Apple Silicon + Intel builds
- ✅ diagnostics for runtime, lid, display, battery, thermal, and sleep state
- 🧪 experimental closed-lid kernel guard and built-in display darkening

## Job Guard

The first job-aware workflow shipped in v0.6.0.

- ✅ watch an existing PID
- ✅ release Vigil automatically when the watched PID exits
- ✅ run a non-interactive shell command under Vigil
- ✅ capture command output to a log
- ✅ release Vigil when the launched command exits
- 🚧 choose a running process from a native process picker
- 🚧 working-directory picker for launched commands
- 🚧 preserve and present richer command exit details
- 🚧 completion notification
- 💡 combine multiple process conditions with AND / OR rules

## CLI and developer workflows

- 🚧 `macvigil` command-line tool
- 🚧 `macvigil run -- npm test`
- 🚧 `macvigil watch-pid 43127`
- 🚧 watch a TCP port such as a local dev server
- 🚧 Docker container and Compose project triggers
- 🚧 shell completion
- 🚧 Homebrew Cask
- 🚧 launch-at-login option
- 💡 Shortcuts support
- 💡 URL scheme and local API
- 💡 editor / Raycast integrations

## AI and local-agent workflows

AI is a first-class use case, not a hard-coded dependency.

- 🚧 Agent Session preset
- 🚧 Local Model Server preset
- 🚧 opt-in detection of common local AI runtimes
- 🚧 show which process or command is keeping Vigil active
- 💡 repository indexing / embedding preset
- 💡 agent completion integration

## Power safety

- ✅ battery reserve cutoff for closed-lid operation
- ✅ critical thermal cutoff
- 🚧 warning state at serious thermal pressure
- 🚧 estimated time to battery reserve
- 🚧 optional Closed-Lid Eco only on external power
- 💡 session energy budget

## Power measurements

MacVigil should earn efficiency claims with data.

- 🚧 baseline normal macOS behavior
- 🚧 benchmark `caffeinate`
- 🚧 benchmark equivalent Amphetamine configurations
- 🚧 benchmark Compute Guard and Closed-Lid Eco
- 🚧 publish battery delta, elapsed time, temperature, and available system-power measurements
- 💡 estimate energy avoided when Job Guard ends earlier than a timer would have

See [docs/POWER-BENCHMARKS.md](docs/POWER-BENCHMARKS.md).

## Compatibility and distribution

- 🚧 validate multiple Apple Silicon generations
- 🚧 validate Intel hardware
- 🚧 maintain a Mac model × macOS compatibility matrix
- 🚧 harden lid/wake race handling
- 🚧 deliberate crash-recovery testing
- 🚧 Developer ID signing
- 🚧 Apple notarization

## 1.0 criteria

MacVigil should not call itself 1.0 until:

- open-lid protection is broadly validated
- closed-lid compatibility and unsupported cases are documented
- crash recovery is deliberately tested
- battery and thermal safeguards are reliable
- power benchmarks are reproducible
- the app is Developer ID signed and notarized
- installation, updating, and authorization cleanup are tested and documented

## Not goals

MacVigil will not:

- defeat mandatory thermal or critical-battery safety behavior
- silently modify macOS password or Lock Screen policy
- claim private or undocumented APIs are stable Apple contracts
- claim lower power usage than another product without reproducible measurements
- keep the machine awake indefinitely after a known protected job has finished
