SharpEmu — Demon's Souls V74.0.26.3

MUDANÇA DE ESTRATÉGIA DE MÍDIA
==============================
V74.0.26.1 e .2 falharam no PRECHECK porque tentavam reconhecer uma forma
específica do replay-dedupe V31.7.9 no HostMovieBridge acumulado.

O teste recente JobPoolLanePacking já fornece uma solução mais simples:
HOST_AUTO_BOOT=OFF

Nesse teste:
NATURAL_GUEST_MOVIE_COUNT=1
NATURAL_GUEST_MOVIES=ps_studios_logo.bk2
BINK_ATTACH_COUNT=1
BINK_ATTACH_FILES=ps_studios_logo.bk2
BINK_COMPLETED_COUNT=1
BINK_COMPLETED_FILES=ps_studios_logo.bk2
MAIN_LOOP_SECONDS=18.2678
GATHER_SECONDS=30.7454
DEVICE_LOST_HITS=0

Portanto o EBOOT sabe pedir o PlayStation Studios sozinho. Pré-executá-lo no
host é o que cria a duplicação.

V74.0.26.3 NÃO ALTERA HostMovieBridge.cs.

RUN_4 usa:
SHARPEMU_BINK_AUTO_BOOT=0
SHARPEMU_BINK_STARTUP_COMPLETION_SHIM=1
SHARPEMU_BINK_BOOT_SEQUENCE removida
SHARPEMU_BINK_DEDUPE_HOST_BOOT_REPLAY removida

Assim não há nada para deduplicar: a sequência pertence ao guest.

WRITE_DATA
==========
A correção AGC continua exatamente a já validada:

entrada:
C8721E522DA5240C0BB30FF71E134DFCF3F1AB832571080A3632AA54BF4B9CDC

saída:
BDA0ACF6EF270F108628682ED890786AF2A1119E59F3A4E55853F427ED09E804

packetPositionWriteV74025 passa a usar ordered action com
requiresGpuToCpuVisibility:false.

REFERÊNCIA DE WAIT ANTERIOR
===========================
wall_seconds=712.39
wait_max_ms=7386.486
wait_over_1s=29
wait_over_4s=26

RUN_4 mede novamente esses números junto com:
auto_boot_order_reports
direct_boot_markers
natural_guest_movie_count
ps_studios_attach_count
ps_studios_completed_count

Esperado:
auto_boot_order_reports=0
direct_boot_markers=0
ps_studios_attach_count=1
