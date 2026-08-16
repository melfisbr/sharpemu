SharpEmu Demon\'s Souls V61.23.0 - AGC Label Epoch / Cross-Queue Safety Fix

Evidence baseline: V61.22.3 producer-lineage diagnostic.

Correction:
- A newly registered unsatisfied WAIT_REG_MEM starts a new logical generation of
  that label in GpuWaitRegistry.
- Any _lastProduced value retained from a previous generation is discarded at
  registration time, before the waiter is stored.
- This prevents a future deadlock-break path from treating an old completed
  producer as evidence for a new wait after the guest has reset the label to 0.
- No wait is force-satisfied. No producer value is invented.

The V61.22.3 trace showed a concrete stale-generation case:
  label 0x456CFF580, new wait submission=68, old producer_seq=315 completed in
  dcb.graphics submission=24.

The package is hash-gated to the exact GpuWaitRegistry.cs captured by V61.22.3.
It creates a backup and restores it automatically if the build fails.
