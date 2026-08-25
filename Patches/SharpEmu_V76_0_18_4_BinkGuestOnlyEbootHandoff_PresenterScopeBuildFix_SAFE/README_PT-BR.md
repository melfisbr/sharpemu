# SharpEmu V76.0.18.4 — Bink Guest-Only Eboot Handoff Presenter Scope BuildFix

Este pacote mantém a implementação funcional V76.0.18:

- `.bk2` permanece hard guest-owned;
- FFmpeg/NihAV/RAD host ficam bloqueados para Bink2;
- `_open` entrega o arquivo original ao guest;
- não existe completion shim/host wait para o Bink guest;
- fechamento do último FD Bink continua o fluxo do eboot sem black-frame host.

## BuildFix V76.0.18.4

A V76.0.18.3 chegou corretamente à build, porém o helper estático `VulkanVideoPresenter.BinkGuestHandoffV7618.cs` referenciava sete campos privados que pertencem à classe interna de instância `Presenter`, gerando CS0103.

O `.4` remove somente essas referências inválidas. O bloqueio host é feito antes, nos entry points e no pump, então esses buffers host por instância não participam do Bink guest-owned.

O pacote continua fazendo backup, apply semântico, build Debug + Release, verify e rollback automático.
