# SharpEmu V76.0.16-FINAL-VULKAN-PERFORMANCE-CONSOLIDATED

Pacote SAFE cumulativo para o baseline **V76.0.13.2 BUILD + VERIFY PASSED**.
Ele consolida todas as implementações funcionais restantes do plano V76:

- **V76.0.14 — Detile + staging/upload pools**
  - host-visible detile buffers persistentemente mapeados;
  - elimina map/unmap por upload no detile;
  - size classes para evitar power-of-two excessivo em buffers grandes;
  - mesma política aplicada aos pools host/device do presenter;
  - lifetime/fence retirement existente continua responsável pelo reuso seguro.

- **V76.0.15 — Graphics ↔ async-compute**
  - segunda fila física passa a ser o caminho padrão quando realmente suportada;
  - `SHARPEMU_DUAL_PHYSICAL_QUEUE=0` restaura o caminho antigo;
  - sincronização cross-queue passa a usar hazards dos recursos guest;
  - read-after-write / write-after-read / write-after-write esperam o timeline exato;
  - lane switches sem dependência de recurso deixam de esperar toda a fila oposta;
  - fallback conservador permanece para submits sem recursos rastreáveis;
  - present espera apenas o compute produtor da imagem/recurso apresentado quando rastreável.

- **V76.0.16 — Presenter / present-mode / frame pacing**
  - seleção explícita `auto|fifo|mailbox|immediate` via `SHARPEMU_VK_PRESENT_MODE`;
  - `auto` preserva FIFO como fallback garantido, prefere MAILBOX com VSync e IMMEDIATE quando VSync/FG exigem baixa latência;
  - latest-ready collapse no queue interno quando há backlog de flips prontos;
  - Bink guest-owned fica excluído do collapse para preservar o clock A/V V76.0.13;
  - `SHARPEMU_PRESENT_LATEST_READY=0` desliga o collapse para A/B;
  - threshold default 3 (`SHARPEMU_PRESENT_LATEST_READY_THRESHOLD`).

## Escopo deliberado

O source já possui um `Presenter` de instância sob a facade estática e já possui `VkPipelineCache` persistente. Portanto este pacote **não faz uma reescrita monolítica** só para mudar a forma externa da classe e não duplica pipeline cache. Ele completa o equivalente funcional pendente com helpers isolados e hooks pequenos.

## Segurança

- nenhum arquivo grande é substituído integralmente;
- 29 patches in-place (15 presenter + 14 detile), cada um deve estar `Ready` ou `Applied`;
- 4 helpers novos verificados por SHA-256;
- prerequisite V76.0.13.2 validado semanticamente;
- backup antes da primeira alteração;
- rollback automático em erro de apply ou build;
- logs, backup e ZIP de resultado em `C:\Users\Edpo\Documents\GitHub\sharpemu\Patches`.

## Execução

Execute `RUN_1` → `RUN_2` → `RUN_3` → `RUN_4`, nessa ordem. Não execute `RUN_4` se `RUN_3` falhar.
