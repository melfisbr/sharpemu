# V74.0.10.1 — Native-lane truth recovery

V74.0.10 runtime logging had two diagnostic defects:

1. PowerShell `-f` precedence formatted only the second concatenated string,
   so the console printed literal placeholders such as `t={0:F0}s`.
2. Result consolidation happened only after the full runtime. Ctrl+C killed
   PowerShell before SUMMARY/ZIP creation.

The runtime itself opens stderr/stdout/CSV files at startup, so an interrupted
V74.0.10 normally leaves a complete or partial result directory.

V74.0.10.1 first searches for:

    SharpEmu_V74_0_10_NATIVE_LANE_TRUTH_RESULT_*
    SharpEmu_V74_0_10_1_NATIVE_LANE_TRUTH_RESULT_*

If it finds >=60 seconds of collection, it does NOT launch the game. It reads
the existing stderr once, reconstructs native-lane/TaskManager/Nexus/GPU/UI
truth, generates SUMMARY.txt and NATIVE_LANE_EVIDENCE.txt, then creates the ZIP.

If no recoverable collection exists, it starts a new run. The new collector:

- prints the exact live result folder immediately;
- fixes the status formatting;
- rewrites LIVE_STATUS.txt every ~30 seconds;
- keeps stdout.log, stderr.log and CSVs live from startup.

Therefore even if a future run is interrupted, rerunning the same command
recovers the data instead of losing the diagnostic.
