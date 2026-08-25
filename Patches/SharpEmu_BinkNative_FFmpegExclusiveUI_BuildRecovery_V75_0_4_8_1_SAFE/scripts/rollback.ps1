$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'common.ps1')
$statePath=Get-StatePath
if(-not(Test-Path -LiteralPath $statePath -PathType Leaf)){throw "$script:Tag state file not found: $statePath"}
$state=Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json
if([string]::IsNullOrWhiteSpace([string]$state.Backup) -or -not(Test-Path -LiteralPath $state.Backup -PathType Leaf)){throw "$script:Tag source backup not available in state"}
Stop-SharpEmu;$repo=Get-RepositoryRoot;$temp=Join-Path (Get-PatchesRoot) ('SharpEmu_V75_0_4_8_ROLLBACK_'+(Get-Date -Format 'yyyyMMdd_HHmmss'));Expand-Archive -LiteralPath $state.Backup -DestinationPath $temp -Force
try{Get-ChildItem -LiteralPath $temp -Recurse -File|ForEach-Object{$rel=$_.FullName.Substring($temp.TrimEnd('\').Length).TrimStart('\');$dst=Join-Path $repo $rel;New-Item -ItemType Directory -Path (Split-Path -Parent $dst) -Force|Out-Null;Copy-Item -LiteralPath $_.FullName -Destination $dst -Force}}finally{Remove-Item $temp -Recurse -Force}
Write-Tag "ROLLBACK SOURCE RESTORED backup=$($state.Backup)"
