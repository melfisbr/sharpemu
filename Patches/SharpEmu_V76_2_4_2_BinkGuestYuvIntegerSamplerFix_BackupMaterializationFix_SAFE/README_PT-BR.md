# SharpEmu V76.2.4.2 — Bink Guest YUV Integer Sampler Fix / Backup Materialization Fix

BuildFix/ValidatorFix para a V76.2.4.1.

Corrige o caso em que `scripts\patch_target.ps1` calcula e imprime
`SharpEmu_V76_2_4_VALIDATOR_PREVIOUS_<timestamp>.zip`, mas chama
`Expand-Archive` antes de garantir que esse ZIP exista fisicamente em `Patches`.

Este pacote NÃO altera o payload funcional Bink/YUV da V76.2.4.
Ele modifica apenas o validador/reparador da V76.2.4.1 já extraída em `Patches`.

Fluxo:
1. valida este pacote;
2. precheck do pacote V76.2.4.1 local;
3. faz backup do `patch_target.ps1` original em `Patches`;
4. injeta criação atômica + verificação do ZIP de backup antes do `Expand-Archive`;
5. executa novamente o runner da V76.2.4.1 que chama `patch_target.ps1` (ou o script diretamente, se não houver runner detectável);
6. verifica que o reparo permanece instalado.

O backup da V76.2.4 alvo só é considerado válido se `Test-Path` for verdadeiro e o ZIP tiver tamanho não-zero antes de qualquer `Expand-Archive`.
