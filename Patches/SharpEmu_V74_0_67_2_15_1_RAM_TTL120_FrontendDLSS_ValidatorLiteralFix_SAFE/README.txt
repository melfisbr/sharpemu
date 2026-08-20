SharpEmu V74.0.67.2.15.1
RAM TTL120 + Frontend DLSS Validator Literal Fix SAFE

V2.15 did NOT modify the repository. RUN_3 executes package validation first,
and validation stopped on an undefined $token before source patching.

The user's V2.15 RUN_2 already proved the actual source anchors:
  ram_field_declaration_safe=true
  ram_field_type=long
  ram_later_ttl_consumer_count=5
  ram_dryrun_lookup_redirect=true
  frontend_quality_anchor_count=1
  PRECHECK PASSED

V2.15 validator bug:
  .Contains(".Replace($token,'V74067215LargeArraySnapshotTtlMs')")

Set-StrictMode expanded undefined $token before the literal comparison.

A second latent validator bug was fixed at the same time:
  .Contains("$env:SHARPEMU_VK_UPSCALER='dlss'")

That expression would inspect an expanded environment value rather than the
literal launcher source.

V2.15.1 uses single-quoted here-string needles and adds a generic validator
regression that rejects .Contains("...$variable...") patterns anywhere in the
package scripts. The self-test constructs the old broken form from character
fragments, proves it is detected, and proves the single-quoted form is safe.

The actual runtime feature ownership remains V74.0.67.2.15:
- effective large-array TTL 1000..120000 ms;
- V74.0.64 cache remains bounded;
- V2.13 content identity remains;
- frontend explicitly sets pre-composite, RAM cache=2, RAM TTL=120000,
  and detile pool=64.

NORMAL DLSS USE AFTER APPLY
===========================
Rendering:
  1. Enable Upscaler.
  2. Select DLSS.
  3. Select the Quality preset.
  4. Launch the game.

If the master Upscaler toggle is OFF, selecting DLSS alone is NOT sufficient.

No RUN_5, PowerShell environment variable, or manual provider path is required
for normal use. RUN_5 intentionally removes forced shell overrides before
opening the GUI so a runtime run can prove frontend-only activation.

DLSS proof:
  selected=dlss
  state=active
  dlss_dispatches>0

RAM proof:
  ARRAY_CACHE_OWNER / ARRAY_SINGLEFLIGHT ttl_ms=120000
