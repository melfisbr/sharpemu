# V76.0.18.3 Host Variable BuildFix

- Functional payload is unchanged from V76.0.18/18.1.
- Rebased prerequisite validation against `src(20260825-003946).zip`.
- Accepts Bink YUV helper hash `58b1ad2800662e20ff29b7c69eadba6d868463880c81872ebcb28608e59c66e5` when all V76.0.12 contracts are present.
- All V76.0.12/14/15/16 helper prerequisites are now validated semantically; hashes are diagnostic/known-state hints rather than brittle gates.
- Bink A/V V76.0.13 remains semantically validated.
- Hard guest-only Bink2 + eboot handoff payload remains byte-for-byte unchanged.
- Logs/results use V76_0_18_2.


- Corrige falha do RUN_3 `Não é possível substituir a variável Host`.
- `scripts/common.ps1`: `$host` -> `$hostText` em `Assert-V7618Installed`.
- `scripts/validate.ps1`: detector case-insensitive para atribuição a `$Host`.
- Nenhum arquivo em `patchdata/` ou `payload/src/` foi alterado funcionalmente.
