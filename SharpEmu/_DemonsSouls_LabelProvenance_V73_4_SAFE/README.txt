SharpEmu Demon's Souls Label Provenance V73.4 SAFE

WHAT V73.3 PROVED
The ordered-visibility parameter fix must be kept:
- ordered-action fence counter: >=512 -> 128
- guest queue backpressure: 8 -> 1
- suspended waits: 7 -> 5
- unresolved imports: 0
- deviceLost=True: 0
- Gen5 metadata remains 53/49 for the main EBOOT.

REMAINING FIVE WAITS
  0x0000000456CFF100  dcb.graphics submission=13
  0x0000000456CFF360  acb.compute[56] submission=18
  0x0000000456CFF580  acb.compute[72] submission=20
  0x0000000456CFF700  acb.compute[32] submission=22
  0x0000000456CFF4C0  acb.compute[40] submission=23

All remain real 32-bit compare==3 waits from value 0 to reference 1 and were
reported producer=none-observed.

WHY V73.4 IS DIAGNOSTIC INSTEAD OF ANOTHER FORCE-WAKE
The current source already contains:
- a global ordered visibility probe for truly producerless waits;
- Vulkan dirty-buffer GPU->CPU writeback;
- NotifyGpuMemoryWriteback -> GpuWaitRegistry.RecordProduced;
- PM4 WRITE_DATA / RELEASE_MEM / DMA producer publication;
- V61.23.5 producer-history preservation.

Blindly forcing 1 or adding another global drain would hide which missing
producer contract is wrong.

V73.4 adds one opt-in bounded trace:
  SHARPEMU_TRACE_LABEL_PROVENANCE=1

It records only:
- producerless wait targets;
- future PM4 producer ranges that overlap those targets;
- compute storage/global buffers that overlap a target, including Writable and
  WriteBackToGuest classification;
- sampled compute scans with the nearest buffer when there is no overlap;
- successful Vulkan writeback ranges that overlap a target;
- address-bearing EVENT_WRITE 0x38/0x39 packets if they occur.

It does NOT change:
- wait comparisons;
- label values;
- wake policy;
- canonical-empty-fastpath;
- PM4 producer semantics;
- compute binding classification;
- Vulkan writeback semantics;
- V73.3 ordered-visibility behavior;
- loader/NIDs.

BASELINE SOURCE GUARDS
AgcExports.cs:
  AED440CE2307DE6103C28889303F41919D605F64B105A0D853B9E9AF4A948679
VulkanVideoPresenter.cs after V73.3:
  F5FDDAAB23E192C90A14FA3B88C335903B60A2FFB6960716AEE746A0200B82AA

The diagnostic clears the existing high-frequency AGC/Vulkan tracing and only
enables this bounded provenance channel. It creates:
  SharpEmu_V73_4_LABEL_PROVENANCE_RESULT_<timestamp>.zip

The result self-classifies the next branch:
- compute-overlap-writeback-disabled
- compute-overlap-not-classified-writable
- compute-overlap-writable-but-no-writeback-overlap
- compute-overlap-and-writeback-observed-check-value-wake
- pm4-producer-overlap-observed
- addressed-event-write-observed
- compute-ran-without-label-range-overlap
- producer-path-not-yet-observed
