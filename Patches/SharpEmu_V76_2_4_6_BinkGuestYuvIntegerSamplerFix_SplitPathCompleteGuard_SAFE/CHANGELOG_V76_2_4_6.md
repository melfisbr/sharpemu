# V76.2.4.6

- Corrige a falha residual `Split-Path ... argumento '$null'` da V76.2.4.5.
- Troca detecção textual por detecção de `CommandAst` real.
- Reescreve todas as chamadas `Split-Path` do pacote-alvo para wrapper null-safe.
- Evita `2>&1 | Tee-Object` com `$ErrorActionPreference=Stop` ao executar `.cmd`; usa `Start-Process` com stdout/stderr redirecionados.
- Atualiza hashes do `manifest.sha256` do pacote-alvo para scripts modificados.
- Rollback automático dos scripts + manifest se o runner alvo retornar erro.
