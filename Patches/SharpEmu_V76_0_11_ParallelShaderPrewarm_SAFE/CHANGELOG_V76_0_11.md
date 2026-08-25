# V76.0.11

- SPIR-V persisted-cache prewarm em ThreadPool, atrasado 100 ms para nao disputar o inicio imediato.
- Prioriza `.spv` recentes, valida estruturalmente cada modulo e respeita caps de entradas/bytes.
- Nao altera `CacheVersion`: V76.0.10-r1 permanece compativel.
- VS e PS de um mesmo graphics cache miss podem traduzir em paralelo no Vulkan.
- Metal e opt-out Vulkan continuam no fluxo sequencial anterior.
- Nenhum cambio no Vulkan pipeline cache: a persistencia existente ja esta integrada em `VulkanVideoPresenter`.
