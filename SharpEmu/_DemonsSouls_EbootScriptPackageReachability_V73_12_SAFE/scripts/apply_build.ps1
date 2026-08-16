param([string]$RepositoryRoot)
. (Join-Path $PSScriptRoot 'common.ps1')
$root=Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$pkg=Get-PackageRoot
& (Join-Path $PSScriptRoot 'precheck.ps1') -RepositoryRoot $root

$sampler=Join-Path $root 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.GuestSampler.cs'
$current=[IO.File]::ReadAllText($sampler)

if(Test-ContainsOrdinal -Text $current -Pattern 'SHARPEMU_TRACE_DEMONS_SCRIPT_LOADER'){
    Write-Host '[V73.12] Script-package probe already installed; building current source.'
}else{
    $expected='E0637FA5E749DADBFA61C6FA54B86F39358511A3E191052BDB915F4A76D7E88D'
    $actual=(Get-FileHash -LiteralPath $sampler -Algorithm SHA256).Hash
    if($actual -ne $expected){
        throw('[V73.12] APPLY ERROR: source changed after precheck. expected={0} actual={1}' -f $expected,$actual)
    }

    $stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupRoot=Join-Path $root ('.sharpemu-hotfix-backup\EbootScriptPackageReachability_V73_12_{0}' -f $stamp)
    New-Item -ItemType Directory -Force -Path $backupRoot|Out-Null
    $backup=Join-Path $backupRoot 'DirectExecutionBackend.GuestSampler.cs'
    Copy-Item -LiteralPath $sampler -Destination $backup -Force

    try{
        Copy-Item -LiteralPath (Join-Path $pkg 'patch\DirectExecutionBackend.GuestSampler.cs') -Destination $sampler -Force
        $patched=[IO.File]::ReadAllText($sampler)
        foreach($marker in @(
            'SHARPEMU_TRACE_DEMONS_SCRIPT_LOADER',
            '[V73.12][SCRIPT_RIP] first_hit',
            '[V73.12][SCRIPT_RIP] counts',
            'StartMenuLoaderSourceRegion',
            'ShowHUDSceneImplExact'
        )){
            if(-not(Test-ContainsOrdinal -Text $patched -Pattern $marker)){
                throw('[V73.12] post-install marker missing: {0}' -f $marker)
            }
        }

        Push-Location $root
        try{
            Write-Host '[V73.12] Building SharpEmu.CLI Debug win-x64...'
            & dotnet build '.\src\SharpEmu.CLI\SharpEmu.CLI.csproj' -c Debug -r win-x64 --nologo
            $exit=$LASTEXITCODE
            if($exit -ne 0){throw('SharpEmu.CLI build failed with exit code {0}.' -f $exit)}
        }finally{Pop-Location}

        Write-Host '[V73.12] SUCCESS'
        Write-Host ('[V73.12] Backup: {0}' -f $backupRoot)
        Write-Host '[V73.12] Main entry thread is now sampled by UI/script probes without enabling ENTRY_WAIT.'
        Write-Host '[V73.12] Next: RUN_DEMONS_SCRIPT_PACKAGE_REACHABILITY_V73_12.cmd'
        return
    }catch{
        if(Test-Path -LiteralPath $backup -PathType Leaf){
            Copy-Item -LiteralPath $backup -Destination $sampler -Force
            Write-Host '[V73.12] GuestSampler restored.'
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
Write-Host '[V73.12] SUCCESS (already installed)'
Write-Host '[V73.12] Next: RUN_DEMONS_SCRIPT_PACKAGE_REACHABILITY_V73_12.cmd'
