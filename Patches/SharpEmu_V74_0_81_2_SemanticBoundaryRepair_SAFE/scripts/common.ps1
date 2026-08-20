param([Parameter(Mandatory=$true)][string]$PackageRoot)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$script:Tag='[V74.0.81.2]'
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
        V81Overall=(Get-Count $p 'SHARPEMU_V74_0_81_DEEP_DRAW_SUBMISSION_FLOW')
        V81Burst=(Get-Count $p 'SHARPEMU_V74_0_81_BOUNDED_QUEUE_BURST')
        V81Split=(Get-Count $p 'SHARPEMU_V74_0_81_QUEUE_INFLIGHT_SPLIT')
        V81FlushRepair=(Get-Count $p 'SHARPEMU_V74_0_81_COMPUTE_BATCH_FLUSH_REPAIR')
        ComputeCore=(Get-Count $p 'private\s+void\s+ExecuteComputeDispatchCore\s*\(')
        QueueBurstField=(Get-Count $p '_queueSubmissionBurstV74043')
        PreserveBatchField=(Get-Count $p '_preservePayloadBatchV7405620')
        SharedComputeField=(Get-Count $p '_computeSharedBatchV7405617')
        PayloadBatchMarker=(Get-Count $p 'PAYLOAD_BATCH_SUBMIT')
        V81Correction=(Get-Count $p 'SHARPEMU_V74_0_81_2_SEMANTIC_BOUNDARY_REPAIR')
        DccV80=(Get-Count $p 'DCC_PROVENANCE_RECOVERY')
    }
    foreach($e in $checks.GetEnumerator()){Write-Host "$script:Tag $($e.Key)=$($e.Value)"}
    if($checks.ComputeCore -ne 1){throw "$script:Tag ExecuteComputeDispatchCore ambiguo/ausente."}
    if($checks.QueueBurstField -lt 2){throw "$script:Tag queue burst contract ausente."}
    if($checks.PreserveBatchField -lt 2){throw "$script:Tag payload batch contract ausente."}
    if($checks.SharedComputeField -lt 2){throw "$script:Tag compute shared batch contract ausente."}
    if($checks.PayloadBatchMarker -lt 1){throw "$script:Tag PAYLOAD_BATCH_SUBMIT diagnostic ausente."}
    if($checks.V81Correction -eq 0){
        if($checks.V81Overall -lt 1 -or $checks.V81Burst -lt 1 -or $checks.V81Split -lt 1 -or $checks.V81FlushRepair -lt 1){
            throw "$script:Tag V74.0.81 completa nao foi detectada. Esta revisao e uma correcao aplicada por cima da V81."
        }
    }
    return $p
}
function New-Backup{
    if(-not(Test-Path -LiteralPath $script:BackupRoot)){New-Item -ItemType Directory -Path $script:BackupRoot|Out-Null}
    $dir=Join-Path $script:BackupRoot ("SemanticBoundaryRepairV740812_"+(Get-Date -Format 'yyyyMMdd_HHmmss'))
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
