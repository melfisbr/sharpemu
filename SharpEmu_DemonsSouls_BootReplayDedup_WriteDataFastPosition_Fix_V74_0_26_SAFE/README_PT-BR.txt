SharpEmu — Demon's Souls V74.0.26

CONFIRMADO NO RESULT V73.0.22.1
- wall_seconds=712.39
- stderr_lines=3067
- runtime_unresolved=0
- device_lost=0
Portanto os ~12 minutos são um gargalo real, não overhead do trace anterior.

VÍDEO PLAYSTATION STUDIOS DUPLICADO
O log prova: direct boot exibiu ps_studios_logo.bk2; depois do
bink2.direct_boot_completed o guest abriu naturalmente o mesmo arquivo e o RAD
foi iniciado novamente.

A reconciliação V31.7.9 já existe, mas exigia
SHARPEMU_BINK_DEDUPE_HOST_BOOT_REPLAY=1.
V31.7.11 torna esse dedupe estreito padrão. Valor 0 continua sendo opt-out.

WAIT/WRITE_DATA
O RESULT teve 261 WAIT_RESUME:
- max 7386.486 ms
- média 561.422 ms
- >=1s: 29
- >=4s: 26

V74.0.25 pretendia evitar GPU readback no WRITE_DATA packet-position, mas
SubmitOrderedGuestAction() usa RequiresGpuToCpuVisibility=true por padrão.
V74.0.26 usa SubmitOrderedGuestActionWithVisibility(..., false) somente nesse
caminho opt-in.

AGC exato de entrada:
C8721E522DA5240C0BB30FF71E134DFCF3F1AB832571080A3632AA54BF4B9CDC

AGC exato corrigido:
BDA0ACF6EF270F108628682ED890786AF2A1119E59F3A4E55853F427ED09E804

Esperado no RUN_4:
ps_studios_rad_attaches_total=1
ps_studios_rad_attaches_post_direct=0
guest_replay_deduped>=1
e queda forte em wait_max_ms / wait_over_4s.
