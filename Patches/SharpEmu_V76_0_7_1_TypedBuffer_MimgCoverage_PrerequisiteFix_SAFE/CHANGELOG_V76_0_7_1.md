# SharpEmu V76.0.7.1 — GFX10 MTBUF D16 + MIMG coverage — PrerequisiteFix

## Correção V76.0.7.1

- Corrige exclusivamente o hash de pré-requisito do helper `Gen5SpirvTranslator.IndirectControlV7606.cs`.
- Hash correto instalado pela V76.0.6.1 BuildFix: `2c395d530bffd6a9a998bda73210d13eb8de9fd1a2c75fe14a20486b2e3a5520`.
- O payload C# da V76.0.7 não foi alterado; apenas o gate SAFE e os nomes de logs/resultados foram corrigidos.
- Continua exigindo exatamente a V76.0.6.1 validada antes de aplicar.


## Implementado

- Corrige o decoder GFX10 MTBUF de 3 para 4 bits de opcode.
- Decodifica `TBUFFER_LOAD_FORMAT_D16_{X,XY,XYZ,XYZW}`.
- Decodifica `TBUFFER_STORE_FORMAT_D16_{X,XY,XYZ,XYZW}`.
- Separa quantidade de componentes tipados da quantidade de VGPRs ocupados por D16 packed.
- Usa o `FORMAT` da própria instrução MTBUF para typed loads, em vez do format/dst_sel do descriptor.
- Mantém MUBUF FORMAT usando o descriptor e seu `dst_sel`.
- Empacota resultados D16 em pares de 16 bits por VGPR no caminho geral e no vertex-fetch especializado.
- Corrige binding de vertex input MTBUF para usar formato e component count da instrução.
- Adiciona SAMPLE MIMG não-MinLod: compare, gradients, explicit LOD, bias, LZ e variantes offset representáveis pelo lowering atual.
- Corrige a classificação de `ImageSampleCD*`: compare + derivatives, sem confundir apenas por substring.

## Deliberadamente pendente

`TBUFFER_STORE_FORMAT*` e `TBUFFER_STORE_FORMAT_D16*` agora são decodificados corretamente, mas a conversão inversa de número/formato para bytes guest ainda não é aproximada. O translator retorna erro explícito `typed-buffer store conversion pending` em vez de gravar dwords crus. Essa conversão é o escopo da V76.0.8.

Os SAMPLE com LOD clamp (`*_Cl`) também permanecem pendentes até o plumbing Vulkan de `shaderResourceMinLod`/SPIR-V MinLod.
