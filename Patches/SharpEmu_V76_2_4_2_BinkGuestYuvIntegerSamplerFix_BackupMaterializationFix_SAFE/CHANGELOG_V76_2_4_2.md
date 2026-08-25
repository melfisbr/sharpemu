# V76.2.4.2

- Corrige `Expand-Archive : ... VALIDATOR_PREVIOUS_*.zip não existe`.
- Materializa o backup da V76.2.4 em `Patches` antes do restore/inspection.
- Verifica `Test-Path` e tamanho do ZIP.
- Procura de forma segura a pasta alvo V76.2.4 quando o nome exato não estiver presente.
- Faz backup do `patch_target.ps1` da V76.2.4.1 antes de modificá-lo.
- Patch idempotente por marker `V76.2.4.2-BACKUP-MATERIALIZATION`.
- Nenhuma mudança funcional no Bink guest/YUV/sampler.
