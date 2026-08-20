param([Parameter(Mandatory=$true)][string]$PackageRoot)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$script:Tag='[V74.0.84]'
$PackageRoot=$PackageRoot.Trim().Trim([char]34).Trim([char]39)
$script:PackageRoot=(Resolve-Path -LiteralPath $PackageRoot).Path.TrimEnd('\')
$script:PatchesRoot=Split-Path -Parent $script:PackageRoot
$script:RepoRoot=Split-Path -Parent $script:PatchesRoot
$script:PresenterRel='src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$script:PresenterPath=Join-Path $script:RepoRoot $script:PresenterRel
$script:BackupRoot=Join-Path $script:RepoRoot '.sharpemu-hotfix-backup'
$script:StateFile=Join-Path $script:PackageRoot 'LAST_BACKUP.txt'
function Get-Sha256([string]$Path){return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()}
function Read-Utf8([string]$Path){return [System.IO.File]::ReadAllText($Path,[System.Text.Encoding]::UTF8)}
function Write-Utf8NoBom([string]$Path,[string]$Text){$enc=New-Object System.Text.UTF8Encoding($false);[System.IO.File]::WriteAllText($Path,$Text,$enc)}
function Get-Count([string]$Text,[string]$Pattern){return ([regex]::Matches($Text,$Pattern,[System.Text.RegularExpressions.RegexOptions]::Multiline)).Count}
function Get-DeclarationSegment([string]$Text,[string]$Name){
  $needle='private static readonly bool '+$Name+' ='
  $s=$Text.IndexOf($needle,[System.StringComparison]::Ordinal)
  if($s -lt 0){return $null}
  $e=$Text.IndexOf(';',$s,[System.StringComparison]::Ordinal)
  if($e -lt 0){return $null}
  return [pscustomobject]@{Start=$s;Length=($e-$s+1);Text=$Text.Substring($s,$e-$s+1)}
}
function Assert-Repo{if(-not(Test-Path -LiteralPath $script:PresenterPath -PathType Leaf)){throw "$script:Tag Presenter ausente: $script:PresenterPath"}}
function Assert-StructuralContracts{
  Assert-Repo
  $p=Read-Utf8 $script:PresenterPath
  $fair=Get-DeclarationSegment $p '_kytyComputeSubmissionFairnessV74033'
  $adapt=Get-DeclarationSegment $p '_adaptiveUnifiedComputeV7405616'
  $checks=[ordered]@{
    V812=(Get-Count $p 'SHARPEMU_V74_0_81_2_SEMANTIC_BOUNDARY_REPAIR')
    V82=(Get-Count $p 'SHARPEMU_V74_0_82_NONBLOCKING_VISIBILITY_DCC_INDEX')
    V83=(Get-Count $p 'V74\.0\.83')
    FairnessDefinitions=(Get-Count $p '(?m)^\s*private\s+static\s+readonly\s+bool\s+_kytyComputeSubmissionFairnessV74033\s*=')
    AdaptiveDefinitions=(Get-Count $p '(?m)^\s*private\s+static\s+readonly\s+bool\s+_adaptiveUnifiedComputeV7405616\s*=')
    EmergencyLimit=(Get-Count $p 'SoftEmergencyGuestSubmissionLimitV74033')
    CrossWorkOvercommit=(Get-Count $p 'CROSS_WORK_OVERCOMMIT')
    SubmissionOvercommit=(Get-Count $p 'SUBMISSION_OVERCOMMIT')
    AdaptiveHelper=(Get-Count $p 'ShouldUseAdaptiveUnifiedComputeV7405616')
    AdaptiveTrace=(Get-Count $p 'ADAPTIVE_UNIFIED_COMPUTE')
    CapacityYield=(Get-Count $p '\[CAPACITY_YIELD\]')
    V84=(Get-Count $p 'SHARPEMU_V74_0_84_SUBMISSION_HEADROOM_ADAPTIVE')
  }
  foreach($e in $checks.GetEnumerator()){Write-Host "$script:Tag $($e.Key)=$($e.Value)"}
  if($checks.V812 -lt 1){throw "$script:Tag V81.2 semantic Vulkan boundaries ausentes."}
  if($checks.V82 -lt 1){throw "$script:Tag V82 nonblocking/DCC index ausente. Aplique V82.1 primeiro."}
  if($checks.FairnessDefinitions -ne 1 -or $null -eq $fair){throw "$script:Tag fairness field ambiguo/ausente."}
  if($checks.AdaptiveDefinitions -ne 1 -or $null -eq $adapt){throw "$script:Tag adaptive field ambiguo/ausente."}
  if($checks.EmergencyLimit -lt 2 -or $checks.CrossWorkOvercommit -lt 1 -or $checks.SubmissionOvercommit -lt 1){throw "$script:Tag bounded submission headroom implementation incompleta."}
  if($checks.AdaptiveHelper -lt 2 -or $checks.AdaptiveTrace -lt 1){throw "$script:Tag adaptive unified compute implementation incompleta."}
  return [pscustomobject]@{Presenter=$p;Fairness=$fair;Adaptive=$adapt}
}
function New-Backup{
  if(-not(Test-Path -LiteralPath $script:BackupRoot)){New-Item -ItemType Directory -Path $script:BackupRoot|Out-Null}
  $dir=Join-Path $script:BackupRoot ("SubmissionHeadroomAdaptiveV74084_"+(Get-Date -Format 'yyyyMMdd_HHmmss'))
  New-Item -ItemType Directory -Path $dir|Out-Null
  Copy-Item -LiteralPath $script:PresenterPath -Destination (Join-Path $dir 'VulkanVideoPresenter.cs') -Force
  Write-Utf8NoBom $script:StateFile $dir
  return $dir
}
function Restore-Backup([string]$Dir){$p=Join-Path $Dir 'VulkanVideoPresenter.cs';if(-not(Test-Path -LiteralPath $p)){throw "$script:Tag backup presenter ausente: $p"};Copy-Item -LiteralPath $p -Destination $script:PresenterPath -Force}
function Quote-ProcessArgument([string]$Value){if($null -eq $Value){return '""'};return '"'+($Value -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"'}
function Find-SharpEmuExe{
 $c=@((Join-Path $script:RepoRoot 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'),(Join-Path $script:RepoRoot 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.CLI.exe'))
 foreach($x in $c){if(Test-Path -LiteralPath $x -PathType Leaf){return $x}}
 return $null
}
