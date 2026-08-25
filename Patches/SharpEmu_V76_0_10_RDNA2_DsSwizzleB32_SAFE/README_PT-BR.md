# SharpEmu V76.0.10 — RDNA2 DS_SWIZZLE_B32 SAFE

Baseline exato: snapshot `SharpEmu_CURRENT_SRC_V76_0_9_3_PLUS_20260824_160938.zip` enviado pelo usuario e compilado com 0 erros.

## Correcao
O decoder Gen5 ja reconhecia `DsSwizzleB32` (DS opcode 0x35), mas o backend Vulkan nao possuia lowering para essa instrucao. Ela caia em `unsupported LDS opcode DsSwizzleB32`.

Segundo a ISA RDNA2, DS_SWIZZLE_B32 nao le nem grava LDS: e uma operacao de permuta de lanes e funciona independentemente em cada grupo de 32 lanes. A V76.0.10 implementa:

- FFT mode (`offset >= 0xE000`)
- rotate mode (`0xC000 <= offset < 0xE000`), incluindo direction e mask
- quad-permute mode (`offset < 0xC000` e bit15=1)
- bitmask mode (`offset < 0xC000` e bit15=0): `j = ((i & AND) | OR) ^ XOR`
- leitura de source lane inativa retorna 0
- destination lane inativa preserva o VGPR anterior via StoreV/EXEC
- wave64 preserva a regra RDNA2 de duas metades independentes de 32 lanes

Tambem deixa de marcar um shader que usa somente DS_SWIZZLE_B32 como consumidor de LDS real.

Nao altera Bink ownership, YUV, MTBUF/D16, atomics, partial thread groups, AGC, scheduler ou VideoOut.

## Uso
Execute RUN_1 -> RUN_2 -> RUN_3 -> RUN_4. O RUN_3 cria backup/build log/summary/result ZIP em `C:\Users\Edpo\Documents\GitHub\sharpemu\Patches` e restaura o source se o build falhar.
