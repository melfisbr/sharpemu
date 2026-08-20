SharpEmu V74.0.75 - Processing Flow / Texture + Wait Wake SAFE

Objetivo
========
Corrigir o fluxo de processamento indicado pelo log do Demon's Souls sem aumentar artificialmente threads, capacidade de fila ou timeouts.

Correcoes
=========
1. Pre-snapshot sampler alias
   - Se o presenter ja possui a mesma imagem Vulkan com outro sampler, o AGC deixa de copiar/detilhar os texels antes de descobrir o alias.
   - Se V74.0.56.33.2 ja estiver aplicada, ela e preservada e nao e embrulhada novamente.

2. Full-overwrite texture snapshot
   - Buffers baseados em physicalSourceByteCount usam GC.AllocateUninitializedArray<byte>.
   - TryReadTextureGuestMemory sobrescreve o buffer inteiro antes do uso; portanto o zero-fill previo do CLR era trabalho desperdicado.

3. Producer signal -> coalesced drain
   - SignalGpuWaitMonitor passa a requisitar o drain ja existente quando ha um contexto de waiter ativo.
   - Nao cria/fabrica valor, fence ou satisfacao: GpuWaitRegistry continua sendo a autoridade da comparacao WAIT_REG_MEM.

4. Gate-owner drain coalescing
   - Se a thread atual ja possui gpuState.Gate, RequestResumableDcbDrain apenas marca DrainPending.
   - O parser ja chama TryDrainPendingWaitersOnGateOwnerV74072 entre pacotes; nao se inicia outra thread apenas para bloquear no mesmo Gate.

5. Drain context lifecycle
   - EnsureGpuWaitMonitor registra um CpuContext reutilizavel para callbacks de GPU writeback/visibility.
   - O contexto e liberado quando nao existem mais waiters.

Seguranca
=========
- Sem gate rigido por SHA.
- Precheck estrutural.
- Backup dos dois arquivos antes da primeira alteracao.
- Rollback automatico se o build falhar.
- RUN_ROLLBACK_LAST.cmd para restauracao manual.

Arquivos alterados
==================
src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs
src\SharpEmu.Libs\Agc\AgcExports.cs

Resultados/logs
===============
Todos os logs e ZIPs sao gravados em C:\Users\Edpo\Documents\GitHub\sharpemu\Patches.
