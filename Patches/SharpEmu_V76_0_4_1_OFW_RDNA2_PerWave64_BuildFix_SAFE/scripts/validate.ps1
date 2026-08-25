$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")
Assert-Package
$manifest = Join-Path $PSScriptRoot "..\PACKAGE_SHA256.txt"
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { throw "$Tag PACKAGE_SHA256.txt ausente" }
Write-Host "$Tag PACKAGE VALIDATION PASSED. payload_sha=$ExpectedFixedSha" -ForegroundColor Green
