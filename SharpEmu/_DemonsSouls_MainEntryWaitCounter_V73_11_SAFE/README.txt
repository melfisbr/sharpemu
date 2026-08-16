SharpEmu Demon's Souls Main Entry Wait Counter V73.11 SAFE

WHY V73.10 IS ROLLED BACK
The V73.10 run proved the HLE route was active, but:
- app+0x821000 worker-page peak remained 96%;
- all native UI method counters remained zero;
- only 5 VideoOut FPS windows were reached;
- the child ended with APPLICATION_HANG after resource dependency recording.

The more important discovery is diagnostic: GuestRipSampleLoop samples
SnapshotGuestThreads(), and the V73.10 thread_split/top_thread output identifies
those samples overwhelmingly as BPE JobWorkerThread CPU0..12. The initial
top-level game entry executes on _entryHostThreadId and was not included.

WHAT THE EXISTING USLEEP TRACE DID PROVE
An untracked thread=0 sample returned to:
  app+0x81A493

That address is inside the EBOOT's generic wait helper:
  app 0x81A3B0..0x81A500

The audited helper register contract is:
  R15 = pointer to 64-bit value being polled
  R14 = target
  RBX = compare selector
  R13 = spin counter
  R12 = scheduler/wrapper object

The old usleep trace dereferenced R13, so it was looking at the spin counter,
not the actual waited value.

V73.11 CHANGES
1. Removes only the V73.10 sceKernelUsleep HLE-preference block.
2. Extends ExtendedHostThreadContextSnapshot with R14/R15.
3. Samples _entryHostThreadId independently from worker GuestThreadState.
4. Only while entry RIP is in 0x81A3B0..0x81A500, reads *R15 and reports:
   pointer, value, target, comparator, matched/waiting predicate, spin count,
   scheduler pointer and RBP caller chain.
5. Feeds entry-thread RIPs through the V73.9 native UI method probe too.

NO SEMANTIC WAIT HACK
V73.11 does not write the wait counter, force a job complete, fabricate a wake,
or change GPU/UI behavior.

CURRENT SOURCE GUARDS
DirectExecutionBackend.cs:
  054C0C4FA74F3B2D3599DCA36F0CC7F374088093DCF1ACE337B179A638EA34CD
DirectExecutionBackend.GuestSampler.cs:
  DDB0C1FBDF353AE8922C73236FB83B186BDAC49750E47F3D814D6A0AD7495E75

DIAGNOSTIC
- automatically stops after 150 seconds
- entry + worker RIP sampling every 4 ms
- native UI reachability remains active
- VideoOut real FPS remains active
- Options samples at 80/95/110/125/140 seconds
- heavy usleep/AGC/resource traces disabled

The result can distinguish:
- main-entry-generic-wait-counter-stuck-nonzero
- main-entry-generic-wait-predicate-satisfied-ui-still-unreached
- main-entry-running-outside-audited-generic-wait
- entry-or-worker-reaches-ui-manager-native-code
- entry-or-worker-reaches-startmenu-native-code

Result:
  SharpEmu_V73_11_MAIN_ENTRY_WAIT_RESULT_<timestamp>.zip
