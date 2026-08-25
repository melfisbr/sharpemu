# SharpEmu V76.0.9.2 - Compute Atomics / Partial Groups / Semantic Carry

Continua sobre o baseline V76.0.8 validado. Esta revisao corrige o gate do prerequisite typed-store: o arquivo `Gen5SpirvTranslator.cs` nao precisa mais conter o bloco textual exato da V76.0.8.

Se `EmitBufferFormatStoreV7608` estiver presente, o prerequisite e aceito. Se a chamada estiver ausente, mas o caminho generico `BufferStoreDword` for localizado de forma inequivoca, o RUN_3 reinsere o dispatch typed imediatamente antes dele, remove o fallback raw para `BufferStoreFormat` e entao valida novamente a V76.0.8 antes de instalar a V76.0.9.

O RUN_2 nunca escreve no source. RUN_3 cria backup antes de qualquer alteracao e faz rollback automatico se reparo, apply, verify ou build falharem.
