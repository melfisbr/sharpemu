param([string]$RepositoryRoot)
. (Join-Path $PSScriptRoot 'common.ps1')
$root=Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$pkg=Get-PackageRoot
& (Join-Path $PSScriptRoot 'precheck.ps1') -RepositoryRoot $root

$direct=Join-Path $root 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.cs'
$current=[IO.File]::ReadAllText($direct)
if(Test-ContainsOrdinal -Text $current -Pattern 'SHARPEMU_V73_10_USLEEP_SCHEDULER_HLE'){
    Write-Host '[V73.10] sceKernelUsleep HLE scheduling fix already installed; building current source.'
}else{
    $expected='5BD0229D97C3862EDC5736D65E41BE3F062A5B9D31B5396EE28F58086D4B1DA8'
    $actual=(Get-FileHash -LiteralPath $direct -Algorithm SHA256).Hash
    if($actual -ne $expected){throw('[V73.10] APPLY ERROR: source changed after precheck. expected={0} actual={1}' -f $expected,$actual)}

    $stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupRoot=Join-Path $root ('.sharpemu-hotfix-backup\JobSystemUsleepScheduler_V73_10_{0}' -f $stamp)
    New-Item -ItemType Directory -Force -Path $backupRoot|Out-Null
    $backup=Join-Path $backupRoot 'DirectExecutionBackend.cs'
    Copy-Item -LiteralPath $direct -Destination $backup -Force
    try{
        Copy-Item -LiteralPath (Join-Path $pkg 'patch\DirectExecutionBackend.cs') -Destination $direct -Force
        $patched=[IO.File]::ReadAllText($direct)
        foreach($marker in @(
            'SHARPEMU_V73_10_USLEEP_SCHEDULER_HLE',
            'string.Equals(nid, "1jfXLRVzisc", StringComparison.Ordinal)',
            'return true;'
        )){
            if(-not(Test-ContainsOrdinal -Text $patched -Pattern $marker)){throw('[V73.10] post-install marker missing: {0}' -f $marker)}
        }

        Push-Location $root
        try{
            Write-Host '[V73.10] Building SharpEmu.CLI Debug win-x64...'
            & dotnet build '.\src\SharpEmu.CLI\SharpEmu.CLI.csproj' -c Debug -r win-x64 --nologo
            $exit=$LASTEXITCODE
            if($exit -ne 0){throw('SharpEmu.CLI build failed with exit code {0}.' -f $exit)}
        }finally{Pop-Location}

        Write-Host '[V73.10] SUCCESS'
        Write-Host ('[V73.10] Backup: {0}' -f $backupRoot)
        Write-Host '[V73.10] sceKernelUsleep now reaches KernelUsleep HLE and GuestThreadExecution.Scheduler.Pump.'
        Write-Host '[V73.10] Next: RUN_DEMONS_JOB_UI_DIAGNOSTIC_V73_10.cmd'
        return
    }catch{
        if(Test-Path -LiteralPath $backup -PathType Leaf){
            Copy-Item -LiteralPath $backup -Destination $direct -Force
            Write-Host '[V73.10] DirectExecutionBackend.cs restored.'
        }
        throw
    }
}

Push-Location $root
try{
    & dotnet build '.\src\SharpEmu.CLI\SharpEmu.CLI.csproj' -c Debug -r win-x64 --nologo
    $exit=$LASTEXITCODE
    if($exit -ne 0){throw('SharpEmu.CLI build failed with exit code {0}.' -f $exit)}
}finally{Pop-Location}
Write-Host '[V73.10] SUCCESS (already installed)'
Write-Host '[V73.10] Next: RUN_DEMONS_JOB_UI_DIAGNOSTIC_V73_10.cmd'
