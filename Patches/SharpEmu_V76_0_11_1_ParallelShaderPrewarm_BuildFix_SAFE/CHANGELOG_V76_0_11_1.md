# V76.0.11.1

- Corrige CS0177 em `AgcExports.ShaderParallelV7611.cs`.
- Inicializa todos os parâmetros `out` antes de qualquer caminho com short-circuit.
- Mantém byte a byte o payload de prewarm SPIR-V da V76.0.11.
- Mantém compilação paralela Vulkan VS+PS.
- Aceita e repara o helper V76.0.11 buggy caso esteja presente.
- Rollback automático permanece ativo.
