SharpEmu — Demon's Souls V74.0.26.2

POR QUE A V74.0.26.1 BLOQUEOU
=============================
AGC: OK. O dry-run localizou o ponto exato.

HostMovieBridge: o pacote exigia um bloco textual específico para transformar
o gate do V31.7.9. O source atual já contém a capacidade V31.7.9, mas o bloco
foi reorganizado por revisões cumulativas, então old=0/new=0.

A V74.0.26.2 NÃO MODIFICA HostMovieBridge.cs.

PRECHECK DE MÍDIA
=================
Em vez de comparar formatação, valida semanticamente os marcadores que o próprio
pacote V31.7.10 usa para considerar V31.7.9 instalado:
- V31.7.9_GUEST_REPLAY_DEDUPE
- TrySuppressV3179GuestBootReplay
- bink2.guest_replay_deduped
- bink2.guest_boot_reconciliation_completed
- SHARPEMU_BINK_DEDUPE_HOST_BOOT_REPLAY
- os três nomes canônicos de bootstrap

RUN_4 define:
SHARPEMU_BINK_DEDUPE_HOST_BOOT_REPLAY=1

Isso usa a capacidade existente sem reescrever o media bridge.

AGC
===
Entrada exata:
C8721E522DA5240C0BB30FF71E134DFCF3F1AB832571080A3632AA54BF4B9CDC

Payload corrigido:
BDA0ACF6EF270F108628682ED890786AF2A1119E59F3A4E55853F427ED09E804

V74.0.26 no WRITE_DATA continua igual: apenas o caminho
packetPositionWriteV74025 usa SubmitOrderedGuestActionWithVisibility(..., false).

O presenter atual prova que esse overload:
- permanece no guest-work queue;
- para requiresGpuToCpuVisibility=false faz FlushBatchedGuestCommands();
- executa a action sem WaitForFences/WriteBackAllDirtyGuestBuffers.

RESULT
======
Além dos logs, RUN_4 copia HostMovieBridge_CURRENT.cs inteiro, permitindo uma
auditoria byte-a-byte posterior sem novo coletor.
