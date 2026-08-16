# DBFZ Startup + Scheduler + RenderThread Fix V1.8.17.1 SAFE

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

## V1.8.17.1 precheck repair

The eboot validator no longer assumes byte 0 is the ELF header. It verifies the exact DBFZ SHA256, scans the early PS5 container for an embedded ELF64 header, and uses the loader-proven SceDynExec identity for this exact hash when the outer container does not expose a raw ELF signature.
