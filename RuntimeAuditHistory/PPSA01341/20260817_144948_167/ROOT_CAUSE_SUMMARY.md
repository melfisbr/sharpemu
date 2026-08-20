# Runtime Root-Cause Summary

Slow WAIT_REG_MEM >=1s: **91**
Known producer: **91/91**
WRITE_DATA producer: **91/91**
Slow-wait total/avg/max ms: **394142,9 / 4331,2 / 6976,0**
45D texture contracts: **59**, unknown=59, no-writer=59, non-resident=59
45D producer provenance traces: **0**
Shader translate slow/success/fail: **4/4/0**
AJM batch start/wait/decode-jobs: **2509/2508/0**
ACM batches/command probes: **3760/38**
AudioOut2 zero/nonzero/context-submit: **80/0/0**
UI start-menu script/subscreen/UI-RIP/script-RIP: **1/1/0/0**
APR read failures: **0**

## Findings

- GPU_WAIT_KNOWN_WRITE_DATA: every >=1s WAIT_REG_MEM sampled by the tracer had a known explicit WRITE_DATA producer. The delay is producer scheduling/visibility, not a missing producer.
- FULLRES_TEXTURE_PROVENANCE_GAP: the 3840x2160 compositor surface 0x45D550000 is sampled while its exact render-target/writer/residency provenance is missing.
- AUDIO_PIPELINE_ZERO_PCM: ACM/AJM batches run, but AudioOut2 observes only zero PCM and no host context-submit. ACM command processing / decode-to-mix lineage must be audited.
- UI_ASSETS_RESOLVED_BEFORE_NATIVE_MENU: uistartmenu.cgpr and subscreen_overlay_backing.ctxr are resolved successfully, but the sampled native UI ranges were not observed. File discovery is not the primary UI blocker in this session.
- SHADER_TRANSLATION_SUCCEEDS_FOR_OBSERVED_SLOW_SHADERS: observed slow shader translations completed successfully; GPU synchronization/provenance remains a stronger blocker than translation failure in this session.
