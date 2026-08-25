# V76.0.5.1

- Rebase adaptativo sobre os hashes locais observados em 2026-08-24 11:51 -03:00.
- Preserva alterações posteriores em presenter/translator/ALU.
- Corrige precheck excessivamente rígido da V76.0.5 sem transformar UNKNOWN em aceite genérico.
- Neutraliza default-on do soft-fail V76.0.4 quando presente.
- Mantém rollback total em qualquer falha antes/depois da build.
