# SharpEmu V76.0.10.2 — Shader Cache Critical Path Semantic SOPP Fix SAFE

Esta revisao corrige somente o mecanismo de aplicacao SOPP da V76.0.10.1. O payload C# do cache permanece identico. Vulkan e Metal passam a inserir SClause/SWaitcntDepctr por tokens unicos dentro do bloco SOPP, sem depender de um here-string textual completo.

O pacote requer a V76.0.9.3, cria backup antes da primeira mutacao e restaura o baseline em qualquer falha de apply/build.
