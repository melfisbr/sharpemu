param([string]$RepositoryRoot="")
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "common.ps1")

$repoRoot=Resolve-RepoRootV74021 -RepositoryRoot $RepositoryRoot
& (Join-Path $PSScriptRoot "precheck.ps1") -RepositoryRoot $repoRoot

$packageRoot=[System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$cpuPath=Get-CpuDispatcherPathV74021 -Root $repoRoot
$directPath=Get-DirectBackendPathV74021 -Root $repoRoot
$kernelPath=Get-KernelExportsPathV74021 -Root $repoRoot
$hostPath=Get-HostMovieBridgePathV74021 -Root $repoRoot

$hostHashBefore="missing"
if([System.IO.File]::Exists($hostPath)){$hostHashBefore=(Get-FileHash -LiteralPath $hostPath -Algorithm SHA256).Hash}

$cpuText=[System.IO.File]::ReadAllText($cpuPath)
$directText=[System.IO.File]::ReadAllText($directPath)
$kernelText=[System.IO.File]::ReadAllText($kernelPath)
$cpuState=Get-EntryAbiStateV74021 -Text $cpuText
$directState=Get-LleInitEnvStateV74021 -Text $directText
$kernelState=Get-InitEnvStateV74021 -Text $kernelText

$needsPatch=($cpuState -ne "Applied" -or $directState -ne "Applied" -or $kernelState -ne "Applied")
$backupDirectory=$null
$utf8NoBom=New-Object System.Text.UTF8Encoding($false)

if($needsPatch){
    $stamp=Get-Date -Format "yyyyMMdd_HHmmss"
    $backupDirectory=[System.IO.Path]::Combine($repoRoot,".sharpemu-hotfix-backup","EntryAbiV74_0_21_$stamp")
    [System.IO.Directory]::CreateDirectory($backupDirectory)|Out-Null
    Copy-Item -LiteralPath $cpuPath -Destination ([System.IO.Path]::Combine($backupDirectory,"CpuDispatcher.cs")) -Force
    Copy-Item -LiteralPath $directPath -Destination ([System.IO.Path]::Combine($backupDirectory,"DirectExecutionBackend.cs")) -Force
    Copy-Item -LiteralPath $kernelPath -Destination ([System.IO.Path]::Combine($backupDirectory,"KernelExports.cs")) -Force

    try{
        if($cpuState -eq "Baseline"){
            $cpuFragment=[System.IO.File]::ReadAllText([System.IO.Path]::Combine($packageRoot,"patch","CpuDispatcher.InitializeProcessEntryFrame.v74021.csfrag"))
            $cpuText=Replace-CSharpMethodV74021 -Text $cpuText -Signature "private static bool InitializeProcessEntryFrame(" -Replacement $cpuFragment
            $oldCall="InitializeProcessEntryFrame(context, processImageName, programExitHandlerStubAddress)"
            $newCall="InitializeProcessEntryFrame(context, processImageName, programExitHandlerStubAddress, entryPoint)"
            $callCount=([regex]::Matches($cpuText,[regex]::Escape($oldCall))).Count
            if($callCount -ne 1){throw "[V74.0.21] Expected one legacy process-entry call, found $callCount."}
            $cpuText=$cpuText.Replace($oldCall,$newCall)
            [System.IO.File]::WriteAllText($cpuPath,$cpuText,$utf8NoBom)
        }

        if($directState -eq "Baseline"){
            $directFragment=[System.IO.File]::ReadAllText([System.IO.Path]::Combine($packageRoot,"patch","DirectExecutionBackend.IsSafeLleLibcExport.v74021.csfrag"))
            $directText=Replace-CSharpMethodV74021 -Text $directText -Signature "private static bool IsSafeLleLibcExport(string exportName)" -Replacement $directFragment
            [System.IO.File]::WriteAllText($directPath,$directText,$utf8NoBom)
        }

        if($kernelState -eq "Baseline"){
            $kernelFragment=[System.IO.File]::ReadAllText([System.IO.Path]::Combine($packageRoot,"patch","KernelExports.InitEnv.v74021.csfrag"))
            $kernelText=Replace-CSharpMethodV74021 -Text $kernelText -Signature "public static int InitEnv(CpuContext ctx)" -Replacement $kernelFragment
            # Replace-CSharpMethod starts at the method signature, while the fragment includes the SysAbiExport attribute.
            # Remove the now-duplicated old attribute immediately before the replacement.
            $duplicatePattern='(?s)\[SysAbiExport\(\s*Nid = "bzQExy189ZI",\s*ExportName = "_init_env",\s*Target = Generation\.Gen4 \| Generation\.Gen5,\s*LibraryName = "libc"\)\]\s*(?=\[SysAbiExport\(\s*Nid = "bzQExy189ZI")'
            $kernelText=[regex]::Replace($kernelText,$duplicatePattern,"",1)
            [System.IO.File]::WriteAllText($kernelPath,$kernelText,$utf8NoBom)
        }

        $finalCpu=[System.IO.File]::ReadAllText($cpuPath)
        $finalDirect=[System.IO.File]::ReadAllText($directPath)
        $finalKernel=[System.IO.File]::ReadAllText($kernelPath)
        if((Get-EntryAbiStateV74021 -Text $finalCpu) -ne "Applied"){throw "[V74.0.21] CpuDispatcher post-patch verification failed."}
        if((Get-LleInitEnvStateV74021 -Text $finalDirect) -ne "Applied"){throw "[V74.0.21] DirectExecutionBackend post-patch verification failed."}
        if((Get-InitEnvStateV74021 -Text $finalKernel) -ne "Applied"){throw "[V74.0.21] KernelExports post-patch verification failed."}

        $hostHashAfter="missing"
        if([System.IO.File]::Exists($hostPath)){$hostHashAfter=(Get-FileHash -LiteralPath $hostPath -Algorithm SHA256).Hash}
        if($hostHashAfter -ne $hostHashBefore){throw "[V74.0.21] HostMovieBridge changed unexpectedly; refusing patch."}

        Write-Host "[V74.0.21] SOURCE PATCH APPLIED."
        Write-Host "[V74.0.21] Backup: $backupDirectory"
    } catch {
        if($backupDirectory){
            Copy-Item -LiteralPath ([System.IO.Path]::Combine($backupDirectory,"CpuDispatcher.cs")) -Destination $cpuPath -Force
            Copy-Item -LiteralPath ([System.IO.Path]::Combine($backupDirectory,"DirectExecutionBackend.cs")) -Destination $directPath -Force
            Copy-Item -LiteralPath ([System.IO.Path]::Combine($backupDirectory,"KernelExports.cs")) -Destination $kernelPath -Force
        }
        throw
    }
} else {
    Write-Host "[V74.0.21] Source correction already installed; build verification only."
}

try{
    Write-Host "[V74.0.21] Building Release win-x64..."
    Invoke-DotNetCheckedV74021 -Root $repoRoot -Arguments @(
        "build","src\SharpEmu.CLI\SharpEmu.CLI.csproj","-c","Release","-r","win-x64","--nologo")
    Sync-ReleaseRuntimeAssetsV74021 -Root $repoRoot
} catch {
    if($needsPatch -and $backupDirectory){
        Copy-Item -LiteralPath ([System.IO.Path]::Combine($backupDirectory,"CpuDispatcher.cs")) -Destination $cpuPath -Force
        Copy-Item -LiteralPath ([System.IO.Path]::Combine($backupDirectory,"DirectExecutionBackend.cs")) -Destination $directPath -Force
        Copy-Item -LiteralPath ([System.IO.Path]::Combine($backupDirectory,"KernelExports.cs")) -Destination $kernelPath -Force
        Write-Host "[V74.0.21] Build failed; all three modified source files restored from backup."
    }
    throw
}

$releaseDll=[System.IO.Path]::Combine($repoRoot,"artifacts","bin","Release","net10.0","win-x64","SharpEmu.dll")
if(-not [System.IO.File]::Exists($releaseDll)){throw "[V74.0.21] Release SharpEmu.dll missing after build: $releaseDll"}

$hostHashFinal="missing"
if([System.IO.File]::Exists($hostPath)){$hostHashFinal=(Get-FileHash -LiteralPath $hostPath -Algorithm SHA256).Hash}
if($hostHashFinal -ne $hostHashBefore){throw "[V74.0.21] HostMovieBridge hash changed during RUN_3."}

Write-Host "[V74.0.21] SUCCESS: EntryParams 0x118 + argv[33] + entry address + gated LLE _init_env installed."
Write-Host "[V74.0.21] HostMovieBridge preserved: $hostHashFinal"
Write-Host "[V74.0.21] Next: RUN_4_DEMONS_ENTRY_ABI_TEST.cmd"
