# V74.0.117.1.1 — SCRIPT REPAIR SAFE

Este pacote NÃO altera a lógica CPU→GPU Feed/EnvelopeUnclamp da V117.1.

Ele corrige somente o bug PowerShell observado em V117.1:

    Não é possível localizar um parâmetro posicional que aceite
    o argumento 'pending_items'.

## Estratégia

A V117.1.1 localiza a pasta irmã:

    SharpEmu_DemonsSouls_CPUToGPUFeed_EnvelopeUnclamp_REBASED_Fix_V74_0_117_1_SAFE

e repara SOMENTE as linhas de scripts que invocam `patch_envelope.ps1`.

A chamada defeituosa deixa tokens de validação como `pending_items`,
`pending_mb`, etc. escaparem como argumentos posicionais.

O repair:
1. cria backup dos .ps1 alterados em Patches;
2. preserva `-Source <variável> -Out <variável>`;
3. remove apenas argumentos posicionais residuais após o parâmetro `-Out`;
4. valida o parse de todos os PowerShell da V117.1;
5. executa o RUN_2 original;
6. RUN_3/4/5 delegam para a V117.1 original depois do reparo.

Nenhum arquivo em `src\` é modificado por este repair diretamente.
A única modificação no source continua sendo aquela implementada pela própria
V117.1 quando o RUN_3 original finalmente conseguir executar.

RUN_4 continua protegido pelo state/guard original da V117.1.
