SharpEmu V76.3.21.3.1 - Authoritative Closure Sync512 + Guest Progress DEV SAFE
====================================================================================

POR QUE ESTA REVISAO EXISTE
O V76.3.21.3 anterior gravava SHARPEMU_PRODUCER_DEPENDENCY_CLOSURE_SYNC_SCAN=512,
mas o runtime enviado em 2026-08-29 ainda registrou sync_budget=4096. Os demais
controles conservadores (8 slices / 1000 us / chain4) estavam ativos. Portanto a
reversao ficou incompleta na ligacao real do consumidor.

MUDANCA ESTRUTURAL MINIMA
- VulkanVideoPresenter.cs passa a forcar o closure sync scan para 512 somente
  quando o processo e PPSA01341 (Demon's Souls).
- O valor e decidido no proprio consumidor, antes de criar uma closure.
- ModuleInitializer/perfis posteriores nao podem reabrir 4096 para PPSA01341.
- A/B: SHARPEMU_V7632131_DISABLE=1 restaura o comportamento anterior.

NAO MUDA
- WAIT_REG_MEM / WRITE_DATA / RELEASE_MEM.
- dual physical queue / timeline / range hazards.
- Async AGC.
- snapshot bounds V21.2.
- Bink auto boot continua OFF.
- nenhum frame, wait ou fence e fabricado.

RUN_4 DIAGNOSTIC
Ativa apenas probes: scene pipeline gaps, geometry draws e guest-thread snapshots.
O primeiro contrato a conferir e closure_sync_contract_ok=True. Depois, o criterio
funcional continua natural_ps_studios_request=True.
