# SharpEmu — Controller Options and Warning Fix v2

Esta revisão inclui as novas chaves `Options.InputMode.*` em todos os 15 arquivos de idioma incorporados, corrigindo o teste `EmbeddedLanguages_ContainEveryEnglishOptionsKey`.

Também mantém:
- opção de entrada global e por jogo;
- integração GUI → `SHARPEMU_INPUT_MODE` → `scePad`;
- correção dos quatro avisos de compilação;
- backup, build e execução dos testes.

Execute na raiz do repositório:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\SharpEmu-Controller-Options-And-Warnings-Fix-v2\apply_and_validate.ps1 -RepositoryRoot $PWD
```
