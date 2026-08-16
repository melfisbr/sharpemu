$ErrorActionPreference="Stop"
# Exact 64-byte head observed in V1.8.14.2.1.
$hex='52494646BC31000057415645666D742034000000FEFF010080BB00004C1D0000A00000002200000404000000D242E147BA368D4D88FC61654F8C836C01000000'
$bytes=for($i=0;$i -lt $hex.Length;$i+=2){[Convert]::ToByte($hex.Substring($i,2),16)}
if($bytes[0]-ne 0x52 -or $bytes[8]-ne 0x57){throw "RIFF fixture failed"}
if($bytes[20]-ne 0xFE -or $bytes[21]-ne 0xFF){throw "WAVE_EXTENSIBLE fixture failed"}
# GUID bytes begin at 44.
$guid='D242E147BA368D4D88FC61654F8C836C'
$actual=($bytes[44..59]|ForEach-Object {$_.ToString('X2')})-join ''
if($actual -ne $guid){throw "ATRAC9 GUID fixture mismatch: $actual"}
$apply=Get-Content -LiteralPath (Join-Path $PSScriptRoot "apply_build.ps1") -Raw
foreach($m in @('SHARPEMU_DBFZ_RIFF_ATRAC9_PRESERVE_V1_8_15','SHARPEMU_DBFZ_FULL_APP0_WRITE_V1_8_15','preserved=1')){
 if(-not $apply.Contains($m)){throw "Patch marker missing: $m"}
}
Write-Host "[DBFZ-RIFF-1815] OFFLINE RIFF/ATRAC9 REGRESSION PASSED."
