$ErrorActionPreference="Stop"

$pre=Get-Content -LiteralPath (Join-Path $PSScriptRoot "precheck.ps1") -Raw
$post=Get-Content -LiteralPath (Join-Path $PSScriptRoot "post_audit.ps1") -Raw
$apply=Get-Content -LiteralPath (Join-Path $PSScriptRoot "apply_build.ps1") -Raw

foreach($needle in @(
 'State=',
 'AlreadyApplied',
 'NeedsV1_8_15_1Apply',
 'SHARPEMU_DBFZ_RIFF_ATRAC9_PRESERVE_V1_8_15_1'
)){
    if(-not $pre.Contains($needle)){throw "Idempotent precheck regression missing: $needle"}
}

if($post.Contains('DBFZ-RIFF-181511')){throw "Duplicated legacy tag leaked into V1.8.15.2."}
if($apply.Contains('V1_8_15_1_1')){throw "Duplicated legacy version leaked into V1.8.15.2."}

Write-Host "[DBFZ-RIFF-18152] OFFLINE IDEMPOTENCY/TAG REGRESSION PASSED."
