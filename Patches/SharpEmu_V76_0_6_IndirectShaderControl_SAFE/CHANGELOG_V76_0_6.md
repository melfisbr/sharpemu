# V76.0.6

- Implementa S_SETPC_B64 e S_SWAPPC_B64 no PC-dispatcher SPIR-V.
- Preserva semântica absoluta do PC e retorno de S_SWAPPC_B64.
- Cria granularidade por instrução apenas quando o shader contém controle de fluxo indireto.
- Conservadoriza predecessores de CFG para branches indiretos e preserva binding exato por PC.
- Scalar evaluator passa a seguir alvos indiretos estaticamente resolvíveis.
- Scalar evaluator ganha S_ASHR_I64.
- SAFE: precheck exige V76.0.5.1; backup + rollback automático em qualquer falha após o primeiro write.
