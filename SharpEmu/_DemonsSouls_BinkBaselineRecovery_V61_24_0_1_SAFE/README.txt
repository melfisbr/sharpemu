V61.24.0.1

Fixes the V61.24.0 package regression:
- The previous precheck incorrectly required a compiled
  SHARPEMU_BINK_REALTIME_DEADLINE marker.
- The user's V61.23.6.1.1 rollback baseline is valid without that marker.
- This package treats that feature as optional and proceeds on the exact
  current source/runtime baseline.

Grounding:
AgcExports.cs expected V61.23.6.1.1 SHA256:
4809CECC89E500B23B2993557BBF55FE9BF1F7022B1FAD97251A893141D8B083
GpuWaitRegistry.cs expected V61.23.6.1.1 SHA256:
3D13C08D3627DD2D8B922F641C2AB9D9B1637B190C9F7C95CC8A50EFDEA17636

The diagnostic collects exact current Bink/Nihav/VideoOut/AJM/AudioOut source
and runtime evidence so the next semantic media/audio correction can be
generated against the current checkout rather than an obsolete build.
