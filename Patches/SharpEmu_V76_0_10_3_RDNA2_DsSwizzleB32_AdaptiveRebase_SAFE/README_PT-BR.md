# SharpEmu V76.0.10.3 — RDNA2 DS_SWIZZLE_B32 Adaptive Rebase SAFE

Baseline exato: source apos V76.0.10.2 ShaderCacheCriticalPath SemanticSoppFix.

O PRECHECK anterior encontrou Gen5SpirvTranslator.cs = 5e6492f18bf7ec3042c47dc05d6f097cffae512a96f9f4fb405d99b248e8802a. Esse hash foi reproduzido byte-a-byte aplicando a V76.0.10.2 ao snapshot enviado pelo usuario. Portanto esta versao NAO restaura o translator 8f2052f7... e preserva SClause/SWaitcntDepctr.

Mudanca funcional: implementa DS_SWIZZLE_B32 no backend Vulkan e evita exigir LDS para essa instrucao lane-permute. Nao altera Bink ownership, YUV, Wave64, MTBUF/D16, typed stores, atomics ou shader cache.

Hashes finais:
- Gen5SpirvTranslator.cs = 81f81c1d897afbd03e86c6ad2223a6b3e742c57009a363df9ee6657e4f3f89b5
- Gen5SpirvTranslator.DsSwizzleV7610.cs = 99e575ffd9eab1e275dfa3ad548c5ec994a5f8e1172dfb693270ae4d808a81c1

RUN_3 cria backup/build log/summary/result ZIP em C:\Users\Edpo\Documents\GitHub\sharpemu\Patches. Falha de build restaura o main anterior e remove o helper novo.
