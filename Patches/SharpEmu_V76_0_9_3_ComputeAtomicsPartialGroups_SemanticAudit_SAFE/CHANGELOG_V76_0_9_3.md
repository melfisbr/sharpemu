# SharpEmu V76.0.9.3

Prerequisite-gate fix sobre V76.0.9.2.

- `v8_04_d16_narrow_integer_kind` passa a ser auditoria semantica, nao anchor textual.
- Bloqueia explicitamente somente `Equal(numberFormat, UInt(4/5))`, a forma comprovadamente incorreta.
- Aceita narrowing D16 refatorado/renomeado sem exigir `var isUint/isSint` ou spelling exato.
- Mantem o reparo semantico `v8_03` para `EmitBufferFormatStoreV7608`.
- Mantem byte a byte os 9 patches V76.0.9 e o helper CAS de atomics.
- Nenhuma escrita ocorre no RUN_2; RUN_3 continua com backup e rollback automatico.
