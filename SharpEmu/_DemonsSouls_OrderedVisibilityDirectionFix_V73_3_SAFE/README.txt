SharpEmu Demon's Souls Ordered Visibility Direction Fix V73.3 SAFE

V73.2 exposed a concrete parameter-binding defect in the current Vulkan
presenter, not a speculative compatibility stub.

Exact audited presenter SHA-256:
534EB79448DF504500D1B018DA98714778FB13D06EC2FF887AC9544C2A1A6364

VulkanOrderedGuestAction fields are ordered as:
  1 Action
  2 DebugName
  3 RequireGlobalVisibility
  4 RequiresGpuToCpuVisibility

SubmitOrderedGuestActionWithVisibility previously supplied its
requiresGpuToCpuVisibility argument positionally as field #3. Consequently:
- ACQUIRE_MEM(false), intended CPU->GPU only, still retained the default
  RequiresGpuToCpuVisibility=true and forced queue fence/readback work.
- known-producer WAIT queue-visibility(true) also set RequireGlobalVisibility,
  widening a queue-local request.
- explicit global visibility is already represented separately by
  SubmitGlobalOrderedGuestAction and remains unchanged.

V73.3 uses named fields:
  RequireGlobalVisibility: false
  RequiresGpuToCpuVisibility: requiresGpuToCpuVisibility

Representative V73.1.1 baseline:
  ordered-action fence counter >= 512
  queue backpressure counter = 8
  WAIT suspended / resumed = 7 / 0
  unresolved imports = 0
  deviceLost=True = 0

Safety:
- exact SHA guard before editing VulkanVideoPresenter.cs
- automatic rollback on build failure
- no AGC wait comparison changes
- no WRITE_DATA / RELEASE_MEM / DMA producer changes
- no GpuWaitRegistry producer-history changes
- no 0/1/1 canonical-empty dispatch changes
- no loader/NID changes

The diagnostic disables high-frequency tracing, compares the existing low-rate
fence/backpressure/wait counters to the baseline, and also captures the exact
current Gen5GlobalMemoryBinding / Gen5ShaderScalarEvaluator / WriteBackToGuest
source files. If producerless waits remain, that evidence is already included
for the next correction.
