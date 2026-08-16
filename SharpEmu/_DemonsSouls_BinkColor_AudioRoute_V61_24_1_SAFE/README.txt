V61.24.1 SAFE
Evidence from V61.24.0.1:
- PS Studios: 255 expected, completion frame 254 => full frame sequence reached.
- 3 Bink movies complete, no realtime deadline, no device lost.
- Current Bink path: BT709, full range, UV swap false, LUT path.
- AudioOut2 context memory is queried, but no AJM module/instance/decode activity appears.

This package activates the already-implemented persistent FFmpeg swscale color
converter and auto-range detection while retaining the corrected NIHAV U|V
side-by-side repack. It also enables existing AJM/AudioOut tracing so the next
audio correction can target import/routing vs decode based on real calls.

No AGC source changes. No fake PCM. No forced wait completion.
