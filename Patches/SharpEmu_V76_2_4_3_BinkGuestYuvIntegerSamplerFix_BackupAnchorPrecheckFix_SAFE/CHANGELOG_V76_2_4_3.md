# V76.2.4.3

- Corrige falso PRECHECK FAILED quando `patch_target.ps1` possui 2 restores legítimos por `$backupZip`.
- Troca a regra `Count -eq 1` por `Count -ge 1`.
- Seleciona explicitamente o primeiro restore como ponto de inserção do fix V76.2.4.2.
- Registra quantidade total de restore sites e linha da primeira âncora no contexto de precheck.
- Preserva integralmente a lógica funcional Bink guest/YUV/integer sampler da V76.2.4.
- Mantém o marker funcional `V76.2.4.2-BACKUP-MATERIALIZATION` para idempotência.
