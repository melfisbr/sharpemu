param([string]$RepositoryRoot)
. (Join-Path $PSScriptRoot 'common.ps1')
$root=Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$pkg=Get-PackageRoot
& (Join-Path $PSScriptRoot 'validate.ps1') -PackageRoot $pkg

$direct=Join-Path $root 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.cs'
$sampler=Join-Path $root 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.GuestSampler.cs'
$ampr=Join-Path $root 'src\SharpEmu.Libs\Ampr\AmprExports.cs'
$kernel=Join-Path $root 'src\SharpEmu.Libs\Kernel\KernelMemoryCompatExports.cs'

foreach($path in @($direct,$sampler,$ampr,$kernel)){
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){
        throw('[V73.11.1] PRECHECK ERROR: missing {0}' -f $path)
    }
}

$directText=[IO.File]::ReadAllText($direct)
$samplerText=[IO.File]::ReadAllText($sampler)
$amprText=[IO.File]::ReadAllText($ampr)
$kernelText=[IO.File]::ReadAllText($kernel)

if(Test-ContainsOrdinal -Text $directText -Pattern 'SHARPEMU_V73_10_USLEEP_SCHEDULER_HLE'){
    throw '[V73.11.1] PRECHECK ERROR: V73.10 usleep preference is still present. Apply V73.11 first.'
}

foreach($marker in @(
    'SHARPEMU_TRACE_DEMONS_ENTRY_WAIT',
    '[V73.11][ENTRY_WAIT]',
    'SHARPEMU_TRACE_DEMONS_UI_METHODS',
    '[V73.9][UI_RIP] counts'
)){
    if(-not(Test-ContainsOrdinal -Text $samplerText -Pattern $marker)){
        throw('[V73.11.1] PRECHECK ERROR: cumulative sampler marker missing: {0}' -f $marker)
    }
}

foreach($marker in @(
    'sceAmprAprCommandBufferReadFile',
    'TraceAmprRead('
)){
    if(-not(Test-ContainsOrdinal -Text $amprText -Pattern $marker)){
        throw('[V73.11.1] PRECHECK ERROR: AMPR marker missing: {0}' -f $marker)
    }
}

foreach($marker in @(
    'sceKernelAprResolveFilepathsToIdsAndFileSizes',
    'TryResolveAprFilepath('
)){
    if(-not(Test-ContainsOrdinal -Text $kernelText -Pattern $marker)){
        throw('[V73.11.1] PRECHECK ERROR: APR marker missing: {0}' -f $marker)
    }
}

Write-Host '[V73.11.1] PRECHECK PASSED.'
Write-Host '[V73.11.1] No repository source will be modified.'
Write-Host '[V73.11.1] The run waits for uistartmenu.cgpr instead of using the V73.11 early timeout.'
