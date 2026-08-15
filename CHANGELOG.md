# Changelog

All notable MacVigil changes will be documented here.

## [Unreleased]

### Added

- fresh MacVigil repository and product identity
- new `com.lotfy.macvigil` bundle identity
- redesigned SwiftUI menu-bar interface
- Compute Guard, Closed-Lid Eco, and Full Awake runtime profiles
- timed, custom, and indefinite sessions
- modular IOKit power assertion controller
- active system idle-sleep veto
- experimental root-domain clamshell guard
- narrowly scoped `pmset disablesleep` authorization
- experimental built-in backlight darkening/restoration
- crash-safe `MacVigilWatchdog`
- low-battery reserve and critical thermal-pressure closed-lid shutdown
- detailed diagnostics
- universal Apple Silicon + Intel GitHub Actions builds
- tag-driven release workflow
- power-efficiency philosophy and benchmark methodology
- use-case, architecture, security, troubleshooting, and compatibility documentation

### Changed from the KeepAwakeMac prototype

- clean MacVigil naming throughout app-visible and persistent identifiers
- new cache directory: `~/Library/Caches/MacVigil/`
- new sudoers fragment: `/etc/sudoers.d/macvigil`
- new watchdog executable: `MacVigilWatchdog`
- power behavior is presented as explicit runtime profiles rather than a collection of low-level toggles
- energy efficiency and job-aware completion are first-class product goals

## Versioning

MacVigil starts in a pre-1.0 stabilization phase. The project will not tag 1.0 until closed-lid compatibility, crash recovery, safety behavior, power benchmarks, and signed/notarized distribution meet the criteria in [ROADMAP.md](ROADMAP.md).
