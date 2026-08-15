# Power Benchmarks

MacVigil's power-efficiency positioning should be supported by measurements rather than assumptions.

This document defines the benchmark rules before results exist, which reduces the temptation to tune the test around a preferred outcome.

## Benchmark harness

v0.9 adds a small local harness at `scripts/power-benchmark.sh` so repeated runs collect the same basic metadata and battery samples.

Run it from a checkout of the repository:

```bash
bash scripts/power-benchmark.sh baseline 3600 30
bash scripts/power-benchmark.sh caffeinate 3600 30
bash scripts/power-benchmark.sh macvigil-compute-guard 3600 30
```

Arguments are:

1. a label for the run
2. duration in seconds
3. sample interval in seconds

Results are written under `benchmark-results/` unless `MACVIGIL_BENCHMARK_DIR` is set. Each run contains a CSV sample file and a metadata file with the macOS/hardware profile, initial/final power assertions, power settings, and raw battery-registry snapshots.

The harness intentionally does **not** claim to measure precise whole-system watt-hours. Battery percentage is coarse and `pmset` thermal output is platform-dependent. Use higher-quality external or system measurement tools when a claim requires them, while keeping the same workload/configuration controls described below.

## What we want to measure

For each configuration, record where practical:

- starting and ending battery percentage
- starting and ending battery energy / charge data when available
- average system/package power from an appropriate measurement tool
- CPU/GPU utilization
- display configuration and brightness
- wall-clock runtime
- task completion state
- thermal pressure / temperature observations
- whether the system, display, or lid entered an unexpected state

The most important metric is not always the app process's own CPU usage. A keep-awake policy changes what the **whole Mac** is allowed to power down.

## Comparison configurations

At minimum:

1. **Normal macOS** — no keep-awake utility
2. **`caffeinate`** — equivalent system-sleep protection
3. **Amphetamine** — an equivalent profile/settings combination
4. **MacVigil Compute Guard**
5. **MacVigil Closed-Lid Eco** where supported and safe
6. **MacVigil Full Awake** where relevant

Do not compare a dark-screen MacVigil profile to a bright-screen competitor profile and call the difference an application-efficiency win. Display state must be equivalent when the claim is about the keep-awake implementation itself.

## Hardware controls

Every comparison in a benchmark set must use the same machine.

Record:

```text
Mac model:
Chip:
RAM:
Battery cycle count:
Battery maximum capacity:
macOS version/build:
External power: yes/no
External displays:
Room temperature (approx):
```

A result on one machine should not be generalized to all Macs.

## Workload profiles

### A. Idle runtime

Keep the machine awake with no meaningful foreground workload.

Purpose: reveal baseline cost of the awake policy and display configuration.

Suggested duration: 60 minutes.

### B. Local development server

Run a stable local server with low background traffic.

Example:

```bash
python3 -m http.server 8000
```

Purpose: simulate a developer leaving a service reachable.

### C. CPU build

Use a repeatable source tree and clean build command.

Purpose: test whether policies affect task completion or thermal behavior under sustained compute.

### D. Local AI inference

Use the same model, prompt set, context length, and runtime configuration for every test.

Purpose: represent MacVigil's core local-AI use case.

### E. Network transfer

Transfer a fixed-size file over the same local network path.

Purpose: represent downloads/uploads/NAS workflows.

## Display tests

Display behavior deserves a separate benchmark because brightness 0, normal display sleep, and panel power-off are not interchangeable.

Test at least:

- display awake at fixed brightness
- brightness set to 0 while the system remains awake
- normal display sleep while the system remains protected

If a private/internal mechanism is used, record the exact macOS build because behavior may change.

## Timer waste vs job-aware release

This benchmark captures a different kind of energy saving.

Scenario:

- user estimates a job at 4 hours
- actual job runtime is 45 minutes

Compare:

- four-hour fixed keep-awake timer
- job-aware session that releases protection at minute 45

Record the machine's energy use from job completion until normal sleep occurs.

This measurement can show the value of **ending protection at the correct time**, independent of low-level assertion efficiency.

## Repetition

Run each battery benchmark at least three times. More repetitions are better when variance is high.

Publish:

- individual runs
- mean
- range or standard deviation
- any discarded run and the reason it was discarded

Do not hide failed, thermally throttled, or interrupted runs if they reveal a product limitation.

## Results table template

| Hardware | macOS | Workload | Configuration | Display state | Duration | Battery / energy delta | Completed? | Notes |
|---|---|---|---|---|---:|---:|---|---|
| TBD | TBD | Idle | MacVigil Compute Guard | Display sleep | 60m | TBD | yes | TBD |

## Claims policy

Acceptable before benchmarks:

> MacVigil is designed around energy-aware runtime protection.

Acceptable after reproducible data:

> On Mac model X, macOS build Y, workload Z, configuration A used N% less measured energy than configuration B under the documented test protocol.

Not acceptable:

> MacVigil always uses less power than Amphetamine.

unless a scope and evidence exist that genuinely justify such a claim.
