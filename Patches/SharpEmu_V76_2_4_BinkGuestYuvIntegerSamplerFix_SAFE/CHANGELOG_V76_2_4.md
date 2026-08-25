# CHANGELOG V76.2.4

- Adiciona `VulkanVideoPresenter.BinkGuestSamplerV7624.cs` como partial do `Presenter` correto.
- Preserva `R8Uint/R8G8Uint` para o decode/storage guest.
- Forca nearest/no-mip apenas no sample das planes finais Bink Y/UV tile=5.
- Aplica a mesma normalizacao ao neutral frame YUV.
- Telemetria inclui filtros guest originais e `changed=0/1`.
- Mantem V76.0.18 hard guest-only e eboot handoff.
- Builds Debug + Release obrigatorias.
