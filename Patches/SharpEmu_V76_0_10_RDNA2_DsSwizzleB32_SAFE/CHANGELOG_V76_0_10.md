# V76.0.10

- Implementa lowering Vulkan de RDNA2 `DS_SWIZZLE_B32`.
- Implementa os quatro modos descritos pela ISA: FFT, rotate, quad-permute e bitmask-permute.
- Mantem a permuta limitada a cada metade de 32 lanes da wave64.
- Respeita EXEC para source/destination lane validity.
- Remove DS_SWIZZLE_B32 da deteccao de uso real de LDS.
- Baseline por SHA-256 exato do source atual do usuario.
