# SharpEmu V76.0.24 — Bink Guest YUV Normalized Sample View SAFE

Corrige a corrupção visual verde/rosa observada após o Bink2 passar a ser
decodificado pelo próprio guest.

Escopo:
- mantém Bink2 hard guest-only;
- mantém storage decode em R8Uint/R8G8Uint;
- cria apenas a VIEW de amostragem final como R8Unorm/R8G8Unorm;
- usa o mesmo VkImage MUTABLE_FORMAT; não há cópia CPU;
- FFmpeg/NihAV/RAD host continuam bloqueados para .bk2;
- preserva o handoff V76.0.18;
- Debug + Release obrigatórios;
- rollback automático em falha.

A/B:
- padrão: SHARPEMU_BINK_YUV_NORMALIZED_SAMPLE_VIEW=1
- compatibilidade anterior: SHARPEMU_BINK_YUV_NORMALIZED_SAMPLE_VIEW=0

Marker esperado:
[BINK-GUEST][V76.0.24][YUV-SAMPLE-VIEW]
