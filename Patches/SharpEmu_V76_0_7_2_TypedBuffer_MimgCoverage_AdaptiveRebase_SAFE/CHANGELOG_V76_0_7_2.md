# CHANGELOG V76.0.7.2

- Remove hashes integrais rigidos dos quatro arquivos alvo.
- Substitui whole-file payload por 11 patches semanticos in-place e idempotentes.
- Mantem hash exato apenas para componentes imutaveis V76.0.5.1 e helper V76.0.6.1.
- Precheck agora distingue `Applied` e `Ready` por patch individual.
- Backup completo antes do primeiro write e rollback em excecao/build failure.
- Nenhuma mudanca funcional adicional sobre V76.0.7.1.
