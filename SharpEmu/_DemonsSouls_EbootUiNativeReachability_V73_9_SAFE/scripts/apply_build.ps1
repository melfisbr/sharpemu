param([string]$RepositoryRoot)
. (Join-Path $PSScriptRoot 'common.ps1')
$root=Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$pkg=Get-PackageRoot
& (Join-Path $PSScriptRoot 'precheck.ps1') -RepositoryRoot $root

$sampler=Join-Path $root 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.GuestSampler.cs'
$text=[IO.File]::ReadAllText($sampler)

if(Test-ContainsOrdinal -Text $text -Pattern 'SHARPEMU_TRACE_DEMONS_UI_METHODS'){
    Write-Host '[V73.9] UI RIP probe already installed; building current source.'
}else{
    $expected='9FEB4664DDA918AD46A8049161B6812A162EC3D07B7DD4632921282E03FEA1F3'
    $actual=(Get-FileHash -LiteralPath $sampler -Algorithm SHA256).Hash
    if($actual -ne $expected){throw('[V73.9] APPLY ERROR: GuestSampler changed after precheck. expected={0} actual={1}' -f $expected,$actual)}

    $stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupRoot=Join-Path $root ('.sharpemu-hotfix-backup\EbootUiNativeReachability_V73_9_{0}' -f $stamp)
    New-Item -ItemType Directory -Force -Path $backupRoot|Out-Null
    $backup=Join-Path $backupRoot 'DirectExecutionBackend.GuestSampler.cs'
    Copy-Item -LiteralPath $sampler -Destination $backup -Force

    try{
        Copy-Item -LiteralPath (Join-Path $pkg 'patch\DirectExecutionBackend.GuestSampler.cs') -Destination $sampler -Force
        $patched=[IO.File]::ReadAllText($sampler)
        foreach($marker in @(
            'SHARPEMU_TRACE_DEMONS_UI_METHODS',
            '[V73.9][UI_RIP] first_hit',
            '[V73.9][UI_RIP] counts',
            'StartMenuThink',
            'StartMenuHandleInputFocus'
        )){
            if(-not(Test-ContainsOrdinal -Text $patched -Pattern $marker)){throw('[V73.9] post-install marker missing: {0}' -f $marker)}
        }

        Push-Location $root
        try{
            Write-Host '[V73.9] Building SharpEmu.CLI Debug win-x64...'
            & dotnet build '.\src\SharpEmu.CLI\SharpEmu.CLI.csproj' -c Debug -r win-x64 --nologo
            $exit=$LASTEXITCODE
            if($exit -ne 0){throw('SharpEmu.CLI build failed with exit code {0}.' -f $exit)}
        }finally{Pop-Location}

        Write-Host '[V73.9] SUCCESS'
        Write-Host ('[V73.9] Backup: {0}' -f $backupRoot)
        Write-Host '[V73.9] Next: RUN_DEMONS_UI_NATIVE_REACHABILITY_V73_9.cmd'
        return
    }catch{
        if(Test-Path -LiteralPath $backup -PathType Leaf){
            Copy-Item -LiteralPath $backup -Destination $sampler -Force
            Write-Host '[V73.9] GuestSampler restored.'
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
Write-Host '[V73.9] SUCCESS (already installed)'
Write-Host '[V73.9] Next: RUN_DEMONS_UI_NATIVE_REACHABILITY_V73_9.cmd'
