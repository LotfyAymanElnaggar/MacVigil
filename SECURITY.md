# Security Policy

MacVigil changes system power behavior, and Closed-Lid Eco uses a narrowly scoped privileged `pmset` authorization. Security-sensitive changes should be treated carefully.

Read the complete [Security Model](docs/SECURITY-MODEL.md) for the exact sudoers rule, ownership model, crash recovery behavior, password/Lock Screen policy, and manual recovery steps.

## Reporting a vulnerability

For non-sensitive bugs, use the public GitHub issue tracker.

For a vulnerability that may expose credentials or grant privileges beyond the two documented `pmset disablesleep` commands, do not include passwords, tokens, private keys, or sensitive logs in a public issue. Share only the minimum reproduction information required to identify the problem.

## Supported versions

MacVigil is currently in its pre-1.0 stabilization phase. Closed-Lid Eco is explicitly experimental and compatibility can vary by Mac model and macOS build.
