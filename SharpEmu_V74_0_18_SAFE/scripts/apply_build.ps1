param([string]$RepositoryRoot="")
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "common.ps1")

$root=Resolve-RepoRootV74018 -RepositoryRoot $RepositoryRoot
& (Join-Path $PSScriptRoot "precheck.ps1") -RepositoryRoot $root

$direct=Get-DirectExecutionBackendPathV74018 -Root $root
$originalText=[System.IO.File]::ReadAllText($direct)
$initialState=Get-NativeMemcpyIntrinsicGateStateV74018 -Text $originalText
$backupRoot=$null
$backupDirect=$null

if($initialState.State -eq "Ready"){
    $stamp=Get-Date -Format "yyyyMMdd_HHmmss"
    $backupRoot=[System.IO.Path]::Combine(
        $root,".sharpemu-hotfix-backup","NativeMemcpyIntrinsic_V74_0_18_$stamp")
    [System.IO.Directory]::CreateDirectory($backupRoot)|Out-Null
    $backupDirect=[System.IO.Path]::Combine($backupRoot,"DirectExecutionBackend.cs")
    Copy-Item -LiteralPath $direct -Destination $backupDirect -Force
    try{
        $patchedText=Add-NativeMemcpyIntrinsicGateV74018 -Text $originalText
        $patchedState=Get-NativeMemcpyIntrinsicGateStateV74018 -Text $patchedText
        if($patchedState.State -ne "Applied"){
            throw "[V74.0.18] Post-transform state invalid: $($patchedState.State) / $($patchedState.Detail)"
        }
        [System.IO.File]::WriteAllText($direct,$patchedText,[System.Text.UTF8Encoding]::new($false))
        Write-Host "[V74.0.18] Native memcpy runtime gate installed in DirectExecutionBackend.cs."
        Write-Host "[V74.0.18] Default remains HLE-preferred; RUN_4 alone enables SHARPEMU_NATIVE_MEMCPY_INTRINSIC=1."
        Write-Host "[V74.0.18] Backup: $backupRoot"
    }
    catch{
        if($null -ne $backupDirect -and [System.IO.File]::Exists($backupDirect)){
            Copy-Item -LiteralPath $backupDirect -Destination $direct -Force
        }
        Write-Host "[V74.0.18] Apply failed; DirectExecutionBackend.cs restored."
        throw
    }
}
elseif($initialState.State -eq "Applied"){
    Write-Host "[V74.0.18] Native memcpy runtime gate already installed; building only."
}
else{
    throw "[V74.0.18] Unexpected state after PRECHECK: $($initialState.State)"
}

try{
    Write-Host "[V74.0.18] Building Release win-x64..."
    Invoke-DotNetCheckedV74018 -Root $root -Arguments @(
        "build","src\SharpEmu.CLI\SharpEmu.CLI.csproj",
        "-c","Release","-r","win-x64","--nologo")
    Sync-ReleaseRuntimeAssetsV74018 -Root $root
}
catch{
    if($null -ne $backupDirect -and [System.IO.File]::Exists($backupDirect)){
        Copy-Item -LiteralPath $backupDirect -Destination $direct -Force
        Write-Host "[V74.0.18] Build failed; DirectExecutionBackend.cs restored."
    }
    throw
}

$finalText=[System.IO.File]::ReadAllText($direct)
$finalState=Get-NativeMemcpyIntrinsicGateStateV74018 -Text $finalText
if($finalState.State -ne "Applied"){
    throw "[V74.0.18] FINAL native memcpy state invalid: $($finalState.State) / $($finalState.Detail)"
}
foreach($guard in @(
    "SHARPEMU_V74_0_18_NATIVE_MEMCPY_INTRINSIC",
    "SHARPEMU_NATIVE_MEMCPY_INTRINSIC",
    "allowNativeMemcpyV74018",
    "[V74.0.18][MEMCPY_FASTPATH]"
)){
    if(-not $finalText.Contains($guard)){throw "[V74.0.18] FINAL guard missing: $guard"}
}

$releaseDll=[System.IO.Path]::Combine($root,"artifacts","bin","Release","net10.0","win-x64","SharpEmu.dll")
if(-not [System.IO.File]::Exists($releaseDll)){
    throw "[V74.0.18] Release SharpEmu.dll missing after successful build: $releaseDll"
}
Write-Host "[V74.0.18] SUCCESS - native memcpy gate applied and Release build passed."
Write-Host "[V74.0.18] Next: RUN_4_DEMONS_MEMCPY_NATIVE_SCALE.cmd"
