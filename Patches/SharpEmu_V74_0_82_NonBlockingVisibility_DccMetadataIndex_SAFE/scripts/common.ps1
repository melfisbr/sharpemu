param([Parameter(Mandatory=$true)][string]$PackageRoot)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$script:Tag='[V74.0.82]'
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
function Assert-Repo{if(-not(Test-Path -LiteralPath $script:PresenterPath -PathType Leaf)){throw "$script:Tag Presenter ausente: $script:PresenterPath"}}
function Assert-StructuralContracts{
  Assert-Repo
  $p=Read-Utf8 $script:PresenterPath
  $checks=[ordered]@{
    V812=(Get-Count $p 'SHARPEMU_V74_0_81_2_SEMANTIC_BOUNDARY_REPAIR')
    OrderedField=(Get-Count $p '_nonBlockingOrderedVisibilityV740293')
    OrderedFenceTrace=(Get-Count $p 'vk\.ordered_action_fence_wait')
    DccMethod=(Get-Count $p 'TryResolveGuestImageMetadataAliasV7405632\s*\(')
    GuestImages=(Get-Count $p '_guestImages')
    GuestVariants=(Get-Count $p '_guestImageVariants')
    DccV80=(Get-Count $p 'DCC_PROVENANCE_RECOVERY')
    V82=(Get-Count $p 'SHARPEMU_V74_0_82_NONBLOCKING_VISIBILITY_DCC_INDEX')
  }
  foreach($e in $checks.GetEnumerator()){Write-Host "$script:Tag $($e.Key)=$($e.Value)"}
  if($checks.V812 -lt 1){throw "$script:Tag V74.0.81.2 nao detectada. Aplique a .81.2 primeiro."}
  if($checks.OrderedField -lt 2){throw "$script:Tag ordered visibility contract ausente."}
  if($checks.OrderedFenceTrace -lt 1){throw "$script:Tag ordered fence diagnostic ausente."}
  if($checks.DccMethod -ne 1){throw "$script:Tag DCC metadata resolver ambiguo/ausente."}
  if($checks.GuestImages -lt 2 -or $checks.GuestVariants -lt 2){throw "$script:Tag guest image dictionaries ausentes."}
  return $p
}
function New-Backup{
  if(-not(Test-Path -LiteralPath $script:BackupRoot)){New-Item -ItemType Directory -Path $script:BackupRoot|Out-Null}
  $dir=Join-Path $script:BackupRoot ("NonBlockingVisibilityDccIndexV74082_"+(Get-Date -Format 'yyyyMMdd_HHmmss'))
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
