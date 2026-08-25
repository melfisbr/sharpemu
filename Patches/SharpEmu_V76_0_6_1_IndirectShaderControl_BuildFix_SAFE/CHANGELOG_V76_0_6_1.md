# V76.0.6.1

- BuildFix da V76.0.6 após falha real de compilação.
- Corrige CS0165: `targetAddress` agora é inicializado antes do short-circuit e passado por `out targetAddress`.
- Corrige CS0136: alvo indireto usa `indirectTargetPc`, evitando colisão com `targetPc` declarado pelo tratamento de S_BRANCH.
- Reaplica o escopo funcional da V76.0.6 sobre a V76.0.5.1 após rollback.
- Mantém S_SETPC_B64, S_SWAPPC_B64, CFG indireto, descoberta scalar call/return e S_ASHR_I64.
- SAFE: precheck exige V76.0.5.1; backup + rollback automático em qualquer falha após o primeiro write.
