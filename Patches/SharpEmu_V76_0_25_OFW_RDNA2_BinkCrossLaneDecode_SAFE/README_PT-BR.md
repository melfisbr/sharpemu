# SharpEmu V76.0.25 — OFW/RDNA2 Bink Cross-Lane Decode SAFE

Este pacote corrige o caminho correto do Bink2 no PS5: o código RAD do título permanece no guest e executa kernels AGC/RDNA2. Nenhum decoder FFmpeg/NihAV/RAD host é ativado.

Implementações:
- GFX10/RDNA2 opcode 0xB2 `DS_PERMUTE_B32` (scatter dentro de meia-wave de 32 lanes).
- GFX10/RDNA2 opcode 0xB3 `DS_BPERMUTE_B32` (gather dentro de meia-wave de 32 lanes).
- EXEC respeitado no source e destination; leitura de source desabilitado retorna zero; índice usa bits [6:2] e wrap de 32 lanes.
- Essas instruções não exigem alocação LDS, conforme arquitetura RDNA2.
- DPP16: remove faixas que eram declaradas suportadas mas caíam silenciosamente em `src=self`.
- V76.0.24: desativa o alias de sample UNORM; o composite volta a usar o mesmo tipo UINT declarado pelo descriptor guest/SPIR-V.
- V76.2.3 hybrid host policy: desativada em source.
- SPIR-V cache generation: `V76.0.25-rdna2-crosslane-r1`, garantindo recompilação dos kernels.
- Build Debug + Release; rollback integral se qualquer build falhar.

Base técnica: audits OFW do usuário mostram AGC/VideoOut e não um serviço Sony Bink2; o runtime atual confirma `decode_owner=guest`, STRICT-COMPUTE e producers Y/UV. A semântica DS_PERMUTE/BPERMUTE segue o RDNA2 ISA da AMD.

O pacote não contém firmware, SDK proprietário ou binários RAD.
