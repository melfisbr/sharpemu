SharpEmu V74.0.67.2.19
DLSS Strict Quality Profile Passthrough SAFE

PROBLEM PROVEN BY RUNTIME
=========================
The frontend requests UltraPerformance, but the managed pre-composite path
silently changes it:

  requested_quality=ultraperformance
  effective_quality=quality

This repeats throughout the supplied runtime while DLSS itself is active and
dispatch_failures=0.

ROOT CAUSE
==========
The frontend/env parser is already correct. It recognizes:
  NativeAA / DLAA
  Quality
  Balanced
  Performance
  UltraPerformance

The native NGX provider mapping is also already correct:
  0 -> DLAA
  1 -> MaxQuality
  2 -> Balanced
  3 -> MaxPerf
  4 -> UltraPerformance

The unwanted downgrade occurs in VulkanUpscalerBridge's pre-composite path:
it derives effectiveQuality from the observed input/output scale ratio and uses
that inferred value for the native dispatch.

V2.19 FIX
=========
The old auto-resolved value is retained only for diagnostics:

  autoResolvedQualityV74067219 = <existing ratio-derived expression>

but the actual dispatch profile is now:

  effectiveQuality = requestedQuality

Therefore the user's Rendering profile owns the provider quality enum.

The source resolver is NOT changed. It still chooses the best valid temporal
scene source that actually exists. V2.19 does not invent or resize guest render
targets.

This distinction is important:
- profile selection is now strict;
- input scene resolution still comes from the game/resource tracker.

If a vendor rejects a particular profile/input-size combination, SharpEmu will
report the provider failure instead of silently substituting another profile.

EXPECTED RUNTIME
================
UltraPerformance:
  requested_quality=ultraperformance
  effective_quality=ultraperformance
  [UPSCALER][RUNTIME] ... quality=ultraperformance
  selected=dlss
  state=active
  dlss_dispatches>0
  dispatch_failures=0

Balanced:
  requested_quality=balanced
  effective_quality=balanced

Performance:
  requested_quality=performance
  effective_quality=performance

Quality:
  requested_quality=quality
  effective_quality=quality

DLAA/NativeAA:
  requested_quality=nativeaa/native
  effective_quality=nativeaa
  (requires equal input/output dimensions; existing native validation remains)

FRONTEND
========
RUN_5 clears shell overrides. Normal use remains:
  Rendering -> Upscaler Enabled -> DLSS -> desired profile -> Execute.

V2.19 is cumulative with V2.17/V2.18 when those source markers are absent.
