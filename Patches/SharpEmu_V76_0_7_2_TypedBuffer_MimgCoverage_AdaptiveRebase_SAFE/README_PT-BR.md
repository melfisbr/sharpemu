# SharpEmu V76.0.7.2 - GFX10 MTBUF D16 + MIMG Adaptive Rebase SAFE

Esta revisao corrige o falso `Divergent` da V76.0.7/7.1. Os quatro arquivos C# alvo nao sao mais validados por hash integral nem substituidos por payload completo.

O precheck exige:
- componentes imutaveis da V76.0.5.1;
- helper exato da V76.0.6.1 (`2c395d53...`);
- marcadores semanticos V76.0.5.1/V76.0.6.1;
- para cada uma das 11 mudancas V76.0.7, ou o marcador final ja deve existir ou a ancora antiga deve existir exatamente uma vez.

O apply:
1. cria backup dos quatro arquivos;
2. aplica somente os 11 trechos MTBUF/MIMG ainda ausentes;
3. valida marcadores;
4. compila Release/win-x64;
5. restaura automaticamente o backup se qualquer etapa falhar.

Escopo funcional e o mesmo da V76.0.7.1: MTBUF opcode 4-bit, familia D16, FORMAT da instrucao, typed-load packing e cobertura MIMG SAMPLE sem MinLod. Typed stores permanecem explicitamente pendentes em vez de raw fallback.
