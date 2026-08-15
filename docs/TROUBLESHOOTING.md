# Troubleshooting

MacVigil intentionally exposes diagnostics because a black display, display sleep, system sleep, and lid-triggered sleep are different states.

## Start with diagnostics

Open MacVigil and choose **Copy Diagnostics**. Useful fields include:

```text
Session active
Runtime profile
Authorization installed
pmset privilege available
Closed-lid mode active
Physical lid closed
External display detected
Kernel lid guard active
Kernel selector status / return
AppleClamshellCausesSleep
SleepDisabled readback
Backlight dimmed by MacVigil
Battery / power source
Battery reserve
Thermal pressure
Last idle-sleep veto
Last system wake notification
```

The report also includes recent `pmset` assertions and sleep/wake logs.

## “The screen went black; did the Mac sleep?”

Not necessarily.

In **Compute Guard**, MacVigil deliberately allows normal display sleep. The computer can remain awake and keep running a job while the display is dark.

Check:

- whether the job continued
- `pmset -g assertions`
- recent `pmset -g log`

A display-only event should not be reported as a system-sleep failure.

## Closed-Lid Eco will not start

Check:

1. Closed-Lid Authorization is installed.
2. `pmset privilege available` is true in diagnostics.
3. the kernel selector did not return an error.
4. battery is above the configured reserve.

MacVigil refuses to present Closed-Lid Eco as armed if the experimental kernel guard is rejected.

## Authorization exists but sudo is rejected

MacVigil expects one exact sudoers fragment:

```text
/etc/sudoers.d/macvigil
```

and only these two commands:

```text
/usr/bin/pmset -a disablesleep 1
/usr/bin/pmset -a disablesleep 0
```

Remove and reinstall the authorization from the app. If another unrelated sudoers file is malformed, MacVigil validates only its own fragment to avoid making that unrelated configuration part of MacVigil's install/remove logic.

## The Mac still slept with the lid closed

Copy diagnostics after reopening and inspect:

- `Kernel lid guard active`
- `Kernel selector status`
- `Kernel selector return`
- `AppleClamshellCausesSleep`
- `SleepDisabled readback`
- recent `pmset` sleep/wake log

If the selector was accepted and `SleepDisabled=1` but the log still shows `Clamshell Sleep`, the macOS build may be overriding or changing the internal root-domain mechanism. File a compatibility report with the exact Mac model and macOS build.

## The Mac appears to sleep with the lid open

First determine whether it was only display sleep.

Compute Guard does not keep the display awake. If you need the display itself to stay visible, choose **Full Awake**.

If the sleep log shows actual system sleep, include the sleep reason in a bug report.

## Built-in display brightness did not restore

Normally the app or watchdog restores the brightness saved before Closed-Lid Eco darkened the panel.

If brightness remains very low after an abnormal crash:

- use the keyboard brightness keys,
- relaunch MacVigil and end any active Closed-Lid Eco state,
- reboot if necessary.

Do not interpret brightness `0` as proof that the panel is fully powered off.

## Emergency restore of normal sleep

Run:

```bash
sudo pmset -a disablesleep 0
```

Verify:

```bash
pmset -g | grep -i SleepDisabled
```

The expected value is `0`.

If an experimental clamshell override appears to remain active after the app/helper has stopped, relaunch MacVigil and arm/end Closed-Lid Eco, or reboot the Mac.

## Remove authorization manually

```bash
sudo pmset -a disablesleep 0
sudo rm -f /etc/sudoers.d/macvigil
```

## High temperature

Stop Closed-Lid Eco and open the lid. Move the MacBook to a well-ventilated surface.

Never operate a loaded closed MacBook inside a bag, sleeve, drawer, or enclosed space.

MacVigil automatically ends Closed-Lid Eco at critical macOS thermal pressure, but that is a last safety boundary rather than a substitute for ventilation.

## Gatekeeper warning

Development GitHub builds are currently ad-hoc signed until Developer ID signing and notarization are configured.

For a build you personally trust, macOS may allow it through right-click **Open** or **System Settings → Privacy & Security → Open Anyway**. Verify release checksums when they are published.

Do not disable Gatekeeper globally.

## What to include in a bug report

- Mac model
- chip (Apple Silicon generation or Intel)
- exact macOS version/build
- power source
- runtime profile
- external display(s), if any
- what workload was running
- whether the lid was open/closed
- copied MacVigil diagnostics
- concise reproduction steps

Remove usernames, paths, IP addresses, hostnames, or other private information if they appear in logs and are not needed for the report.
