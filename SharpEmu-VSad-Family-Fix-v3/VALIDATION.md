# Validação

- Pacote verificado com a pasta `src` presente.
- 100.005 vetores determinísticos avaliados.
- Casos de zero, UINT_MAX, overflow e operandos invertidos.
- Implementações Vulkan/SPIR-V e Metal/MSL incluídas.
- O ambiente atual não possui o SDK .NET; build e testes ficam no script.

## Checagens estáticas

- OK: Vulkan VSadU8
- OK: Vulkan VSadHiU8
- OK: Vulkan VSadU16
- OK: Vulkan VSadU32
- OK: Metal VSadU8
- OK: Metal VSadHiU8
- OK: Metal VSadU16
- OK: Metal VSadU32
- OK: Único helper Vulkan U8
- OK: Único helper Metal U8
