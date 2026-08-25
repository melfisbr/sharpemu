# Changelog V76.2.4.7

- Corrige falso positivo `Path fora do pacote-alvo` observado na V76.2.4.6.
- Mantém containment real: canonicaliza root/candidate e usa `Path.GetRelativePath`.
- Não desabilita a proteção; apenas substitui a decisão falsa-positiva por uma decisão canônica.
- Atualiza `manifest.sha256` da V76.2.4.6 após patchar seu script.
- Reroda automaticamente V76.2.4.6 VALIDATE/PRECHECK/RUN_3.
- Rollback do meta-pacote V76.2.4.6 em falha.
- Nenhuma alteração funcional adicional no decoder/YUV do SharpEmu.
