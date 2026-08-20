# Runtime Trace Coverage

| Category | Status | Matched lines | Evidence files |
|---|---|---:|---:|
| loader_eboot_imports | **OBSERVED** | 60381 | 1 |
| shader_gpu | **OBSERVED** | 1 | 1 |
| audio_media | **OBSERVED** | 1890 | 1 |
| ui_resources | **OBSERVED** | 994 | 1 |
| file_io | **OBSERVED** | 47 | 1 |
| thread_sync | **OBSERVED** | 23022 | 1 |
| errors_stalls | **OBSERVED** | 626 | 2 |

`OBSERVED` means the captured runtime logs contain evidence for that category.
`GAP` means this session did not expose enough evidence in existing logs; source-level tracing is still required.

Important: this collector can preserve and classify existing SharpEmu logs, but it cannot infer guest file reads, shader compiler transitions, HLE calls or audio/UI calls that SharpEmu never logs.
