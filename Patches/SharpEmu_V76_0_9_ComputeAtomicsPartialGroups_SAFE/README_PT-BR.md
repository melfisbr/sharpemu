# SharpEmu V76.0.9 — Compute Atomics + Partial Thread Groups SAFE

Prerequisito: V76.0.8 BUILD + SOURCE VERIFY PASSED.

Este pacote e adaptativo/in-place: nao substitui arquivos grandes inteiros. Ele fecha tres lacunas concretas do compute GFX10/RDNA2: semantica bounded de INC/DEC, cobertura da familia FLAT/GLOBAL atomic 32-bit e execucao de grupos parciais atraves do guard de limite de threads ja existente no backend Vulkan.

O apply cria backup antes do primeiro write e faz rollback automatico se qualquer etapa ou a build Release/win-x64 falhar.

RUN_4 e estritamente pos-build: execute somente se RUN_3 retornar BUILD PASSED.
