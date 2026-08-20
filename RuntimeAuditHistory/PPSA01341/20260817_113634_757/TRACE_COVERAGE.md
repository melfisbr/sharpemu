# Runtime Trace Coverage

| Category | Status | Matched lines | Evidence files |
|---|---|---:|---:|
| loader_eboot_imports | **OBSERVED** | 10 | 2 |
| shader_gpu | **OBSERVED** | 2 | 1 |
| audio_media | **GAP** | 0 | 0 |
| ui_resources | **OBSERVED** | 27 | 2 |
| file_io | **OBSERVED** | 34 | 2 |
| thread_sync | **OBSERVED** | 2 | 1 |
| errors_stalls | **OBSERVED** | 4 | 1 |

`OBSERVED` means the captured runtime logs contain evidence for that category.
`GAP` means this session did not expose enough evidence in existing logs; source-level tracing is still required.

Important: this collector can preserve and classify existing SharpEmu logs, but it cannot infer guest file reads, shader compiler transitions, HLE calls or audio/UI calls that SharpEmu never logs.
