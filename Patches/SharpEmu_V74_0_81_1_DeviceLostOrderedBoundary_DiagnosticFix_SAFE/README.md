# SharpEmu V74.0.81.1 — DeviceLost Ordered Boundary + Diagnostic Fix SAFE

Correction package for the V74.0.81 deep draw flow experiment.

Observed failure addressed:
- V74.0.81 reached the main loop / first frame, then Vulkan returned `ErrorDeviceLost` while submitting an ordered `write_data` after aggressive compute batch-boundary removal.
- The PowerShell 5.1 diagnostic then failed while reading `.Count` from a scalar `Select-String` result, preventing summary/result ZIP emission.

This package intentionally keeps the safe V81 queued-vs-inflight byte accounting, but:
1. restores the mandatory compute-start batch boundary;
2. restores the resource/upload boundary after `CreateComputeDispatchResources`;
3. removes the now-redundant shared-only late flush guard;
4. reduces default same-submission scheduler burst from 8 to 2 (env override retained);
5. replaces diagnostic `Select-String ... .Count` usage with explicit counting and prints log/summary/ZIP paths before launch.

It does not change DCC provenance recovery (V74.0.80), sampler alias fixes, guest fences/labels, or game files.
