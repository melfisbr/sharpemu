# SharpEmu V76.0.6 — Indirect Shader Control SAFE

Base obrigatória: V76.0.5.1 aplicada e verificada.

Esta etapa fecha o controle de fluxo SOP1 indireto que ainda faltava no tradutor Gen5/Vulkan:

- S_SETPC_B64: PC recebe o endereço absoluto contido no par SGPR fonte.
- S_SWAPPC_B64: salva PC+4/PC+instruction-size no par SGPR destino e salta ao endereço fonte.
- O dispatcher Vulkan continua usando índice de bloco; somente shaders que contêm indirect-PC são divididos em blocos por instrução.
- Alvos fora do programa não criam loop infinito: caem no default do dispatcher e encerram a invocação.
- O scalar evaluator segue chamadas/retornos quando o alvo absoluto pode ser resolvido a partir do estado escalar conhecido.
- S_ASHR_I64 é adicionado ao scalar evaluator, alinhando-o ao lowering SPIR-V que já existia.
- HasSameScalarDefinitions aceita identidade PC->mesmo PC mesmo quando o CFG indireto torna definições conservadoramente conflitantes.

O pacote não toca RAD/Bink host decoder, IME, DCC, scheduler Vulkan, detile ou presenter.
