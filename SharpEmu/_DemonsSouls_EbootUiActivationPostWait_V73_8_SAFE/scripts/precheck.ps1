param([string]$RepositoryRoot)

. (Join-Path $PSScriptRoot 'common.ps1')
$root=Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$pkg=Get-PackageRoot
& (Join-Path $PSScriptRoot 'validate.ps1') -PackageRoot $pkg

$paths=@{
    Agc=Join-Path $root 'src\SharpEmu.Libs\Agc\AgcExports.cs'
    Presenter=Join-Path $root 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
    Pad=Join-Path $root 'src\SharpEmu.Libs\Pad\PadExports.cs'
    Keyboard=Join-Path $root 'src\SharpEmu.Libs\Pad\KeyboardPadMapping.cs'
    MovieSkip=Join-Path $root 'src\SharpEmu.Libs\Media\HostOptionsSkipBridgeV6113262.cs'
}
foreach($path in $paths.Values){
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw('[V73.8] PRECHECK ERROR: missing {0}' -f $path)}
}

$agc=[IO.File]::ReadAllText($paths.Agc)
$presenter=[IO.File]::ReadAllText($paths.Presenter)
$pad=[IO.File]::ReadAllText($paths.Pad)
$keyboard=[IO.File]::ReadAllText($paths.Keyboard)

foreach($m in @(
    'SHARPEMU_TRACE_LABEL_PROVENANCE',
    '[V73.4][LABEL]',
    'requiresGpuBufferReadback: false',
    'TraceScanoutLineage('
)){
    if(-not(Test-ContainsOrdinal -Text $agc -Pattern $m)){
        throw('[V73.8] PRECHECK ERROR: cumulative AGC marker missing: {0}' -f $m)
    }
}

foreach($m in @(
    'RequiresQueueCompletionOnly',
    'RequiresGpuToCpuVisibility: requiresGpuToCpuVisibility)',
    'PRODUCER_PRIORITY'
)){
    if(-not(Test-ContainsOrdinal -Text $presenter -Pattern $m)){
        throw('[V73.8] PRECHECK ERROR: cumulative presenter marker missing: {0}' -f $m)
    }
}

foreach($m in @(
    'SHARPEMU_AUTO_OPTIONS',
    'IsAutoOptionsActive()',
    'buttons |= OrbisPadButton.Options'
)){
    if(-not(Test-ContainsOrdinal -Text $pad -Pattern $m)){
        throw('[V73.8] PRECHECK ERROR: pad Options diagnostic marker missing: {0}' -f $m)
    }
}

foreach($m in @(
    '0x09',
    'Options.KeyboardMapping.Action.Options'
)){
    if(-not(Test-ContainsOrdinal -Text $keyboard -Pattern $m)){
        throw('[V73.8] PRECHECK ERROR: keyboard Options mapping marker missing: {0}' -f $m)
    }
}

Write-Host '[V73.8] PRECHECK PASSED.'
Write-Host '[V73.8] Filesystem/APR/AMPR is already proven clean by V73.7.1.'
Write-Host '[V73.8] V73.4 label provenance, V73.5 WRITE_DATA and V73.0.14 producer priority are present.'
Write-Host '[V73.8] Pad auto-Options and Tab->Options mapping are present.'
Write-Host '[V73.8] No repository source will be modified.'
