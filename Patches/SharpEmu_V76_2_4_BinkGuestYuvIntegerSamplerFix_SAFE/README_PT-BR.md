# SharpEmu V76.2.4 — Bink Guest YUV Integer Sampler Fix SAFE

Escopo cirurgico apos confirmar por runtime que `ps_studios_logo.bk2` esta em guest-only:

- NAO reativa FFmpeg, NihAV ou RAD host.
- NAO converte as storage images Bink de `R8Uint/R8G8Uint` para UNORM.
- Mantem o compute guest escrevendo nos formatos inteiros originais.
- Normaliza apenas o sampler das planes finais Bink tile=5 para nearest/no-mip.
- O neutral Y/UV usado antes do primeiro producer tambem recebe sampler seguro.
- `SHARPEMU_BINK_INTEGER_NEAREST=0` permite A/B sem remover o patch.
- Debug e Release sao compilados; rollback integral em falha.

Runtime esperado:
`[BINK-GUEST][V76.2.4][YUV-SAMPLER] ... guest_mag=... guest_min=... guest_mip=... host_mag=nearest ... changed=...`

Se `changed=1`, o guest estava tentando usar filtro nao-nearest em uma plane inteira e o patch corrige isso.
Se todos os eventos mostrarem `changed=0` e a imagem continuar corrompida, o proximo alvo e o conteudo produzido pelos compute shaders/wave64, nao o sampler.
