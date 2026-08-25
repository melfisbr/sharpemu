# SharpEmu V76.0.18.1 — PrerequisiteFix

Este BuildFix mantém o payload funcional V76.0.18 inalterado e corrige apenas o gate do `BinkGuestAvClockV7613.cs`: hashes conhecidos `07df...` e `4688...` são aceitos, e qualquer outra variante precisa passar pelos contratos semânticos A/V V76.0.13.

# SharpEmu V76.0.18 — Bink2 Hard Guest-Only + Eboot Handoff

Baseline: V76.0.16 FINAL (V76.0.13.2 Bink A/V + V76.0.14/15/16 performance).

Objetivo:
- `.bk2` nunca pode ser tomado por FFmpeg, NihAV, RAD native ou RAD externo.
- `_open` entrega o arquivo Bink original ao guest/eboot, sem completion shim.
- o presenter não bombeia decoder host durante uma sessão Bink guest.
- no `close()` do último FD Bink, limpa apenas estado legado host; não cria frame preto e não espera host.
- preserva `_latestPresentation` e a FIFO guest, permitindo que o fluxo do eboot continue naturalmente.
- compila Debug **e** Release para evitar testar um SharpEmu.exe Debug antigo.

## Evidência esperada no runtime
Deve aparecer:
- `[BINK-GUEST][V76.0.18] hard_guest_only=True host_decoder=False`
- `[BINK-GUEST][V76.0.18][KERNEL-OPEN] ... route=guest-file-fd host_takeover=False completion_shim=False`
- `[BINK-GUEST][V76.0.2][SESSION] begin ... decode_owner=guest`
- `[BINK-GUEST][V76.0.18][EBOOT-HANDOFF] ... no_black=True no_host_wait=True`

Não deve aparecer para `.bk2`:
- `[BINK-FFMPEG] bridge_attached`
- `decoder=FfmpegVideoDecoder`
- `Bink2 NIHAV bridge attached`
- `Bink RAD bridge attached`
- `black_submitted` causado por fechamento do filme guest.

`SHARPEMU_BINK_ALLOW_HOST_DECODER=1` é ignorado por design nesta versão.
