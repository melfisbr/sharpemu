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
