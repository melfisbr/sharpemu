# V76.0.12.3 — Bink Guest YUV/Storage PrerequisiteFix

- Mantém byte por byte o payload C# Bink/YUV da V76.0.12.2.
- Corrige o gate da V76.0.11.1: o cache SPIR-V não é mais validado por hash integral do arquivo.
- Valida semanticamente os contratos necessários da V76.0.11.1:
  - `CacheVersion = "V76.0.10-r1"`;
  - `ScheduleDiskPrewarmV7611` / `PrewarmDiskCacheV7611`;
  - `SHARPEMU_SPIRV_PREWARM_MAX` / `SHARPEMU_SPIRV_PREWARM_MB`;
  - fila assíncrona `QueueDiskWriteV7610` + `ThreadPool.QueueUserWorkItem`;
  - helper VS+PS paralelo V76.0.11.1 e seu callsite AGC.
- O helper paralelo continua protegido por hash exato, porque é um arquivo isolado e não deve receber carry-forward de terceiros.
- Aceita o cache instalado observado no source validado (`4c40d35d...`) se os contratos funcionais continuarem presentes.
- Não altera RAD/Nihav/FFmpeg, IME, DCC, scheduler ou presenter fora dos hooks YUV V76.0.12.
- Reconhece explicitamente o hash observado `4c40d35df93d1434f03c8092c1ccb0406063e0bfae2cb90a335f8895621ad09f` como estado conhecido da V76.0.11.1; outros hashes só passam por auditoria semântica.
