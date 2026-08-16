SharpEmu Demon's Souls Post-Metadata AGC Source Audit V73.2 SAFE

V73.1.1 RESULT
The Gen5 dynamic import metadata correction is validated by runtime:
- main eboot: SCE import metadata libraries=53 modules=49
- libc.prx: libraries=3 modules=3
- libSceNpCppWebApi.prx: libraries=6 modules=6
- runtime unresolved imports: 0

Therefore the 483 static NO_HLE_EXPORT rows from the EBOOT audit are not
evidence that 483 HLE implementations are required. They include native PRX
symbols and native data objects.

NEXT REAL BLOCKER SURFACE
The same V73.1.1 runtime contains:
- 7 agc.wait_suspended, all producer=none-observed
- 43 agc.dispatch_reject reason=canonical-empty-fastpath
- 8 vk.guest_queue_backpressure samples
- 14 sampled vk.ordered_action_fence_wait traces
- 1 presented guest frame
- 0 deviceLost=True
- 0 unresolved imports
- 0 unsupported vector opcode reports

A semantic AGC patch is deliberately NOT applied in V73.2 because the current
canonical-empty-fastpath branch is newer than the source snapshots already
available to ChatGPT. Patching an older branch would risk reintroducing earlier
producer/wait regressions.

V73.2 collects the exact current source for:
- AgcExports.cs
- GpuWaitRegistry.cs
- VulkanVideoPresenter.cs
- SelfLoader.cs
- up to 40 additional C# files discovered from synchronization/render symbols

It also generates:
- SOURCE_STATE.txt
- SOURCE_SHA256.txt
- SOURCE_SYMBOL_MATCHES.csv
- source windows around canonical-empty-fastpath, indirect dispatch,
  WAIT_REG_MEM producer tracking, EVENT_FASTPATH, ordered actions,
  queue backpressure and render-target sampling
- current git status/diff

SAFETY
- No source mutation.
- No build.
- No game execution.
- Fails if V73.1.1 Gen5 metadata integration is absent.
- Fails if the known bad V61.23.1 eager producer-history removal is active.
- Requires the existing WRITE_DATA/DMA/RELEASE_MEM producer-lineage markers.

Send the generated:
SharpEmu_V73_2_POSTMETADATA_AGC_SOURCE_AUDIT_<timestamp>.zip
back to ChatGPT. The next package can then patch the exact current AGC branch
rather than guessing from an obsolete source snapshot.
