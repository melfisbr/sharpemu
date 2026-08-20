SharpEmu V74.0.67.2.20
DLSS Dual-Config Runtime Deployment SAFE

ROOT CAUSE
==========
The uploaded runtime is running from:
  artifacts\bin\Debug\net10.0\win-x64

Its managed loader checks:
  Debug\...\upscalers\SharpEmu.VulkanUpscaler.Native.dll
  Debug\...\SharpEmu.VulkanUpscaler.Native.dll

Both report:
  exists=0
  loaded=0

Provider init then reports:
  provider_dll_not_loaded
  provider=0
  caps=0x0
  selected=off
  precomposite_provider_init_failed

The Rendering selection itself is correct:
  requested_quality=ultraperformance
  effective_quality=ultraperformance

FIX
===
The already validated local provider + nvngx runtime are copied into:
  runtime\dlss\upscalers\SharpEmu.VulkanUpscaler.Native.dll
  runtime\dlss\nvngx_dlss.dll

SharpEmu.CLI.csproj is patched so every Debug/Release build and publish copies
those exact binaries automatically.

RUN_3 builds and validates BOTH Debug and Release.

RUN_5 deliberately launches Debug because that is the configuration that
failed in the supplied log.

Expected after fix:
  Debug loader exists=1 loaded=1
  provider=1
  caps=0x9
  selected=dlss
  state=active
  requested_quality=ultraperformance
  effective_quality=ultraperformance
  dlss_dispatches>0
  dispatch_failures=0
