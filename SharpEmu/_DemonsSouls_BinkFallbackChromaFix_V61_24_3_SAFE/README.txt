SharpEmu V61.24.3 SAFE

Evidence from BOTH V61.24.2 runs:
- bink2.ffmpeg_color_ready occurs for every movie.
- The first FFmpeg frame then times out after 5000 ms for every movie.
- The converter is disabled and visible frames use the LUT fallback.
- Therefore V61.24.2's FFmpeg-only U/V correction never affected visible output.
- Existing fallback heuristic chose 'normal' from a green-cast score, but the
  user confirms colors remain wrong.

Correction:
- Disable the known-failing FFmpeg color path for this run.
- Force existing SHARPEMU_BINK_FORCE_UV_SWAP=1, which performs the alternate
  u/v conversion in TryRepairGreenFallback — the path that actually presents.
- Preserve the validated full-video behavior.
- Disable the already-characterized high-volume AJM trace.

No AGC changes. No fake audio. No forced GPU waits.
