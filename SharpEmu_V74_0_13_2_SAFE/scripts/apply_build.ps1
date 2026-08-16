param([string]$RepositoryRoot="")
. (Join-Path $PSScriptRoot "common.ps1")
$root=Resolve-RepoRoot $RepositoryRoot
& (Join-Path $PSScriptRoot "precheck.ps1") -RepositoryRoot $root
$hostMovieBridgePath=Get-HostMovieBridgePathV74013 $root
$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$backup=[System.IO.Path]::Combine($root,".sharpemu-hotfix-backup","FastBootPerfHandoff_V74_0_13_$stamp")
[System.IO.Directory]::CreateDirectory($backup)|Out-Null
$backupHost=[System.IO.Path]::Combine($backup,"HostMovieBridge.cs")
Copy-Item -LiteralPath $hostMovieBridgePath -Destination $backupHost -Force
try{
    Install-RobustStartupHandoffV74013 -Path $hostMovieBridgePath
    $text=[System.IO.File]::ReadAllText($hostMovieBridgePath)
    if(-not $text.Contains("SHARPEMU_V74_0_13_ROBUST_STARTUP_COMPLETION_HANDOFF") -or
       -not $text.Contains("startup_completion_shim_header_fallback")){
        throw "[V74.0.13.2] HostMovieBridge verification failed."
    }

    Write-Host "[V74.0.13.2] Robust startup completion handoff installed."
    Write-Host "[V74.0.13.2] Building Debug win-x64 (compatibility baseline)..."
    Invoke-DotNetChecked -Root $root -Arguments @("build","src\SharpEmu.CLI\SharpEmu.CLI.csproj","-c","Debug","-r","win-x64","--nologo")
    Write-Host "[V74.0.13.2] Building Release win-x64 (performance runtime)..."
    Invoke-DotNetChecked -Root $root -Arguments @("build","src\SharpEmu.CLI\SharpEmu.CLI.csproj","-c","Release","-r","win-x64","--nologo")
    Sync-ReleaseRuntimeAssetsV74013 -Root $root
}
catch{
    Copy-Item -LiteralPath $backupHost -Destination $hostMovieBridgePath -Force
    Write-Host "[V74.0.13.2] Apply/build failed; HostMovieBridge restored."
    throw
}
Write-Host "[V74.0.13.2] Backup: $backup"
Write-Host "[V74.0.13.2] SUCCESS"
Write-Host "[V74.0.13.2] Next: RUN_4_DEMONS_FASTBOOT_PERF_HANDOFF.cmd"
