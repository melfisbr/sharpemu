# V76.0.25

- Implementa RDNA2 DS_PERMUTE_B32/DS_BPERMUTE_B32 no decoder e SPIR-V.
- Corrige feature analysis para cross-lane DS sem LDS storage.
- Remove DPP controls silenciosamente tratados como identidade.
- Reverte sample-view UNORM V76.0.24 para identidade UINT guest.
- Desativa BinkDecodePolicyV7623 hybrid host.
- Invalida cache SPIR-V antiga.
