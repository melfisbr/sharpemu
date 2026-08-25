# V76.0.18.1 PrerequisiteFix

- Não altera o payload C# funcional da V76.0.18.
- Substitui o hash rígido do BinkGuestAvClockV7613 por validação semântica forte.
- Reconhece explicitamente hashes 07df... e 4688....
- Logs/resultados passam a usar V76_0_18_1.

# V76.0.18

- Torna `BinkGuestOwnedRuntimeV7600.Enabled` uma regra hard guest-only.
- Neutraliza `SHARPEMU_BINK_ALLOW_HOST_DECODER` para Bink2.
- Bypass direto do HostMovieBridge no `_open` de `.bk2`.
- Remove completion shim/wait host do fluxo Bink guest.
- Bloqueios redundantes em HostMovieBridge, FFmpeg, NihAV, RAD native e RAD externo.
- Desativa pump host durante sessão `.bk2` guest.
- Novo `VulkanVideoPresenter.BinkGuestHandoffV7618.cs`: limpa apenas estado host legado no fechamento, sem black frame e preservando apresentações guest.
- Build SAFE de Debug e Release.
- Mantém V76.0.16 Vulkan performance e V76.0.12/13 YUV/A-V.
