# V76.2.4.5

- Corrige a falha residual `Split-Path ... '$null'` do runner V76.2.4.1.
- Inicializa `$Patches` sem `Split-Path`, usando os diretórios pais de `$PSScriptRoot`.
- Atualiza o manifest do pacote-alvo após a correção do script.
- Valida sintaxe e ausência do padrão inválido antes de reexecutar o runner.
- Rollback de `patch_target.ps1` e `manifest.sha256` em qualquer falha.
- Não altera diretamente arquivos C# do SharpEmu.
