param([string]$RepositoryRoot)

. (Join-Path $PSScriptRoot 'common.ps1')
$root=Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$pkg=Get-PackageRoot
& (Join-Path $PSScriptRoot 'validate.ps1') -PackageRoot $pkg

$agc=Join-Path $root 'src\SharpEmu.Libs\Agc\AgcExports.cs'
$presenter=Join-Path $root 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'

foreach($path in @($agc,$presenter)){
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){
        throw('[V73.6] PRECHECK ERROR: missing {0}' -f $path)
    }
}

$agcText=[IO.File]::ReadAllText($agc)
$presenterText=[IO.File]::ReadAllText($presenter)

foreach($marker in @(
    'SHARPEMU_TRACE_SCANOUT_LINEAGE',
    'SHARPEMU_RENDER_CHECKPOINTS',
    'SHARPEMU_TRACE_DCC_ALIAS',
    'TraceScanoutLineage(',
    'TrySubmitOrderedGuestImageFlip(',
    'requiresGpuBufferReadback: false',
    'SHARPEMU_TRACE_LABEL_PROVENANCE'
)){
    if(-not(Test-ContainsOrdinal -Text $agcText -Pattern $marker)){
        throw('[V73.6] PRECHECK ERROR: AGC marker missing: {0}' -f $marker)
    }
}

foreach($marker in @(
    'RequiresQueueCompletionOnly',
    'RequiresGpuToCpuVisibility: requiresGpuToCpuVisibility)'
)){
    if(-not(Test-ContainsOrdinal -Text $presenterText -Pattern $marker)){
        throw('[V73.6] PRECHECK ERROR: V73.3/V73.5 presenter marker missing: {0}' -f $marker)
    }
}

Write-Host '[V73.6] PRECHECK PASSED.'
Write-Host ('[V73.6] AgcExports_SHA256={0}' -f (Get-FileHash -LiteralPath $agc -Algorithm SHA256).Hash)
Write-Host ('[V73.6] VulkanVideoPresenter_SHA256={0}' -f (Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash)
Write-Host '[V73.6] V73.3 and V73.5 semantics are present.'
Write-Host '[V73.6] Evidence-only run: no source mutation and no forced scanout recovery.'
