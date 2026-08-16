V61.24.2 SAFE

V61.24.1 proved:
- PlayStation Studios now runs completely.
- Persistent FFmpeg swscale path is active.
- Colors are still wrong.
- AJM reaches initialize/module/batch processing, but no decoder instance/decode.

Root color defect:
NihavBink2Decoder computes uPlane/vPlane according to _swapUv for the LUT
fallback, but TryConvertYuvViaFfmpeg receives _pgmPlanarBuffer directly.
Therefore SHARPEMU_NIHAV_UV_SWAP has no effect while FFmpeg conversion is active.

Fix:
Adds SHARPEMU_BINK_FFMPEG_UV_SWAP. When enabled, the two contiguous I420
chroma planes are swapped only around the FFmpeg conversion call and restored
afterward. This is allocation-free and does not alter the LUT fallback.

The V61.24.2 diagnostic enables this corrected path and disables noisy AJM
tracing already characterized by V61.24.1.
