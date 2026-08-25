# V76.0.12.2 — Bink Guest YUV/Storage Namespace BuildFix

- Corrige CS0246 em `VulkanVideoPresenter.BinkGuestYuvV7612.cs` adicionando `using SharpEmu.Libs.Gpu;`, namespace real de `GuestDrawTexture`.
- Mantém a lógica YUV/session-epoch da V76.0.12.1 sem mudanças semânticas.
- Reconhece o helper defeituoso da V76.0.12.1 (`39907322...`) como estado reparável e o substitui de forma isolada.
- Mantém rollback para V76.0.11.1 em qualquer falha posterior.

---

# V76.0.12.2

- Adiciona epoch por sessão ao Bink guest-owned.
- Registra o VkImage final Y/UV somente depois de uma escrita storage GPU da sessão atual.
- Rejeita produtores Y/UV inicializados por sessão Bink anterior.
- Suprime upload CPU para os planos finais Y/UV GPU-owned.
- Corrige neutral black de Y=16 para Y=0 no contrato full-range do Bink2.
- Mantém host decoder desabilitado e preserva strict guest GPU ordering existente.


## V76.0.12.2 BuildFix
- Corrige sobrescrita de `$HelperHash` por `$helperHash` (PowerShell é case-insensitive).
- Precheck agora distingue corretamente helper ausente (`ReadyCopy`) de helper aplicado.
- Apply/verify preservam o hash esperado durante toda a execução.
- Payload C# V76.0.12 permanece inalterado.
