$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")
Assert-Package
$state = Get-SourceState
Write-Host "$Tag Repo=$Repo"
Write-Host "$Tag Target=$Target"
Write-Host "$Tag State=$state"
if ($state -eq 'Missing') { throw "$Tag target ausente" }
if ($state -like 'Divergent:*') { throw "$Tag source divergente; recuso sobrescrever um baseline desconhecido. hash=$($state.Substring(10))" }
Write-Host "$Tag PRECHECK PASSED." -ForegroundColor Green
