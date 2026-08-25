# V76.2.4.4

- Corrige `$Patches == $null` em `SharpEmu_V76_2_4_1_BinkGuestYuvIntegerSamplerFix_ValidatorPathFix_SAFE\scripts\patch_target.ps1`.
- Injeta raiz determinística:
  `$v7624PatchesRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)`
- Substitui chamadas `Join-Path $Patches` por `Join-Path $v7624PatchesRoot`.
- Mantém backup/rollback do script alvo.
- Reexecuta o runner original V76.2.4.1 após a correção.
