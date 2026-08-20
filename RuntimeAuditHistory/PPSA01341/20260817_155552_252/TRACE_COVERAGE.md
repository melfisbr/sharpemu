# Runtime Trace Coverage

| Category | Status | Matched lines | Evidence files |
|---|---|---:|---:|
| loader_eboot_imports | **OBSERVED** | 566 | 1 |
| shader_gpu | **GAP** | 0 | 0 |
| audio_media | **OBSERVED** | 15 | 1 |
| ui_resources | **OBSERVED** | 36 | 1 |
| file_io | **GAP** | 0 | 0 |
| thread_sync | **OBSERVED** | 110 | 1 |
| errors_stalls | **OBSERVED** | 27 | 2 |

`OBSERVED` means the captured runtime logs contain evidence for that category.
`GAP` means this session did not expose enough evidence in existing logs; source-level tracing is still required.

Important: this collector can preserve and classify existing SharpEmu logs, but it cannot infer guest file reads, shader compiler transitions, HLE calls or audio/UI calls that SharpEmu never logs.
