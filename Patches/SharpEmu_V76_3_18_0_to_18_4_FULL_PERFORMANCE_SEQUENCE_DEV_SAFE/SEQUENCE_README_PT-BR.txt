Sequencia V76.3.18.0 -> V76.3.18.4

1. 18.0: dual VkQueue real por capacidade + timeline/range hazard + CB pool 256.
2. 18.1: working set residente/caches maiores, usando RAM/VRAM disponivel sem forcar ownership.
3. 18.2: waits producer-driven; full scan somente watchdog 64ms.
4. 18.3: pool thread-local dos containers temporarios do shader frontend.
5. 18.4: metrica final separa guest_fps de host_media_fps.

IMPORTANTE:
- Build Debug em todas as etapas.
- Nenhum diagnostico/jogo e executado nas etapas 18.0-18.3.
- O jogo e executado apenas no final, pela 18.4.
- Bink/FFmpeg host nao e usado como FPS do guest.
- Cada RUN_3 tem backup/rollback proprio quando aplicavel.
