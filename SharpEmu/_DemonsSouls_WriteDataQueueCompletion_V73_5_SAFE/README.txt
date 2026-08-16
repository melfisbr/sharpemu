SharpEmu Demon's Souls WRITE_DATA Queue Completion V73.5 SAFE

V73.4 RESULT
- producerless WAIT registrations: 5
- compute/storage overlaps with those labels: 0
- PM4 producer overlaps: 5/5
- all five producers are WRITE_DATA
- GPU writeback overlaps: 0
- runtime unresolved imports: 0
- deviceLost=True: 0

PRODUCER GRAPH
  [V73.4][LABEL] range_overlap label=0x0000000456CFF100 range=0x0000000456CFF100+0x8 source=pm4_producer_registered queue=acb.compute[32] submission=15 packet=0x000000060A199348 name=write_data dst=0x0000000456CFF100 count=2
  [V73.4][LABEL] range_overlap label=0x0000000456CFF360 range=0x0000000456CFF360+0x8 source=pm4_producer_registered queue=dcb.graphics submission=24 packet=0x0000000442600750 name=write_data dst=0x0000000456CFF360 count=2
  [V73.4][LABEL] range_overlap label=0x0000000456CFF700 range=0x0000000456CFF700+0x8 source=pm4_producer_registered queue=dcb.graphics submission=24 packet=0x00000004426015DC name=write_data dst=0x0000000456CFF700 count=2
  [V73.4][LABEL] range_overlap label=0x0000000456CFF580 range=0x0000000456CFF580+0x8 source=pm4_producer_registered queue=dcb.graphics submission=24 packet=0x000000044260253C name=write_data dst=0x0000000456CFF580 count=2
  [V73.4][LABEL] range_overlap label=0x0000000456CFF4C0 range=0x0000000456CFF4C0+0x8 source=pm4_producer_registered queue=dcb.graphics submission=24 packet=0x0000000442603478 name=write_data dst=0x0000000456CFF4C0 count=2

The first watched graphics label 0x456CFF100 is produced by acb.compute[32]
submission 15. The later dcb.graphics submission 24 contains the WRITE_DATA
producers for the remaining async-compute labels.

CORRECTION
WRITE_DATA still waits for all prior Vulkan work in its current logical guest
queue to complete. It no longer performs WriteBackAllDirtyGuestBuffers before
applying the packet's immediate payload.

The new path is:
  SubmitOrderedGuestActionAfterQueueCompletion

It is added as a safe default method to IGuestGpuBackend, bridged by
VulkanGuestGpuBackend and implemented by VulkanVideoPresenter using an ordered
action with:
  RequireGlobalVisibility = false
  RequiresGpuToCpuVisibility = false
  RequiresQueueCompletionOnly = true

Only ApplySubmittedWriteData selects this path.

UNCHANGED
- V73.3 ordered visibility direction fix
- RELEASE_MEM
- DMA ordering / DMA writeback
- shader global-buffer writeback
- global visibility probes
- ACQUIRE_MEM
- WAIT_REG_MEM comparison
- label values / wake policy
- producer history
- canonical-empty-fastpath
- loader / NID behavior

BASELINE SHA-256 GUARDS
  AgcExports.cs=3F2B5FD1ECF4F7D3715C57E15393190615A1E8EC6FF62F2236FC712FF2D1B4B5
  VulkanVideoPresenter.cs=F5FDDAAB23E192C90A14FA3B88C335903B60A2FFB6960716AEE746A0200B82AA
  VulkanGuestGpuBackend.cs=33E6A4E2424E3FED838C80F884D6EEE527F053A9361F1D0EECF9F3D64427A704
  IGuestGpuBackend.cs=28B49D708282E95F24080478B39D9EDC6183906757F0C473FEFB8E41E4AE45F6

DIAGNOSTIC
The bounded V73.4 provenance channel is retained and extended to record:
- WRITE_DATA packet control + first two immediate payload dwords
- actual WRITE_DATA application
- guest-visible and latched producer value
- actual wait resume event

The diagnostic leaves full AGC/Vulkan tracing disabled.

Result:
  SharpEmu_V73_5_WRITEDATA_PRODUCER_RESULT_<timestamp>.zip
