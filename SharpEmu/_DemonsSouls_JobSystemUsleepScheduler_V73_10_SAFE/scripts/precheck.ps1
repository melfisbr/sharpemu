param([string]$RepositoryRoot)
. (Join-Path $PSScriptRoot 'common.ps1')
$root=Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$pkg=Get-PackageRoot
& (Join-Path $PSScriptRoot 'validate.ps1') -PackageRoot $pkg

$direct=Join-Path $root 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.cs'
$sampler=Join-Path $root 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.GuestSampler.cs'
$kernel=Join-Path $root 'src\SharpEmu.Libs\Kernel\KernelRuntimeCompatExports.cs'

foreach($path in @($direct,$sampler,$kernel)){
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw('[V73.10] PRECHECK ERROR: missing {0}' -f $path)}
}

$directText=[IO.File]::ReadAllText($direct)
$samplerText=[IO.File]::ReadAllText($sampler)
$kernelText=[IO.File]::ReadAllText($kernel)
$baseline='5BD0229D97C3862EDC5736D65E41BE3F062A5B9D31B5396EE28F58086D4B1DA8'
$hash=(Get-FileHash -LiteralPath $direct -Algorithm SHA256).Hash
$installed=Test-ContainsOrdinal -Text $directText -Pattern 'SHARPEMU_V73_10_USLEEP_SCHEDULER_HLE'

if(-not $installed -and $hash -ne $baseline){
    throw('[V73.10] PRECHECK ERROR: DirectExecutionBackend baseline changed. expected={0} actual={1}. No source modified.' -f $baseline,$hash)
}

foreach($marker in @(
    'TryCreateNativeImportIntrinsic(',
    'IsHlePreferredNid(',
    '"1jfXLRVzisc" =>',
    'IsLeafImport('
)){
    if(-not(Test-ContainsOrdinal -Text $directText -Pattern $marker)){
        throw('[V73.10] PRECHECK ERROR: direct import marker missing: {0}' -f $marker)
    }
}

foreach($marker in @(
    'SHARPEMU_TRACE_DEMONS_UI_METHODS',
    '[V73.9][UI_RIP] counts'
)){
    if(-not(Test-ContainsOrdinal -Text $samplerText -Pattern $marker)){
        throw('[V73.10] PRECHECK ERROR: V73.9 sampler marker missing: {0}' -f $marker)
    }
}

foreach($marker in @(
    'Nid = "1jfXLRVzisc"',
    'ExportName = "sceKernelUsleep"',
    'GuestThreadExecution.Scheduler?.Pump(ctx, "sceKernelUsleep")'
)){
    if(-not(Test-ContainsOrdinal -Text $kernelText -Pattern $marker)){
        throw('[V73.10] PRECHECK ERROR: KernelUsleep scheduling marker missing: {0}' -f $marker)
    }
}

Write-Host '[V73.10] PRECHECK PASSED.'
Write-Host ('[V73.10] DirectExecutionBackend_SHA256={0}' -f $hash)
Write-Host ('[V73.10] usleep_scheduler_hle_installed={0}' -f $installed)
Write-Host '[V73.10] V73.9 UI RIP probe is preserved.'
Write-Host '[V73.10] KernelUsleep scheduler Pump implementation is present.'
