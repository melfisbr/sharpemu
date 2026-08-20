# Runtime Root-Cause Summary

Slow WAIT_REG_MEM >=1s: **59**
Known producer: **59/59**
WRITE_DATA producer: **59/59**
Slow-wait total/avg/max ms: **260094,8 / 4408,4 / 7071,3**
45D texture contracts: **0**, unknown=0, no-writer=0, non-resident=0
45D producer/state/unresolved-DCC traces: **0/0/28**
Scanout lineage / valid 4K lineage: **0/0**
Shader translate slow/success/fail: **0/0/0**
AJM batch start/wait/decode-jobs: **0/0/0**
ACM batches/command probes/deref probes: **0/0/0**
AudioOut2 zero/nonzero/context-submit: **0/0/0**
ResourcePool GatherResourceFileInfo: **36,881s**
UI start-menu script/subscreen/UI-RIP/script-RIP: **0/0/0/0**
APR read failures: **0**

## Findings

- GPU_WAIT_KNOWN_WRITE_DATA: every >=1s WAIT_REG_MEM sampled by the tracer had a known explicit WRITE_DATA producer. The delay is producer scheduling/visibility, not a missing producer.
- RESOURCE_ENUMERATION_STILL_SLOW: ResourcePool::GatherResourceFileInfo took 36,881s even with focused tracing.
