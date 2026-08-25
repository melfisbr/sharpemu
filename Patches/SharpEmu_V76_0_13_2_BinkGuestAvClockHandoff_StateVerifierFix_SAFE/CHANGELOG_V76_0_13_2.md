# V76.0.13.2 — Bink Guest A/V Clock Handoff State Verifier BuildFix

- Corrige falso `markers=1/2` depois do apply da V76.0.13.1.
- O verifier procurava `BeginSession(epoch, path);`, mas o próprio patch escreve uma chamada multilinha com `Volatile.Read(ref _sessionEpoch)`.
- Agora o estado aplicado exige as chamadas semânticas `BinkGuestAvClockV7613.BeginSession(` e `BinkGuestAvClockV7613.EndSession(`.
- O payload C# funcional da V76.0.13 permanece inalterado.
- Rollback e prerequisites V76.0.12.3 permanecem inalterados.

# SharpEmu V76.0.13.2 — Bink Guest A/V Clock + Handoff

## Escopo

Esta etapa mantém o Bink2 **guest-owned**. Não adiciona RAD/Nihav/FFmpeg host, não injeta frames e não substitui o áudio do guest.

## Implementado

- Novo `BinkGuestAvClockV7613` usando `GuestAudioClock` apenas como referência temporal.
- Epoch A/V iniciado no primeiro FD `.bk2` da sessão e encerrado no último close.
- Primeiro produtor Y/UV real pode permanecer em neutral-black por uma janela curta até o áudio guest avançar.
- O handoff não usa `Thread.Sleep`, fence wait ou stall da render thread.
- Timeout padrão do handoff: 180 ms para filmes sem áudio ou áudio que não avançou ainda.
- Threshold padrão para considerar áudio iniciado: 12 ms de progresso após o início da sessão.
- Draws que realmente ligam produtor Y/UV atual recebem epoch + `ContentGeneration`.
- Após `vkQueuePresentKHR`, frames Bink visíveis são contabilizados somente quando o `ContentGeneration` muda.
- Telemetria registra wall clock, guest-audio clock, estimativa de vídeo e skew.
- Após a liberação do primeiro frame, o hot path faz fast-exit via `Volatile.Read` sem lock.

## Variáveis

- `SHARPEMU_BINK_GUEST_AV_SYNC=0` — desabilita somente o novo gate/clock V76.0.13.
- `SHARPEMU_BINK_FIRST_VISUAL_HOLD_MS=0..500` — janela máxima do primeiro handoff; padrão 180.
- `SHARPEMU_BINK_AUDIO_START_THRESHOLD_MS=0..100` — progresso mínimo do áudio; padrão 12.
- `SHARPEMU_BINK_GUEST_TARGET_FPS=1..120` — usado somente na estimativa/telemetria de skew; padrão 30.

## Fora de escopo

- Não descarta ou duplica frames para corrigir skew contínuo.
- Não limpa buffers de áudio guest no fechamento do `.bk2`.
- Não altera scheduler graphics/compute.
- Não altera detile/staging.
- Não altera present mode do swapchain.


## V76.0.13.2 prerequisite/build fix

- Remove dependencia dos textos `[BINK-GUEST][V76.0.12][SESSION] begin/end` no precheck.
- Valida o contrato real de session epoch da V76.0.12.3.
- Rebase do BeginSession para o próprio incremento do primeiro-FD (`Interlocked.Increment(ref _sessionEpoch)`) + `Volatile.Read(ref _sessionEpoch)`, sem segundo teste de contagem.
- Payload `BinkGuestAvClockV7613.cs` permanece byte a byte igual.
