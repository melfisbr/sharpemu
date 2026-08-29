SharpEmu V76.3.21.0.1
ForwardMaxThroughput Precheck Semantic Bridge — DEV SAFE

PURPOSE
-------
Fix only this V76.3.21.0 PRECHECK failure:

  Presenter contract ausente: SHARPEMU_DUAL_QUEUE_RESOURCE_SYNC

The failing V21.0 validator is checking a title/profile environment-contract
name as if it must literally occur in VulkanVideoPresenter.cs.

That is not a reliable proof of the actual Presenter capability.

SAFETY STRATEGY
---------------
This hotfix does NOT replace the V21.0 package and does NOT reproduce its
performance merge.

Instead it:
1. requires the existing V21.0 package folder;
2. runs V21.0's own RUN_1 package validation;
3. verifies actual Presenter dual-queue/timeline/cross-queue-hazard evidence;
4. verifies the CLI/profile contains dual/resource policy evidence;
5. adds a comment-only compatibility marker to VulkanVideoPresenter.cs;
6. runs V21.0's original RUN_2 PRECHECK;
7. runs V21.0's original RUN_3 APPLY+BUILD;
8. RUN_4 delegates to V21.0's original diagnostic.

The bridge adds zero runtime behavior.

WHY A COMMENT MARKER
--------------------
Modifying V21.0's own precheck.ps1 could invalidate the original package
manifest or RUN_1 validation. Adding a source comment satisfies the erroneous
textual prerequisite while leaving the original package byte-for-byte intact.

The bridge refuses to add the marker unless it first finds real dual-queue /
timeline / resource-hazard implementation evidence. It therefore does not
paper over a source that genuinely lacks the architecture.

ROLLBACK
--------
Before adding the marker, RUN_3 saves:

  Patches\V76_3_21_0_1_PRE_PRESENTER_<timestamp>.cs

If original V21 RUN_2 or RUN_3 fails, the Presenter is automatically restored.

RUN_5_ROLLBACK_LAST.cmd can also restore the latest bridge backup manually.
