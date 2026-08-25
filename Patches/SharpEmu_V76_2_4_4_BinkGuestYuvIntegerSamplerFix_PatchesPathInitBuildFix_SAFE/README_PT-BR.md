# SharpEmu V76.2.4.4 — Patches Path Init BuildFix

Este pacote corrige exclusivamente o instalador/validator da V76.2.4.1/V76.2.4.3.

Problema corrigido:
`patch_target.ps1` chama `Join-Path $Patches ...`, mas `$Patches` pode estar nulo no escopo em que
o runner original é executado.

A V76.2.4.4 torna o script alvo autossuficiente:
- deriva a raiz `Patches` a partir de `$PSScriptRoot`;
- usa `$v7624PatchesRoot` em vez de depender de `$Patches`;
- preserva o runner funcional original;
- faz backup do `patch_target.ps1` antes da alteração;
- restaura o script alvo se o runner original falhar.

Este BuildFix NÃO altera o source funcional do integer sampler por conta própria.
