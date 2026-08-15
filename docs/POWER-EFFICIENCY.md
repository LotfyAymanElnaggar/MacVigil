# Power Efficiency

MacVigil is not trying to keep **everything** awake. Its goal is to keep the **workload** alive while letting macOS reduce power use for components the workload does not need.

## The key distinction

A long-running local job may require:

- CPU/GPU execution
- networking
- storage
- memory
- a reachable user session

It often does **not** require:

- a bright built-in display
- an external display
- continuous user interaction
- a guessed multi-hour keep-awake timer after the work has already finished

MacVigil therefore treats system availability, display state, lid behavior, battery reserve, thermal pressure, and job lifetime as separate decisions.

## Runtime profiles

### Compute Guard

Designed for AI agents, builds, Docker, servers, downloads, indexing, notebooks, and similar background work.

MacVigil prevents idle system sleep but does not hold a display-awake assertion. macOS can apply its normal display-sleep policy.

### Closed-Lid Eco

Designed for unattended MacBook workloads where the lid is physically closed.

The current experimental implementation combines:

- normal MacVigil power assertions
- a narrowly authorized `pmset -a disablesleep 1`
- an experimental IOPM root-domain clamshell guard
- built-in backlight brightness saved and set to `0` when no external display is present
- battery reserve and thermal safety
- a crash watchdog that restores state

Brightness `0` is **not** the same statement as “the display panel consumes zero power.” MacVigil will not make that claim without measurement.

### Full Awake

Designed for presentations, monitoring, dashboards, demos, or other situations where the display is part of the workload.

MacVigil holds both system and display idle-sleep assertions.

## Where the biggest energy saving may come from

Display control matters, but job-aware completion can matter even more.

Suppose a user starts a four-hour timer because a build or agent might take that long. The job actually finishes after 42 minutes. A timer-based tool can leave the system protected for another 3 hours and 18 minutes.

A future job-aware MacVigil session should release its assertions immediately when the protected process exits.

```text
job starts
   ↓
Vigil protects runtime
   ↓
display may sleep/darken
   ↓
job finishes
   ↓
Vigil releases protection
   ↓
normal macOS sleep resumes
```

That is why process, PID, port, and container triggers are central to the roadmap.

## Battery policy

Closed-lid operation can hide the normal visual cues that a MacBook is still working. MacVigil therefore treats battery reserve as a safety boundary rather than a cosmetic preference.

Current behavior:

- reserve options: 10%, 15%, 20%, 25%
- Closed-Lid Eco stops when battery reaches the reserve
- normal macOS sleep state is restored when MacVigil owns the global setting

Planned work includes discharge-rate estimates, warnings before cutoff, and optional external-power-only policies.

## Thermal policy

Closing a MacBook does not make active compute free. Long CPU/GPU workloads can still produce substantial heat.

Current MacVigil behavior exposes macOS thermal pressure and disarms Closed-Lid Eco when `ProcessInfo.thermalState` reaches `.critical`.

MacVigil does not attempt to defeat mandatory thermal emergency sleep or shutdown behavior.

## External displays

Closed-Lid Eco does not intentionally blank external displays. If an external display is detected, the built-in backlight override is skipped.

## Comparing with other tools

MacVigil should not claim to consume less energy than Amphetamine, `caffeinate`, or another keep-awake utility based on architecture alone.

Comparisons must use the same:

- Mac model
- battery health
- macOS version
- workload
- display configuration and brightness
- power source
- network conditions
- duration
- thermal environment

See [POWER-BENCHMARKS.md](POWER-BENCHMARKS.md).

## Principle

> **Keep the work running. Not the screen.**

That phrase is a design constraint, not a promise that every workload can run at minimum possible power. MacVigil should continuously improve its ability to protect only what the workload actually requires.
