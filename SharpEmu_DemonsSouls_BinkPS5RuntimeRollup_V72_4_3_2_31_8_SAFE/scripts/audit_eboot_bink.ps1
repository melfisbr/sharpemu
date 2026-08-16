param(
    [string]$RepositoryRoot=(Get-Location).Path,
    [string]$Eboot="F:\JOGOSPS5\PPSA01341\eboot.bin"
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$expectedHash = "22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E"
if (-not (Test-Path -LiteralPath $Eboot -PathType Leaf)) {
    throw "[V72.4.3.2.31.8] EBOOT missing: $Eboot"
}
$hash=(Get-FileHash -LiteralPath $Eboot -Algorithm SHA256).Hash
if ($hash -ne $expectedHash) {
    throw "[V72.4.3.2.31.8] Unexpected Demon's Souls EBOOT SHA256: $hash"
}
$bytes=[IO.File]::ReadAllBytes($Eboot)
$text=[Text.Encoding]::ASCII.GetString($bytes)
$markers=@(
    'PS5BinkManager.cpp',
    'frame_bufs[%d].Plane_%s',
    'BinkGPU is only supported for Bink 2.2 and later files.',
    'Error reading Bink header.',
    'Not a Bink file.',
    'void *BinkAlloc(U64)',
    'HBINK',
    'Bink IO',
    'Bink Snd',
    'CComponentBinkSimpleMovie.cpp',
    'CCPLdrBinkSimpleMovie.cpp',
    'BinkColorCorrection'
)
$missing=@($markers | Where-Object { -not $text.Contains($_) })
if ($missing.Count -gt 0) {
    throw "[V72.4.3.2.31.8] EBOOT Bink evidence missing: $($missing -join ', ')"
}
Write-Host "[V72.4.3.2.31.8] EBOOT_BINK_AUDIT PASSED: exact PPSA01341 EBOOT; PS5BinkManager/HBINK/planes/BinkGPU/I-O/sound evidence present." -ForegroundColor Green
Write-Host "[V72.4.3.2.31.8] No proprietary Bink code was extracted; evidence is string-level only."
