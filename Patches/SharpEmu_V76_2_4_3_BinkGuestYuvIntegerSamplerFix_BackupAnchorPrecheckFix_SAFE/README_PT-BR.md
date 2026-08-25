# SharpEmu V76.2.4.3 — Bink Guest YUV Integer Sampler Fix / Backup Anchor Precheck Fix

BuildFix/PrerequisiteFix da V76.2.4.2.

A V76.2.4.2 corrigiu a materialização do ZIP `SharpEmu_V76_2_4_VALIDATOR_PREVIOUS_<timestamp>.zip`, mas seu precheck exigia que o `patch_target.ps1` da V76.2.4.1 contivesse exatamente uma ocorrência de `Expand-Archive -LiteralPath $backupZip`.

O script real da V76.2.4.1 contém **duas ocorrências legítimas**:

1. rollback se a entrada `scripts\validate.ps1` no manifest não for encontrada exatamente uma vez;
2. rollback se o `RUN_1` original continuar falhando.

A V76.2.4.3 passa a aceitar um ou mais restore sites e seleciona deterministicamente o **primeiro** como ponto de inserção da materialização. Uma vez criado e validado, o mesmo ZIP de backup é reutilizável pelo segundo rollback.

Este pacote **não altera o payload funcional Bink guest/YUV/integer sampler** da V76.2.4. Ele apenas corrige o reparador/validador V76.2.4.2.

Fluxo:
1. valida este pacote;
2. precheck do `patch_target.ps1` V76.2.4.1;
3. aceita `Expand-Archive $backupZip` count >= 1;
4. injeta o materialization fix V76.2.4.2 antes do primeiro restore;
5. reexecuta o runner original V76.2.4.1;
6. verifica marker, materialização e política de âncora.
