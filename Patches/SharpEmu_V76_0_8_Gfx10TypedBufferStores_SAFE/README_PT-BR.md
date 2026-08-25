# V76.0.8 - GFX10 Typed Buffer Stores + MUBUF D16

Baseline exigido: V76.0.7.2 validada.

Este pacote e adaptativo/in-place: nao substitui Gen5ShaderTranslator.cs nem Gen5SpirvTranslator.cs inteiros. Ele exige as ancoras semanticas da V76.0.7.2, faz backup antes do primeiro write e restaura o baseline se a build falhar.

Escopo principal:
- BUFFER_LOAD/STORE_FORMAT_D16_X/XY/XYZ/XYZW (MUBUF opcodes 0x80-0x87);
- TBUFFER_STORE_FORMAT_* e TBUFFER_STORE_FORMAT_D16_* com conversao de formato;
- BUFFER_STORE_FORMAT_* e BUFFER_STORE_FORMAT_D16_* com FORMAT + dst_sel do SRD;
- unpack D16 low/high;
- conversao inversa para formatos normalizados, scaled, integer, f16/f32 e UFLOAT 10/11-bit;
- correcao da classificacao UINT/SINT no narrowing D16 de loads.

RUN_4 deve ser executado somente depois de RUN_3 mostrar BUILD PASSED.
