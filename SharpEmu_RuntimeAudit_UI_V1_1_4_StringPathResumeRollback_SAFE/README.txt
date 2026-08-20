SharpEmu RuntimeAudit UI V1.1.4 - String Path Resume Rollback SAFE

Current known state after V1.1.3:
- MainWindow.axaml.cs was successfully restored to the exact pre-RuntimeAudit SHA256:
  7D9213109B2B316DB00D97339DC9F233A0ECB467777C96D79D50364565282EAD
- V1.1.3 then failed before quarantining the separate RuntimeAudit partial because
  Find-FileByHash returned string paths and the script incorrectly attempted $p.FullName.

V1.1.4 resumes from that exact point. It does NOT restore MainWindow again.
It:
- confirms MainWindow.axaml.cs is still at the original SHA;
- treats RuntimeAudit candidates explicitly as string paths;
- quarantines the remaining RuntimeAudit UI partial;
- removes only a direct GUI ProjectReference to SharpEmu.RuntimeAudit if present;
- confirms no RuntimeAudit UI marker remains;
- rebuilds SharpEmu.GUI;
- launches a real six-second startup probe and leaves SharpEmu running if successful.

Commands:
  .\SharpEmu_RuntimeAudit_UI_V1_1_4_StringPathResumeRollback_SAFE\RUN_1_VALIDATE_PACKAGE.cmd
  .\SharpEmu_RuntimeAudit_UI_V1_1_4_StringPathResumeRollback_SAFE\RUN_2_PRECHECK.cmd
  .\SharpEmu_RuntimeAudit_UI_V1_1_4_StringPathResumeRollback_SAFE\RUN_3_RESUME_ROLLBACK_BUILD_STARTUP_TEST.cmd

Only if startup still fails:
  .\SharpEmu_RuntimeAudit_UI_V1_1_4_StringPathResumeRollback_SAFE\RUN_4_COLLECT_STARTUP_DIAGNOSTIC.cmd
