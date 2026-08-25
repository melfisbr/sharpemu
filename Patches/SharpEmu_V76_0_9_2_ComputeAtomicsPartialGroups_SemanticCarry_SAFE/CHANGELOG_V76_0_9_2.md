# SharpEmu V76.0.9.2

Build-gate fix sobre V76.0.9.1.

- Remove a dependencia do bloco textual historico `v8_03_format_store_dispatch`.
- Detecta o dispatch `EmitBufferFormatStoreV7608` semanticamente.
- Se a chamada sumiu, localiza estruturalmente o caminho generico `BufferStoreDword` e reinsere o dispatch typed antes dele.
- Remove somente o fallback `BufferStoreFormat` do caminho raw-dword e o antigo `typed-buffer store conversion pending`, quando presentes.
- Mantem byte a byte o payload V76.0.9 de atomics/partial groups e o helper CAS.
- Nenhuma escrita ocorre no RUN_2; reparo so acontece depois de backup no RUN_3.
