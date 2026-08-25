# SharpEmu V76.0.12 — Bink guest-owned YUV/storage epoch

Baseline exigido: **V76.0.11.1 BUILD + VERIFY**.

Esta etapa mantém o Bink2 title-owned sob controle do guest e corrige a propriedade
das superfícies finais Y/UV Vulkan:

- cada sessão `.bk2` recebe um epoch;
- uma imagem Y/UV inicializada por um filme anterior não pode alimentar o filme atual;
- somente uma storage image escrita pela GPU no epoch atual pode satisfazer o bind final;
- o caminho final Y/UV não cria upload CPU/guest-RAM antes do compute producer;
- o fallback neutro usa Y=0 e UV=128 (Bink2 full-range);
- nenhuma rotina RAD/Nihav/FFmpeg host é habilitada.

`SHARPEMU_BINK_YUV_SESSION_EPOCH=0` desativa somente o gate de epoch para A/B.

Execute RUN_1 -> RUN_2 -> RUN_3 -> RUN_4. Não execute RUN_4 se RUN_3 falhar.
