SharpEmu V61.24.0 SAFE

Immediate grounded correction:
- Forces SHARPEMU_BINK_REALTIME_DEADLINE=0 for the Demon's Souls test so
  ps_studios_logo.bk2 is not ended at nominal wall-clock time before all
  decoded frames have been displayed.

Evidence collection for the next semantic corrections:
- Captures exact Media/Bink/Nihav/VideoOut source around color conversion,
  chroma ordering, BT.709/range/LUT and pacing.
- Captures exact AJM/AudioOut source around module registration, instances,
  decode, context submit and PCM output.
- Captures focused runtime color/audio lines and automatic frame-completion
  counters.

Safety:
- Does not force UV swap without exact source/evidence.
- Does not invent PCM data or fake AJM decode completion.
- Does not modify AGC synchronization.
- Does not modify repository source in this package.
- Windows PowerShell 5.1 compatible.
