param([string]$RepositoryRoot="")
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "common.ps1")

$root=Resolve-RepoRootV74017 -RepositoryRoot $RepositoryRoot
& (Join-Path $PSScriptRoot "precheck.ps1") -RepositoryRoot $root

$pthread=Get-PthreadPathV74017 -Root $root
$originalText=[System.IO.File]::ReadAllText($pthread)
$initialState=Get-PthreadOpaqueOwnerGateStateV74017 -Text $originalText
$backupRoot=$null
$backupPthread=$null

if($initialState.State -eq "Ready"){
    $stamp=Get-Date -Format "yyyyMMdd_HHmmss"
    $backupRoot=[System.IO.Path]::Combine(
        $root,".sharpemu-hotfix-backup","PthreadOpaqueOwnerGate_V74_0_17_$stamp")
    [System.IO.Directory]::CreateDirectory($backupRoot)|Out-Null
    $backupPthread=[System.IO.Path]::Combine($backupRoot,"KernelPthreadCompatExports.cs")
    Copy-Item -LiteralPath $pthread -Destination $backupPthread -Force

    try{
        $patchedText=Add-PthreadOpaqueOwnerGateV74017 -Text $originalText
        $patchedState=Get-PthreadOpaqueOwnerGateStateV74017 -Text $patchedText
        if($patchedState.State -ne "Applied"){
            throw "[V74.0.17] Post-transform state invalid: $($patchedState.State) / $($patchedState.Detail)"
        }
        [System.IO.File]::WriteAllText(
            $pthread,$patchedText,[System.Text.UTF8Encoding]::new($false))
        Write-Host "[V74.0.17] Pthread opaque-owner runtime gate installed."
        Write-Host "[V74.0.17] Default behavior remains ENABLED; only RUN_4 sets SHARPEMU_PTHREAD_OPAQUE_OWNER_SYNC=0."
        Write-Host "[V74.0.17] Backup: $backupRoot"
    }
    catch{
        if($null -ne $backupPthread -and [System.IO.File]::Exists($backupPthread)){
            Copy-Item -LiteralPath $backupPthread -Destination $pthread -Force
        }
        Write-Host "[V74.0.17] Apply failed; pthread source restored."
        throw
    }
}
elseif($initialState.State -eq "Applied"){
    Write-Host "[V74.0.17] Pthread runtime gate already installed; building only."
}
else{
    throw "[V74.0.17] Unexpected state after PRECHECK: $($initialState.State)"
}

try{
    Write-Host "[V74.0.17] Building Release win-x64..."
    Invoke-DotNetCheckedV74017 -Root $root -Arguments @(
        "build","src\SharpEmu.CLI\SharpEmu.CLI.csproj",
        "-c","Release","-r","win-x64","--nologo")
    Sync-ReleaseRuntimeAssetsV74017 -Root $root
}
catch{
    if($null -ne $backupPthread -and [System.IO.File]::Exists($backupPthread)){
        Copy-Item -LiteralPath $backupPthread -Destination $pthread -Force
        Write-Host "[V74.0.17] Build failed; pthread source restored."
    }
    throw
}

$finalText=[System.IO.File]::ReadAllText($pthread)
$finalState=Get-PthreadOpaqueOwnerGateStateV74017 -Text $finalText
if($finalState.State -ne "Applied"){
    throw "[V74.0.17] FINAL pthread state invalid: $($finalState.State) / $($finalState.Detail)"
}
foreach($guard in @(
    "SHARPEMU_DBFZ_PTHREAD_OPAQUE_OWNER_SYNC_V1_4_5",
    "SHARPEMU_V74_0_17_DEMONS_PTHREAD_OPAQUE_OWNER_GATE",
    "SHARPEMU_PTHREAD_OPAQUE_OWNER_SYNC",
    "_v74017OpaqueOwnerSyncEnabled"
)){
    if(-not $finalText.Contains($guard)){
        throw "[V74.0.17] FINAL guard missing: $guard"
    }
}

$releaseDll=[System.IO.Path]::Combine(
    $root,"artifacts","bin","Release","net10.0","win-x64","SharpEmu.dll")
if(-not [System.IO.File]::Exists($releaseDll)){
    throw "[V74.0.17] Release SharpEmu.dll missing after successful build: $releaseDll"
}

Write-Host "[V74.0.17] SUCCESS - pthread gate applied and Release build passed."
Write-Host "[V74.0.17] Next: RUN_4_DEMONS_PTHREAD_FASTBOOT.cmd"
