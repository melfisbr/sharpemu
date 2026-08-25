# CHANGELOG V76.0.9

- Corrige DS/BUFFER/GLOBAL/FLAT/IMAGE atomic INC/DEC para respeitar o operando DATA (wrap/clamp), via CAS loop SPIR-V.
- Expande decoder FLAT/GLOBAL atomic 32-bit: SWAP, CMPSWAP, ADD, SUB, SMIN, UMIN, SMAX, UMAX, AND, OR, XOR, INC e DEC.
- Global atomics passam pelo mesmo lowering generico usado pelos demais atomics.
- PARTIAL_TG_EN deixa de ser rejeitado quando representavel: o Vulkan despacha o ultimo workgroup completo e o shader desativa invocacoes alem do limite exato.
- USE_THREAD_DIMENSIONS preserva os limites exatos do packet e nao e bloqueado por halves parciais stale.
