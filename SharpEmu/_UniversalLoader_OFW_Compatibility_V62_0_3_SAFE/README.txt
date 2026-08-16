SharpEmu Universal Loader / OFW Compatibility V62.0.3 SAFE

This revision replaces the V62.0.2 audit script completely.

Confirmed from the user's V62.0.2 run:
- SelfLoader precheck reports program_header_validation=minimum-size-compatible.
- SharpEmu.Core build succeeds.
- SharpEmu.CLI Debug win-x64 build succeeds.
- The remaining failure is the audit script PowerShell parser.

V62.0.3 changes:
- no new loader semantic change when minimum-size PH validation is already active;
- PowerShell 5.1-safe audit code;
- no command/subexpression interpolation inside report strings;
- no inline if-expression in object properties;
- no nested Where-Object pipelines inside interpolated strings;
- PSObject properties are created with New-Object/Add-Member for conservative PS5.1 compatibility;
- explicit ELF64/wrapper classifier;
- exact loader source snapshots and source evidence in the result ZIP;
- package validator verifies SHA-256 and parses every .ps1 using the PowerShell parser.

The audit never starts a game.
