SharpEmu RuntimeAudit UI V1.1.2 - Startup Rollback SAFE

Use this package only for the regression where SharpEmu stopped opening after
RuntimeAudit UI V1.1 was successfully applied.

This package is deliberately narrow:
- restores MainWindow.cs from the exact V1.1 backup created at 20260817_100143
  (or the newest matching RuntimeAudit_UI_V1_1_* backup if the exact folder is absent);
- validates the restored MainWindow SHA256 against the pre-patch hash reported by V1.1;
- quarantines only the RuntimeAudit partial identified by its exact SHA256 or hook marker;
- removes only a GUI ProjectReference to SharpEmu.RuntimeAudit if one exists;
- rebuilds SharpEmu.GUI;
- launches a six-second startup probe and leaves SharpEmu running if it survives;
- preserves all non-RuntimeAudit SharpEmu source changes.

Commands:
  .\SharpEmu_RuntimeAudit_UI_V1_1_2_StartupRollback_SAFE\RUN_1_VALIDATE_PACKAGE.cmd
  .\SharpEmu_RuntimeAudit_UI_V1_1_2_StartupRollback_SAFE\RUN_2_PRECHECK.cmd
  .\SharpEmu_RuntimeAudit_UI_V1_1_2_StartupRollback_SAFE\RUN_3_ROLLBACK_BUILD_STARTUP_TEST.cmd

Only if startup still fails:
  .\SharpEmu_RuntimeAudit_UI_V1_1_2_StartupRollback_SAFE\RUN_4_COLLECT_STARTUP_DIAGNOSTIC.cmd
