SharpEmu Demon's Souls V61.23.1 - AGC Label Epoch Fix (SAFE)

This revision fixes two package defects from V61.23.0:
1. trailing %~dp0\ quoting could pass an invalid path to Test-Path;
2. precheck depended on one concrete _lastProduced declaration type despite an exact baseline hash.

The source correction remains conservative: when a new unsatisfied wait is registered,
stale last-produced history for that label is removed so an older generation cannot be
used by the deadlock breaker. No wait is force-satisfied.

Run in order:
RUN_VALIDATE_PACKAGE_V61_23_1.cmd
RUN_PRECHECK_V61_23_1.cmd
RUN_APPLY_BUILD_V61_23_1.cmd
RUN_DEMONS_DIAGNOSTIC_V61_23_1.cmd
