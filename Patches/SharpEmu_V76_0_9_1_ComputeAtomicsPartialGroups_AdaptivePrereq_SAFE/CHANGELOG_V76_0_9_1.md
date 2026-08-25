# SharpEmu V76.0.9.1 — Compute Atomics + Partial Groups / Adaptive V76.0.8 Prerequisite

Build-fix/precheck-fix da V76.0.9. Mantém o payload compute/atomics byte a byte e substitui o gate rígido da V76.0.8 por validação/reparo adaptativo dos quatro contratos V76.0.8.

- preserva bounded CAS para AtomicInc/AtomicDec;
- preserva família FLAT/GLOBAL atomic 32-bit;
- preserva partial thread groups;
- revalida ou reaplica in-place, quando necessário, os quatro patches V76.0.8;
- mantém helper TypedBufferStoreV7608 por hash exato;
- backup/rollback antes de qualquer escrita.
