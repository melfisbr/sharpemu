param([Parameter(Mandatory=$true)][string]$PackageRoot)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$script:Tag='[V74.0.81]'
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
        PendingBytesField=(Get-Count $p 'private\s+static\s+ulong\s+_pendingGuestWorkBytes\s*;')
        PendingRecord=(Get-Count $p 'record\s+struct\s+PendingGuestWork\s*\(')
        EnqueueMethod=(Get-Count $p 'private\s+static\s+long\s+EnqueueGuestWorkLocked\s*\(')
        TakeRemoveMethod=(Get-Count $p 'private\s+static\s+void\s+RemoveTakenGuestWorkLocked\s*\(')
        RequeueMethod=(Get-Count $p 'private\s+static\s+bool\s+RequeueGuestWorkFront\s*\(')
        CompleteMethod=(Get-Count $p 'private\s+static\s+void\s+CompleteGuestWork\s*\(')
        ComputeCore=(Get-Count $p 'private\s+void\s+ExecuteComputeDispatchCore\s*\(')
        QueueBurstField=(Get-Count $p '_queueSubmissionBurstV74043')
        PreserveBatchField=(Get-Count $p '_preservePayloadBatchV7405620')
        SharedComputeField=(Get-Count $p '_computeSharedBatchV7405617')
        PayloadBatchMarker=(Get-Count $p 'PAYLOAD_BATCH_SUBMIT')
        SamplerAlias78=(Get-Count $p 'SHARPEMU_V74_0_78_3_PRESERVE_LEGACY_TEXTURE_CACHE_WRAPPER')
        DccV80=(Get-Count $p 'DCC_PROVENANCE_RECOVERY')
    }
    foreach($e in $checks.GetEnumerator()){Write-Host "$script:Tag $($e.Key)=$($e.Value)"}
    if($checks.PendingBytesField -ne 1){throw "$script:Tag _pendingGuestWorkBytes ambiguo/ausente."}
    if($checks.PendingRecord -ne 1){throw "$script:Tag PendingGuestWork ambiguo/ausente."}
    if($checks.EnqueueMethod -ne 1){throw "$script:Tag EnqueueGuestWorkLocked ambiguo/ausente."}
    if($checks.TakeRemoveMethod -ne 1){throw "$script:Tag RemoveTakenGuestWorkLocked ambiguo/ausente."}
    if($checks.RequeueMethod -ne 1){throw "$script:Tag RequeueGuestWorkFront ambiguo/ausente."}
    if($checks.CompleteMethod -ne 1){throw "$script:Tag CompleteGuestWork ambiguo/ausente."}
    if($checks.ComputeCore -ne 1){throw "$script:Tag ExecuteComputeDispatchCore ambiguo/ausente."}
    if($checks.QueueBurstField -lt 2){throw "$script:Tag V74.0.43 queue burst contract ausente."}
    if($checks.PreserveBatchField -lt 2){throw "$script:Tag V74.0.56.20 payload batch contract ausente."}
    if($checks.SharedComputeField -lt 2){throw "$script:Tag V74.0.56.17 compute shared batch contract ausente."}
    if($checks.PayloadBatchMarker -lt 1){throw "$script:Tag PAYLOAD_BATCH_SUBMIT diagnostic ausente."}
    return $p
}
function New-Backup{
    if(-not(Test-Path -LiteralPath $script:BackupRoot)){New-Item -ItemType Directory -Path $script:BackupRoot|Out-Null}
    $dir=Join-Path $script:BackupRoot ("DeepDrawSubmissionFlowV74081_"+(Get-Date -Format 'yyyyMMdd_HHmmss'))
    New-Item -ItemType Directory -Path $dir|Out-Null
    Copy-Item -LiteralPath $script:PresenterPath -Destination (Join-Path $dir 'VulkanVideoPresenter.cs') -Force
    Write-Utf8NoBom $script:StateFile $dir
    return $dir
}
function Restore-Backup([string]$Dir){$p=Join-Path $Dir 'VulkanVideoPresenter.cs';if(-not(Test-Path -LiteralPath $p)){throw "$script:Tag backup presenter ausente: $p"};Copy-Item -LiteralPath $p -Destination $script:PresenterPath -Force}
function Quote-ProcessArgument([string]$Value){if($null -eq $Value){return '""'};return '"'+($Value -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"'}
function Find-SharpEmuExe{
    $c=@(
      (Join-Path $script:RepoRoot 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'),
      (Join-Path $script:RepoRoot 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.CLI.exe'),
      (Join-Path $script:RepoRoot 'artifacts\bin\Release\net10.0\win-x64\SharpEmu.exe'),
      (Join-Path $script:RepoRoot 'artifacts\bin\Release\net10.0\win-x64\SharpEmu.CLI.exe'))
    foreach($x in $c){if(Test-Path -LiteralPath $x -PathType Leaf){return $x}}
    return $null
}
