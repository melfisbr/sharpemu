# SharpEmu V74.0.87.1 — Cooperative Gate Quantum / Structural Dry-Run SAFE

Correção direta da V74.0.87 que falhava no PRECHECK com `GateOwnerMarker=4`.

## Causa corrigida
A V87 usava `IndexOf("GATE_OWNER_WAIT_DRAIN")` e classificava apenas a primeira ocorrência. Em um checkout com quatro ocorrências, a primeira pode estar fora do método real. O contador de chaves também era textual e podia ser enganado por `{}` em strings interpoladas.

## O que V87.1 valida antes de escrever
1. SHA256 de todos os arquivos do pacote.
2. Parser nativo do Windows PowerShell em todos os `.ps1`.
3. Fixture offline que reproduz **4 markers -> 1 método válido**.
4. Scanner léxico C# que ignora comentários, chars, strings normais/verbatim/interpoladas/raw.
5. Transformação em memória + idempotência na fixture.
6. Dry-run **somente leitura no AgcExports.cs do checkout atual**. O RUN_1 imprime todos os candidatos e exige exatamente um.
7. RUN_3 reaplica exatamente a mesma transformação previamente validada em memória e faz verificação pós-write antes do build.
8. Falha de apply/build restaura apenas o backup criado nesta execução.

A falha da V87 ocorreu no PRECHECK, portanto ela não escreveu source e não exige rollback antes desta V87.1.

## Execução
```powershell
cd C:\Users\Edpo\Documents\GitHub\sharpemu\Patches
Get-Process SharpEmu -ErrorAction SilentlyContinue | Stop-Process -Force
.\SharpEmu_V74_0_87_1_CooperativeGateQuantum_StructuralDryRun_SAFE\RUN_1_VALIDATE_PACKAGE.cmd
.\SharpEmu_V74_0_87_1_CooperativeGateQuantum_StructuralDryRun_SAFE\RUN_2_PRECHECK.cmd
.\SharpEmu_V74_0_87_1_CooperativeGateQuantum_StructuralDryRun_SAFE\RUN_3_APPLY_BUILD.cmd
.\SharpEmu_V74_0_87_1_CooperativeGateQuantum_StructuralDryRun_SAFE\RUN_4_TEST_DIAGNOSTIC.cmd
```
