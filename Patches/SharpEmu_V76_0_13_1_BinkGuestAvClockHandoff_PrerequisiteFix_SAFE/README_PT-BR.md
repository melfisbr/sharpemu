# SharpEmu V76.0.13.1 — Bink Guest A/V Clock + Handoff SAFE

Pré-requisito: **V76.0.12.3 BUILD + SOURCE VERIFY PASSED**.

O objetivo é alinhar o primeiro quadro visível do Bink guest-owned ao início do áudio que o próprio guest entrega ao dispositivo. O SharpEmu não assume decode nem áudio.

Durante uma janela curta, se o produtor Y/UV já existe mas o `GuestAudioClock` ainda não avançou, o presenter usa a textura neutral-black já existente. Não há `Sleep`, espera de fence ou bloqueio da CPU/render thread. Ao detectar progresso de áudio — ou expirar o timeout — o Y/UV real é liberado.

Depois disso, cada `vkQueuePresentKHR` que contém um produtor Bink real informa ao clock o `ContentGeneration`. Repetições do mesmo produtor não são contadas como novos frames, o que evita interpretar refresh/UI a 60 Hz como decode Bink a 60 fps.

Execute `RUN_1` → `RUN_2` → `RUN_3` → `RUN_4`. Se `RUN_3` falhar, o pacote restaura automaticamente os arquivos anteriores.


## BuildFix V76.0.13.1

O prerequisite da V76.0.12.3 agora valida o epoch YUV por semantica (`_sessionEpoch`, `ActiveSessionEpoch`, `YuvSessionEpochEnabled` e incremento de epoch), sem exigir o texto do log `SESSION begin/end`. O hook de `BeginSession` tambem foi rebased para o formato real da V76.0.12.3 e é inserido dentro do bloco que incrementa `_sessionEpoch` no primeiro FD e usa `Volatile.Read(ref _sessionEpoch)`.
