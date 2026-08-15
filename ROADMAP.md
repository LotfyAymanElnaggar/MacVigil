# MacVigil Roadmap

MacVigil is evolving into an **energy-aware local runtime guard for macOS**: protect the job that matters, minimize unnecessary awake components, and release protection as soon as the job is done.

Legend: ✅ shipped in the fresh MacVigil foundation · 🧪 experimental · 🚧 planned · 💡 later

## Product principles

1. **Protect the job, not every component.** CPU/network availability should not automatically imply a bright display.
2. **Measure before claiming.** Comparative power claims require repeatable tests on the same hardware, OS, workload, duration, and display state.
3. **Safety wins.** Critical battery, thermal emergency, shutdown, and mandatory macOS protections must override convenience.
4. **Restore state cleanly.** System-wide settings need ownership tracking, readback verification, and crash recovery.
5. **End when the work ends.** A 40-minute job should not keep a Mac awake for a guessed four-hour timer.
6. **Explain the state.** Users should be able to see what MacVigil is protecting and why.

---

## 0.1 — Fresh MacVigil foundation

- ✅ new `MacVigil` product identity and bundle ID
- ✅ native SwiftUI menu-bar application
- ✅ **Compute Guard**, **Closed-Lid Eco**, and **Full Awake** profiles
- ✅ timed, custom, and indefinite sessions
- ✅ IOKit system + idle-sleep assertions
- ✅ optional display-awake assertion only for Full Awake
- ✅ active idle-sleep veto while a session is running
- ✅ low-battery reserve for closed-lid operation
- ✅ critical thermal-pressure closed-lid shutdown
- ✅ narrowly scoped one-time `pmset disablesleep` authorization
- 🧪 direct IOPM root-domain clamshell guard
- 🧪 private DisplayServices brightness save/restore for closed-lid darkening
- ✅ crash watchdog with ownership-aware cleanup
- ✅ universal Apple Silicon + Intel GitHub Actions builds
- ✅ detailed power/lid/sleep diagnostics

### Stabilization

- 🚧 validate on multiple Apple Silicon generations
- 🚧 validate on Intel hardware
- 🚧 test stable macOS releases and current macOS betas separately
- 🚧 publish a Mac model × macOS compatibility matrix
- 🚧 harden lid/wake race handling
- 🚧 unit-test parsing and ownership logic
- 🚧 distinguish **display dark**, **display asleep**, and **system asleep** explicitly in diagnostics

---

## 0.2 — Power Safety

### Battery intelligence

- 🚧 separate reserves for battery and external-power sessions
- 🚧 optional “Closed-Lid Eco only on external power” policy
- 🚧 warning before reserve cutoff
- 🚧 estimated time to reserve using recent discharge rate
- 💡 session energy budget (for example, stop after approximately N Wh)

### Thermal intelligence

- ✅ expose current `ProcessInfo.thermalState`
- ✅ disarm Closed-Lid Eco at `.critical`
- 🚧 warning state at `.serious`
- 🚧 session history records thermal-triggered shutdowns
- 💡 Conservative / Balanced / Performance safety policies

### Display efficiency

- ✅ Compute Guard does not hold a display-awake assertion
- 🧪 Closed-Lid Eco can set the built-in backlight to 0 and restore it
- 🚧 benchmark brightness 0 vs normal display sleep
- 🚧 investigate safe panel power-off paths without misrepresenting private APIs as stable macOS contracts
- 🚧 never blank an external display unless the user explicitly chooses that behavior

---

## 0.3 — Power Metrics

MacVigil should earn its efficiency claims with data.

- 🚧 publish repeatable benchmark protocol
- 🚧 baseline normal macOS idle behavior
- 🚧 benchmark `caffeinate`
- 🚧 benchmark equivalent Amphetamine configurations
- 🚧 benchmark MacVigil Compute Guard
- 🚧 benchmark MacVigil Closed-Lid Eco
- 🚧 publish battery delta, average package/system power where measurable, temperature, and task completion
- 💡 per-session estimated energy consumption
- 💡 “energy avoided” estimate when a job-aware session ends earlier than a timer would have

See [docs/POWER-BENCHMARKS.md](docs/POWER-BENCHMARKS.md).

---

## 0.4 — Job-Aware Vigil

The major UX shift: **protect this job until it is done**.

### Processes and commands

- 🚧 keep awake while a selected process is running
- 🚧 keep awake while a PID exists
- 🚧 command wrapper:

```bash
macvigil run -- npm test
```

- 🚧 release assertions when the command exits
- 🚧 preserve and display command exit status
- 💡 AND/OR rules for multiple processes

### Servers and ports

- 🚧 keep awake while a TCP port is listening

```bash
macvigil watch-port 3000
```

- 🚧 local dev-server preset
- 🚧 local inference-server preset
- 💡 network-traffic-aware release grace period

### Containers

- 🚧 Docker container trigger
- 🚧 Docker Compose project trigger
- 💡 local Kubernetes workload trigger

---

## 0.5 — AI / Agent Workflows

AI is a first-class use case, not a hard-coded brand dependency.

- 🚧 Agent Session preset
- 🚧 Local Model Server preset
- 🚧 repository indexing / embedding preset
- 🚧 detect common long-running local AI processes with opt-in rules
- 🚧 show which process is currently keeping Vigil active
- 💡 completion notification
- 💡 Shortcuts action: Start/End Vigil for a process
- 💡 local API for agent/tool integration

The app should remain useful even if specific AI tools change.

---

## 0.6 — Developer Integrations

- 🚧 `macvigil` CLI
- 🚧 Homebrew Cask
- 🚧 Shortcuts support
- 🚧 URL scheme
- 🚧 shell completion
- 🚧 launch-at-login option
- 💡 VS Code / editor integrations
- 💡 Raycast extension
- 💡 local webhook on session completion

---

## 1.0 criteria

MacVigil should not call itself 1.0 until:

- stable open-lid protection is validated broadly
- closed-lid behavior has a published compatibility matrix and clear unsupported cases
- crash recovery has been tested deliberately
- battery + thermal safeguards are reliable
- power benchmarks are reproducible
- the app is Developer ID signed and notarized for normal direct distribution
- installation/uninstallation and authorization cleanup are documented and tested

## Not goals

MacVigil will not:

- defeat mandatory thermal or critical-battery safety behavior
- silently modify macOS password / Lock Screen policy
- claim private or undocumented APIs are stable Apple contracts
- claim lower power usage than another product without a reproducible benchmark
- keep the machine awake indefinitely when a known protected job has already completed
