# Validação realizada

- 100.005 vetores avaliados para cada uma das quatro instruções.
- Sem divergências entre a fórmula emitida e a semântica de referência.
- Casos extremos incluídos: zero, UINT_MAX, overflow do acumulador e operandos invertidos.
- Implementação adicionada nos backends Vulkan/SPIR-V e Metal/MSL.
- Decoder não foi alterado porque já reconhecia os quatro opcodes.
- O ambiente desta sessão não possui o SDK .NET; o script incluído executa build e testes na máquina do usuário.

Checagens estáticas:
- OK: Vulkan VSadU8
- OK: Vulkan VSadHiU8
- OK: Vulkan VSadU16
- OK: Vulkan VSadU32
- OK: Metal VSadU8
- OK: Metal VSadHiU8
- OK: Metal VSadU16
- OK: Metal VSadU32
- OK: No duplicate Vulkan helper
- OK: No duplicate Metal helper
