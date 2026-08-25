# SharpEmu V76.0.9.3 - Compute Atomics / Partial Groups / Semantic Audit

Continua sobre o baseline V76.0.8 validado. Esta revisao corrige o ultimo falso negativo do prerequisite V76.0.8: `v8_04_d16_narrow_integer_kind` nao depende mais do bloco textual historico nem dos nomes locais `isUint`/`isSint`.

A regra V76.0.9.3 bloqueia somente a regressao semanticamente conhecida e incorreta: `Equal(numberFormat, UInt(4))` ou `Equal(numberFormat, UInt(5))`, que compara contra um ID SPIR-V em vez do valor 4/5. Qualquer implementacao refatorada que nao contenha essa forma errada e aceita; a compilacao C# real continua sendo o gate final.

O prerequisite `v8_03_format_store_dispatch` continua com reparo semantico seguro. O payload V76.0.9 de atomics/partial-groups permanece inalterado. RUN_2 nunca escreve no source; RUN_3 cria backup antes de qualquer mutacao e faz rollback automatico em qualquer falha.
