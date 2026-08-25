# SharpEmu V76.0.11.1 — Parallel Shader Prewarm BuildFix SAFE

BuildFix da V76.0.11 para o erro CS0177 em `AgcExports.ShaderParallelV7611.cs`.

A V76.0.11 original introduziu prewarm SPIR-V em background e compilação paralela VS+PS no Vulkan, mas o fallback sequencial usa curto-circuito (`pixel || vertex`). Se o pixel shader falhar primeiro, o vertex compiler não é chamado e o compilador C# exige que o parâmetro `out vertexShader` já esteja atribuído.

A V76.0.11.1 inicializa `vertexShader = null`, `pixelShader = null` e `error = string.Empty` na entrada do helper. Nenhuma semântica de shader, cache ou scheduling é alterada.

O pacote aceita tanto o baseline V76.0.10.2 restaurado pelo rollback quanto um estado parcial que contenha o helper V76.0.11 buggy, reparando-o in-place.
