# MacVigil Validation Checklist

This checklist is for validating a MacVigil build before calling its closed-lid behavior reliable on a specific Mac and macOS version.

## Before testing

- Put the MacBook on a hard, ventilated surface.
- Do not test a sustained workload inside a bag, sleeve, drawer, or other enclosed space.
- Use a harmless workload that makes progress continuously, for example a script that appends a timestamp to a file every few seconds.
- Keep **Copy Diagnostics** available. If a test fails, copy diagnostics **before ending Vigil** whenever possible.

## 1. Open-lid idle test

Use **Closed-Lid Eco** and start Vigil with the lid open.

Confirm in the app:

- Runtime protection is configured.
- Closed-lid authorization is available.
- Display / Lock Screen policy is confirmed.
- SleepDisabled becomes verified after the session starts.
- The kernel lid guard becomes armed after the session starts.

Leave the Mac untouched for longer than the normal display-sleep timeout.

Expected result:

- the workload continues;
- macOS does not use display sleep as the reason to enter the Lock Screen while **Prevent display sleep** is enabled.

## 2. Closed-lid continuity test

With Vigil still active, start the timestamp workload and close the lid for at least 5 minutes.

Expected result:

- the workload has no multi-minute gap;
- reopening the lid does not show evidence of a full system sleep/wake cycle;
- MacVigil still reports its selected protection layers as active.

## 3. Battery test

Repeat Closed-Lid Eco while running on battery.

Confirm:

- the configured battery reserve is shown correctly;
- closed-lid protection stops at the reserve when battery safety is enabled;
- normal macOS behavior is restored after the stop.

## 4. External-power test

Repeat the continuity test while connected to power.

Expected result:

- runtime continuity remains stable;
- battery-reserve logic does not incorrectly stop the session.

## 5. External-display test

Connect an external display, start Closed-Lid Eco, then close the lid.

Expected result:

- MacVigil detects the external display;
- the built-in backlight override is skipped when appropriate;
- the selected runtime protection remains active.

## 6. Clean stop test

Start a closed-lid session, reopen the lid, and end Vigil normally.

After the session ends, diagnostics should show normal restoration, including `SleepDisabled=0` when MacVigil owned that setting.

## 7. Crash / watchdog recovery test

Only perform this after the normal stop path succeeds.

Start a closed-lid session, confirm the protection layers are armed, then terminate the MacVigil process unexpectedly.

Expected result after the watchdog cleanup window:

- the kernel lid guard is released;
- MacVigil-owned global SleepDisabled is restored to 0;
- saved built-in brightness is restored;
- stale watchdog files are removed.

## 8. Failure evidence

When reporting a problem, include:

- Mac model;
- macOS version/build;
- charger or battery;
- selected MacVigil switches;
- whether an external display was attached;
- whether the workload actually stopped making progress;
- diagnostics copied before ending Vigil;
- approximate time the lid was closed and reopened.

A black screen or Lock Screen by itself is not sufficient evidence of system sleep. Use workload continuity, MacVigil's system-sleep notifications, and the macOS sleep/wake log together.
