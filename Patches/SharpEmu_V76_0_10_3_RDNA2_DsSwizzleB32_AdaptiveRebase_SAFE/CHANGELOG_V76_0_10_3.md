# V76.0.10.3

- Rebase do DS_SWIZZLE_B32 sobre Gen5SpirvTranslator.cs hash 5e6492f1..., estado posterior a V76.0.10.2.
- Preserva S_CLAUSE / S_WAITCNT_DEPCTR semantic no-op coverage e shader-cache critical path.
- Implementa DS_SWIZZLE_B32 Vulkan via subgroup shuffle para quad/bitmask/rotate/FFT.
- DS_SWIZZLE_B32 deixa de exigir LDS e deixa de marcar usesLds.
- Sem host Bink decoder; sem alteracao de YUV/MTBUF/atomics.
