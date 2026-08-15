# MacVigil Documentation

MacVigil is an energy-aware runtime guard for macOS. These documents separate product promises from implementation details and experimental behavior.

## Start here

- [Power Efficiency](POWER-EFFICIENCY.md) — why MacVigil separates compute, display, lid, battery, and job lifetime
- [Power Benchmarks](POWER-BENCHMARKS.md) — how efficiency claims should be measured
- [Use Cases](USE-CASES.md) — AI, development, remote work, rendering, research, transfers, servers, and more
- [Architecture](ARCHITECTURE.md) — power assertions, lid guard, backlight control, watchdog, and cleanup
- [Troubleshooting](TROUBLESHOOTING.md) — recovery steps and diagnostics
- [Security Model](SECURITY-MODEL.md) — exact privilege boundary and what MacVigil never changes

## Project planning

See the repository-level [ROADMAP.md](../ROADMAP.md) for planned milestones and [CONTRIBUTING.md](../CONTRIBUTING.md) before changing power-management behavior.

## Experimental behavior

Closed-Lid Eco currently uses implementation details that are not public stable macOS APIs. Compatibility can change between OS versions. The project documents those mechanisms explicitly rather than presenting them as guaranteed Apple-supported behavior.
