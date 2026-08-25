# Changelog V76.0.2

## Fixed
- Bink Vulkan default target FPS was 30; now 60.
- Post-Studios handoff barrier only matched `ps_studios_logo.bk2`; now covers attract/intro/logo family.
- Vector float compares failed on F16 variants.
- Vector integer compares failed on I64/U64 variants.
- DPP16 rejected wave shift/rotate controls (0x130–0x13F).
- LDS atomics lacked 64-bit forms used by some compute kernels.
- Buffer atomic name aliases (Xchg / CmpSwap) rejected.

## Added
- `SpirvShaderDiskCache` — persistent SPIR-V blob cache.
- `HostFramePacerV7602` — host-side 60 Hz present pacing.
- `BinkVulkanPacingV7602` — shared Bink pacing / handoff policy.

## Notes
- All new behaviour is opt-out via environment variables (see README).
