#!/bin/bash
set -euo pipefail

LABEL="${1:-macvigil-run}"
DURATION="${2:-600}"
INTERVAL="${3:-30}"

if [[ ! "$DURATION" =~ ^[0-9]+$ ]] || [[ "$DURATION" -lt 30 ]]; then
  echo "Duration must be an integer >= 30 seconds." >&2
  exit 2
fi

if [[ ! "$INTERVAL" =~ ^[0-9]+$ ]] || [[ "$INTERVAL" -lt 5 ]]; then
  echo "Interval must be an integer >= 5 seconds." >&2
  exit 2
fi

SAFE_LABEL="$(printf '%s' "$LABEL" | tr ' /:' '---' | tr -cd 'A-Za-z0-9._-')"
[[ -n "$SAFE_LABEL" ]] || SAFE_LABEL="run"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BASE_DIR="${MACVIGIL_BENCHMARK_DIR:-$PWD/benchmark-results}"
OUT_DIR="$BASE_DIR/${STAMP}-${SAFE_LABEL}"
mkdir -p "$OUT_DIR"

META="$OUT_DIR/metadata.txt"
CSV="$OUT_DIR/samples.csv"

{
  echo "MacVigil power benchmark harness"
  echo "label=$LABEL"
  echo "started_utc=$STAMP"
  echo "duration_seconds=$DURATION"
  echo "sample_interval_seconds=$INTERVAL"
  echo
  echo "--- sw_vers ---"
  /usr/bin/sw_vers || true
  echo
  echo "--- hardware ---"
  /usr/sbin/system_profiler SPHardwareDataType 2>/dev/null || true
  echo
  echo "--- power settings ---"
  /usr/bin/pmset -g || true
  echo
  echo "--- initial assertions ---"
  /usr/bin/pmset -g assertions || true
  echo
  echo "--- initial battery registry ---"
  /usr/sbin/ioreg -rn AppleSmartBattery -a 2>/dev/null || true
} > "$META"

printf 'elapsed_seconds,timestamp_utc,battery_percent,power_source,remaining_text,thermal_text\n' > "$CSV"

sample() {
  local elapsed="$1"
  local batt percent source remaining thermal now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  batt="$(/usr/bin/pmset -g batt 2>/dev/null || true)"
  percent="$(printf '%s\n' "$batt" | /usr/bin/grep -Eo '[0-9]{1,3}%' | /usr/bin/head -n 1 | tr -d '%' || true)"

  if printf '%s\n' "$batt" | /usr/bin/grep -qi 'Battery Power'; then
    source="battery"
  elif printf '%s\n' "$batt" | /usr/bin/grep -qi 'AC Power'; then
    source="adapter"
  else
    source="unknown"
  fi

  remaining="$(printf '%s\n' "$batt" | /usr/bin/grep -Eo '[0-9]+:[0-9]+ remaining|calculating|charged' | /usr/bin/head -n 1 || true)"
  thermal="$(/usr/bin/pmset -g therm 2>/dev/null | tr '\n,' '  ' | tr -s ' ' || true)"

  printf '%s,%s,%s,%s,"%s","%s"\n' \
    "$elapsed" "$now" "${percent:-}" "$source" "$remaining" "$thermal" >> "$CSV"
}

START_EPOCH="$(date +%s)"
END_EPOCH=$((START_EPOCH + DURATION))

while true; do
  NOW_EPOCH="$(date +%s)"
  ELAPSED=$((NOW_EPOCH - START_EPOCH))
  sample "$ELAPSED"
  [[ "$NOW_EPOCH" -ge "$END_EPOCH" ]] && break
  sleep "$INTERVAL"
done

{
  echo
  echo "--- final assertions ---"
  /usr/bin/pmset -g assertions || true
  echo
  echo "--- final battery ---"
  /usr/bin/pmset -g batt || true
  echo
  echo "--- final battery registry ---"
  /usr/sbin/ioreg -rn AppleSmartBattery -a 2>/dev/null || true
  echo
  echo "finished_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} >> "$META"

echo "Benchmark complete: $OUT_DIR"
echo "Samples: $CSV"
echo "Metadata: $META"
