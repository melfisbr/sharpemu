# SharpEmu V76.0.10.4.1 — RDNA2 DPP/PERMLANE Adaptive Cache Rebase SAFE

Este pacote corrige o PRECHECK da V76.0.10.4 anterior sem reverter o source atual.

## Baseline confirmado pelo runtime do usuario

- `Gen5SpirvTranslator.Alu.cs`: `ea8df89cb52ee9892a00a14f06d3a965bf0518781674af83940f0e0cadb009e8`
- `VulkanShaderBinaryCacheV7605.cs`: `09b7daedf5eab60c1979012d6cf125c9a607623e8df5072f6d487c9907ccbbd3`

O hash do ALU coincide com o baseline esperado. O cache, entretanto, já contém alterações posteriores e por isso NÃO pode ser substituído pelo arquivo antigo da V76.0.10-r1.

## Estratégia desta versão

1. O ALU é substituído pelo payload corrigido de DPP/PERMLANE.
2. O cache atual é preservado byte a byte, exceto pela constante `CacheVersion`, alterada estruturalmente para `V76.0.10.4-r1`.
3. Isso invalida os SPIR-Vs antigos sem apagar ou reverter as demais melhorias do cache atual.
4. O PRECHECK exige exatamente o hash de cache observado no source do usuário antes de qualquer write.
5. Em falha de build, os dois arquivos originais são restaurados automaticamente.

## Correções RDNA2 preservadas

- `V_PERMLANE16_B32` / `V_PERMLANEX16_B32`: `FI` + `BOUND_CTRL` corretos.
- DPP16: source lane inativa com `FI=0` e `BOUND_CTRL=0` suprime a escrita e preserva VDST.
- `BOUND_CTRL=1` continua produzindo zero quando exigido.

Nenhum decoder Bink host, FFmpeg Bink, NihAV, RAD host ou HLE Bink é adicionado.
