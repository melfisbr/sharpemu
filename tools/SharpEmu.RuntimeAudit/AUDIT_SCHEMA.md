# SharpEmu RuntimeAudit output schema

The auditor always creates one `SharpEmu_RuntimeAudit_Result_<timestamp>` folder
and one ZIP with the same basename.

## Primary files

- `consolidated_audit.json` — full machine-readable report.
- `correction_inputs.json` — compact evidence selected specifically for patch generation.
- `AUDIT_SUMMARY.md` — human-readable summary.
- `AUDIT_MANIFEST_SHA256.txt` — hashes of files in the audit folder.

## `consolidated_audit.json` sections

- `host`: OS, architecture, CPU count, physical RAM, .NET and GPU information.
- `repository`: git HEAD/status and key source hashes.
- `eboot`: SHA256, size, interesting SELF/ELF strings, referenced libraries/modules.
- `game`: file count, extension distribution, media inventory and largest files.
- `source`:
  - all runtime environment parameters found through `GetEnvironmentVariable`;
  - TODO/stub/unimplemented/unsupported markers;
  - P/Invoke / NativeLibrary integrations;
  - NuGet dependencies;
  - API-family source coverage;
  - source hashes and copied key-source snapshot.
- `runtime`:
  - exit code and wall time;
  - CPU/RAM/GPU time series summary;
  - loader stage timeline;
  - video timeline;
  - audio timeline;
  - queue/wait/compute/presentation timeline;
  - runtime unmapped/unsupported events;
  - API runtime evidence;
  - observed file paths.
- `findings`: prioritized, evidence-backed issues.

## Important safety property

The default profile intentionally avoids framebuffer/image readbacks and broad
draw dumps. It focuses on textual runtime telemetry, process metrics and source
inventory so the audit itself does not materially change guest rendering.
