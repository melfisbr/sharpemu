SharpEmu RuntimeAudit UI V1.1.3 - Frontend Locator Rollback SAFE

Fixes the V1.1.2 rollback detector that incorrectly required a literal file named
MainWindow.cs.

V1.1.3 locates the patched frontend using, in order:
1. exact post-patch SHA256 recorded by RuntimeAudit UI V1.1;
2. InstallRuntimeAuditButton / "Audit & Launch" marker;
3. exact pre-patch SHA256;
4. unique C# source declaring class MainWindow.

It then:
- restores the exact pre-V1.1 frontend file from backup by SHA256;
- quarantines separate RuntimeAudit UI partials;
- removes only GUI ProjectReference(s) to SharpEmu.RuntimeAudit;
- rebuilds the GUI;
- performs a real startup probe and leaves SharpEmu running if successful.

Commands:
  .\SharpEmu_RuntimeAudit_UI_V1_1_3_FrontendLocatorRollback_SAFE\RUN_1_VALIDATE_PACKAGE.cmd
  .\SharpEmu_RuntimeAudit_UI_V1_1_3_FrontendLocatorRollback_SAFE\RUN_2_PRECHECK.cmd
  .\SharpEmu_RuntimeAudit_UI_V1_1_3_FrontendLocatorRollback_SAFE\RUN_3_ROLLBACK_BUILD_STARTUP_TEST.cmd

Only if RUN_3 reports that SharpEmu still exits:
  .\SharpEmu_RuntimeAudit_UI_V1_1_3_FrontendLocatorRollback_SAFE\RUN_4_COLLECT_STARTUP_DIAGNOSTIC.cmd
