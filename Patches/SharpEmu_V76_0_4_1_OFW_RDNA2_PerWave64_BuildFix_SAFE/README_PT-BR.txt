SharpEmu V76.0.4.1 - OFW/RDNA2 Per-Wave64 BuildFix SAFE
=============================================================

BASELINE
- V76.0.4 OFW/RDNA2 Per-Wave64 Semantics aplicado, mas falhando no build com CS0136.
- Hash esperado do arquivo V76.0.4 quebrado:
  D6FEC976C9B559A8FCA3B8A3817EEB4283E194C4291D4E5B0156D56C18334462

CAUSA CONFIRMADA
- Gen5SpirvTranslator.Alu.cs, metodo BroadcastFirstWave64Active().
- O branch if (_multiWave64Bridge) introduziu locais activeMask/lowMask/highMask/hasLow/hasHigh/firstLow/firstHigh/firstLane.
- O mesmo metodo ja declarava esses nomes mais abaixo no escopo externo.
- Em C#, isso viola CS0136 mesmo que os blocos sejam executados de forma mutuamente exclusiva.

CORRECAO
- Somente renomeia os oito locais do branch multi-wave para nomes multiWave*.
- Nenhuma instrucao SPIR-V, algoritmo, barrier, atomic, wave64, YUV ou ownership Bink foi alterado.
- Arquivo modificado: src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.Alu.cs
- Hash corrigido:
  CB0BA3A3C92D7DF6242E087C96612AE2D1C016A17ADAE46234AC4E938F032EBD

EXECUCAO
1. RUN_1_VALIDATE_PACKAGE.cmd
2. RUN_2_PRECHECK.cmd
3. RUN_3_APPLY_BUILD.cmd
4. RUN_4_VERIFY_SOURCE.cmd

Logs, backup e ZIP de resultado sao gravados em:
C:\Users\Edpo\Documents\GitHub\sharpemu\Patches

O APPLY+BUILD faz rollback do arquivo se o build falhar.
