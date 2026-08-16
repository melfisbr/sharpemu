SharpEmu — Demon's Souls Targetless Composite Merge Fix V73.0.22.1

WHY V73.0.22 WAS BLOCKED
========================
Current AgcExports SHA256:
BEC6107EF646A8D53CB5276F2B8ED29FA818403F4B1488E0D5B199B2D1EA82D1

The successful UI A/B had captured an older AGC:
7FFC81332D6C0CFDA2D03AF9B9A7A347F22B1A8190FA9AB4BBB9C34D010569CE

Between those runs, newer AGC corrections accumulated, including V74.0.25
WRITE_DATA packet-position/startup-wait work. Replacing the entire AGC with the
older V73.0.22 payload would have lost those fixes, so the old package correctly
refused to apply.

V73.0.22.1 DOES NOT REPLACE AGC
===============================
It performs only TWO surgical condition changes:

1) direct writer suppression:
OLD:
  if (hasCurrentFrameDisplayWriter && !_replayTargetlessComposites)

NEW:
  direct writer + replay disabled + title is NOT PPSA01341

2) replay-after-direct-writer trace branch:
OLD:
  if (_replayTargetlessComposites && hasCurrentFrameDisplayWriter)

NEW:
  replay override OR PPSA01341, plus direct writer

No fields, wait logic, DMA logic, WRITE_DATA scheduling, queue identity, DCC,
presenter, movie or input code is replaced.

VALIDATION BEFORE SHIPPING
==========================
The two-condition transformer was tested locally against:
- the exact 7FFC... AGC from the successful LANGUAGE SELECT A/B;
- the same source after applying the exact V74.0.25 transformer.

In both:
- old suppression condition count = 1
- old replay condition count = 1
- resulting new condition counts = 1 each
- brace count unchanged
- no wait/DMA/WRITE_DATA code changed

RUN_2 accepts a baseline edit only when the repository AGC hash is exactly:
BEC6107EF646A8D53CB5276F2B8ED29FA818403F4B1488E0D5B199B2D1EA82D1

It then performs the SAME transformer in memory and requires:
- resulting state = Applied
- only the expected four added line breaks
- brace counts unchanged
- CanonicalMemory preserved
- RecordProducedLabelsInRange preserved
- SubmitOrderedGuestActionAfterQueueCompletion preserved
- V74.0.25 marker preserved when present

If any assumption is false it creates:
SharpEmu_V73_0_22_1_AGC_CAPTURE_<timestamp>.zip
and refuses source modification.

RUNTIME TEST
============
RUN_4:
- Release win-x64
- targetless replay environment override UNSET
- PPSA01341 must replay through source logic itself
- V74.0.25 SHARPEMU_WRITE_DATA_PACKET_POSITION=1 preserved for startup waits
- AGC/Vulkan hot traces disabled
- overlay/perf traces disabled

Close SharpEmu when LANGUAGE SELECT first appears. wall_seconds measures the
low-trace time-to-UI.
