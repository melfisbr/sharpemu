# DBFZ Startup + Scheduler + RenderThread Fix V1.8.17.6 SAFE

Evidence from the direct 2026-08-15 run:

* exact PPSA09790 eboot loads as ELF64 SceDynExec / Gen5;
* 2,766 eboot NIDs and 495,681 relocation descriptors are accepted;
* seven LLE modules preload successfully and imported-data rebind reaches unresolved=0;
* the same 3,241 merged import stubs are rebuilt eight times during module
  initializers, together with repeated TLS handler/pattern setup;
* native guest worker runtime reports max_concurrent=2 even though the backend
  comment explicitly targets 8-12 concurrent TBB threads;
* early TaskGraph/Pool guest threads show DEDICATED create+run, while later
  AgcSubmissionThread, RHIThread, RenderThread 0 and RTHeartBeat 0 show create
  with no run in the failing log;
* Vulkan initializes and presents the splash; 30 seconds later Unreal aborts
  because GameThread timed out waiting for RenderThread.

Repairs:

1. Cache import-trampoline + TLS image setup across TryExecute re-entry when the
   merged import-table fingerprint and symbol count are unchanged. Per-execution
   guest state is still reset normally.
2. Increase native guest concurrency cap from 2 to 16 while prewarming only 8
   workers, allowing the Ryzen host to schedule long-lived TaskGraph/Pool plus
   AGC/RHI/Render threads without precreating all 16 at startup.
3. Do not change Vulkan event semantics yet. The current evidence points to the
   guest RenderThread not being scheduled; changing GPU synchronization before
   fixing that would mix causes.
4. Keep mkdir EEXIST, missing optional ICU resources and missing retail symbol
   files semantically unchanged; the diagnostic counts them but does not
   fabricate replacements.

All source edits are backed up and automatically restored if patching or build
fails.

## V1.8.17.6 precheck repair

The eboot validator no longer assumes byte 0 is the ELF header. It verifies the exact DBFZ SHA256, scans the early PS5 container for an embedded ELF64 header, and uses the loader-proven SceDynExec identity for this exact hash when the outer container does not expose a raw ELF signature.

## V1.8.17.6 worker-declaration repair

The previous precheck assumed a literal `NativeWorkerMaxConcurrent = N;`.
This version locates the declaration structurally and supports const/readonly
fields, expression-bodied properties, and multi-line initializers. It never
rewrites an unrecognized declaration. The import/TLS setup cache remains an
independent correction and can still be applied safely if the worker declaration
cannot be located.

## V1.8.17.6 validation repair

V1.8.17.2 correctly switched the scheduler patch to structural declaration
discovery, but its package regression still expected the obsolete literal
`NativeWorkerMaxConcurrent = 16;` to exist inside `apply_build.ps1`.

V1.8.17.6 removes that stale assertion and validates the actual structural
helpers across const, readonly, expression-bodied, and multi-line forms.
No source-patch behavior was changed from V1.8.17.2.

## V1.8.17.6 common-helper load repair

V1.8.17.3's offline regression directly called the structural
`NativeWorkerMaxConcurrent` helper functions without dot-sourcing `common.ps1`.
All runtime patch scripts already loaded that file correctly.

V1.8.17.6 explicitly loads `common.ps1` in the offline regression and validates
the helper functions are present before exercising the declaration-shape tests.
The actual source patch logic is unchanged.

## V1.8.17.6 applied-state continuation

The source patch has already been successfully installed and built. V1.8.17.6
contains no source rewrite path. Its precheck now validates the *new* source
state rather than the obsolete pre-patch anchors:

- startup cache marker present;
- fingerprint/cache hit+prime code present;
- original SetupImportStubs/TLS operations preserved inside the cache miss;
- prewarm uses Math.Min(NativeWorkerMaxConcurrent, 8);
- NativeWorkerMaxConcurrent resolves to 16.

The offline regression validates continuation/build/post-audit/diagnostic
contracts only. It no longer searches apply_build.ps1 for the old patch payload.
