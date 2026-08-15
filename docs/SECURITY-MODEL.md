# Security Model

MacVigil's ordinary Compute Guard and Full Awake profiles do not require administrator privileges.

Closed-Lid Eco uses a narrowly scoped authorization because one layer of the implementation calls `pmset disablesleep`.

## What authorization installs

When the user chooses **Install…** for Closed-Lid Eco, macOS shows its normal administrator authentication dialog. MacVigil does not receive or store the administrator password.

After approval, MacVigil creates:

```text
/etc/sudoers.d/macvigil
```

The rule is scoped to the current macOS username and permits only:

```text
/usr/bin/pmset -a disablesleep 1
/usr/bin/pmset -a disablesleep 0
```

There are no wildcard arguments, shell access, arbitrary file writes, or general passwordless `sudo` privileges.

The temporary rule and installed MacVigil fragment are validated with `visudo -cf`.

## Ownership

`SleepDisabled` is a system-wide setting. MacVigil reads the existing state before changing it.

If another tool or the user already enabled `SleepDisabled`, MacVigil does not claim ownership and should not disable that setting when its own session ends.

If MacVigil changes the setting itself, it records an ownership marker and verifies the value on cleanup.

## Experimental non-root mechanisms

Closed-Lid Eco also currently uses:

- IOPM root-domain external selector 12 for the clamshell guard
- private DisplayServices brightness functions for built-in-display darkening

These do not broaden the sudoers permission, but they are undocumented/internal macOS mechanisms. Their behavior may change between OS versions.

## Crash recovery

The app bundle includes `MacVigilWatchdog`, a companion process that receives no password and no general sudo permission.

While Closed-Lid Eco is armed, it watches a random-token heartbeat. If the GUI crashes or stops refreshing the heartbeat, the companion attempts to:

- release the kernel clamshell override,
- run the exact authorized `pmset ... disablesleep 0` command only when MacVigil owned the setting,
- restore the saved built-in display brightness,
- remove recovery files.

## Password and Lock Screen policy

MacVigil does not ask for, store, or change the macOS login password.

It does not silently weaken Lock Screen settings, password requirements, FileVault, or other authentication policy.

## Mandatory system safety

MacVigil is not intended to defeat mandatory macOS actions caused by conditions such as critical battery, thermal emergency, shutdown, or other system safety events.

Closed-lid compute can create substantial heat. Never use an actively loaded closed MacBook in a bag, sleeve, drawer, or other poorly ventilated space.

## Manual recovery

To restore normal `pmset` sleep behavior after an abnormal test:

```bash
sudo pmset -a disablesleep 0
```

Then quit/relaunch MacVigil or reboot if an experimental in-kernel clamshell state appears to remain active.

To remove MacVigil's authorization manually:

```bash
sudo rm -f /etc/sudoers.d/macvigil
```

## Reporting security issues

Do not post credentials, private tokens, administrator passwords, or sensitive system logs in public issues. For a suspected privilege-escalation bug, provide only the minimum reproduction details needed to identify the problem.
