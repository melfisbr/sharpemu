# V76.0.10.4.1

- Adaptive rebase sobre o cache atual SHA-256 `09b7daedf5eab60c1979012d6cf125c9a607623e8df5072f6d487c9907ccbbd3`.
- Não substitui o arquivo de cache por uma versão anterior.
- Faz patch estrutural somente de `CacheVersion` para `V76.0.10.4-r1`.
- Mantém a correção RDNA2 DPP/PERMLANE da V76.0.10.4.
- Rollback automático dos dois arquivos em caso de build failure.
