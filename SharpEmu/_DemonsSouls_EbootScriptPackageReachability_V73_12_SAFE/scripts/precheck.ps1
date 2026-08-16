param([string]$RepositoryRoot)
. (Join-Path $PSScriptRoot 'common.ps1')
$root=Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$pkg=Get-PackageRoot
& (Join-Path $PSScriptRoot 'validate.ps1') -PackageRoot $pkg

$sampler=Join-Path $root 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.GuestSampler.cs'
if(-not(Test-Path -LiteralPath $sampler -PathType Leaf)){
    throw('[V73.12] PRECHECK ERROR: missing {0}' -f $sampler)
}
$text=[IO.File]::ReadAllText($sampler)
$baseline='E0637FA5E749DADBFA61C6FA54B86F39358511A3E191052BDB915F4A76D7E88D'
$hash=(Get-FileHash -LiteralPath $sampler -Algorithm SHA256).Hash
$installed=
    (Test-ContainsOrdinal -Text $text -Pattern 'SHARPEMU_TRACE_DEMONS_SCRIPT_LOADER') -and
    (Test-ContainsOrdinal -Text $text -Pattern '[V73.12][SCRIPT_RIP]')

if(-not $installed -and $hash -ne $baseline){
    throw('[V73.12] PRECHECK ERROR: GuestSampler changed. expected={0} actual={1}. No source modified.' -f $baseline,$hash)
}

foreach($marker in @(
    'SHARPEMU_TRACE_DEMONS_UI_METHODS',
    'SHARPEMU_TRACE_DEMONS_ENTRY_WAIT',
    'SampleDemonsEntryThreadV7311()',
    '[V73.9][UI_RIP] counts'
)){
    if(-not(Test-ContainsOrdinal -Text $text -Pattern $marker)){
        throw('[V73.12] PRECHECK ERROR: cumulative sampler marker missing: {0}' -f $marker)
    }
}
Write-Host '[V73.12] PRECHECK PASSED.'
Write-Host ('[V73.12] GuestSampler_SHA256={0}' -f $hash)
Write-Host ('[V73.12] script_probe_installed={0}' -f $installed)
Write-Host '[V73.12] Probe is diagnostic only; no guest state is changed.'
