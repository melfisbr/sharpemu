# SharpEmu V76.2.4.7 — Canonical Containment BuildFix SAFE

Este pacote corrige exclusivamente o falso positivo `Path fora do pacote-alvo` da V76.2.4.6.

Ele **não altera o source do SharpEmu diretamente**. Ele corrige o guard de containment da V76.2.4.6, atualiza o manifest desse meta-pacote e reroda `RUN_1 -> RUN_2 -> RUN_3` da V76.2.4.6, que por sua vez aplica/valida a correção Split-Path na V76.2.4.1.

A checagem nova usa `System.IO.Path.GetRelativePath` sobre paths absolutos canônicos. Um filho real como `...\V76_2_4_1...\scripts\patch_target.ps1` passa; `..`, paths rooted fora da raiz ou escapes continuam bloqueados.

Rollback: se o workflow da V76.2.4.6 falhar após esta alteração, o script e o manifest da V76.2.4.6 são restaurados automaticamente. A própria V76.2.4.6 continua responsável pelo rollback dos scripts da V76.2.4.1.
