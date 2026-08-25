# SharpEmu V76.0.10.1 — Shader Cache Critical Path Validation BuildFix

Baseline: V76.0.9.3 confirmada por BUILD + SOURCE VERIFY.

## Implementações
- Bump do namespace/chave do cache SPIR-V para V76.0.10-r1, impedindo reuso de binários antigos gerados antes das correções V76.0.7–V76.0.9.3.
- Diretório de disco novo `ShaderCache/V76.0.10`.
- Chave deixa de incluir telemetria/cache-only e mantém somente switches que podem alterar semântica do shader.
- Persistência de `.spv` sai do caminho síncrono de compilação e passa por uma fila única de ThreadPool.
- Vulkan aceita `S_CLAUSE` como hint de scheduling host-irrelevante.
- Vulkan aceita `S_WAITCNT_DEPCTR` como wait de scoreboard host-irrelevante; não é convertido em memory barrier.
- Metal recebe o mesmo tratamento para `S_WAITCNT_DEPCTR` por paridade.

O pacote cria backup antes da primeira alteração e faz rollback automático se o build falhar.


## BuildFix V76.0.10.1
- Corrige falso positivo do RUN_1: `validate.ps1` não varre mais a si próprio contra os tokens literais de downloader que compõem sua própria regra.
- A auditoria de rede continua ativa para todos os demais `.ps1`, `.cmd` e `.md`.
- Payload C# e semântica V76.0.10-r1 permanecem byte a byte inalterados.
