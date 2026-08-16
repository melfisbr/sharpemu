param([string]$RepositoryRoot)
. (Join-Path $PSScriptRoot 'common.ps1')
$root=Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$pkg=Get-PackageRoot
& (Join-Path $PSScriptRoot 'validate.ps1') -PackageRoot $pkg

$sampler=Join-Path $root 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.GuestSampler.cs'
if(-not(Test-Path -LiteralPath $sampler -PathType Leaf)){throw('[V73.9] PRECHECK ERROR: missing {0}' -f $sampler)}
$text=[IO.File]::ReadAllText($sampler)
$baseline='9FEB4664DDA918AD46A8049161B6812A162EC3D07B7DD4632921282E03FEA1F3'
$hash=(Get-FileHash -LiteralPath $sampler -Algorithm SHA256).Hash
$installed=
    (Test-ContainsOrdinal -Text $text -Pattern 'SHARPEMU_TRACE_DEMONS_UI_METHODS') -and
    (Test-ContainsOrdinal -Text $text -Pattern '[V73.9][UI_RIP]')

if(-not $installed -and $hash -ne $baseline){
    throw('[V73.9] PRECHECK ERROR: GuestSampler baseline changed. expected={0} actual={1}. No source modified.' -f $baseline,$hash)
}

foreach($marker in @(
    'SHARPEMU_PROFILE_GUEST_RIP',
    'GuestRipSampleLoop()',
    'ReportGuestRipSamples(',
    'GuestImageBase'
)){
    if(-not(Test-ContainsOrdinal -Text $text -Pattern $marker)){
        throw('[V73.9] PRECHECK ERROR: GuestSampler structural marker missing: {0}' -f $marker)
    }
}
Write-Host '[V73.9] PRECHECK PASSED.'
Write-Host ('[V73.9] GuestSampler_SHA256={0}' -f $hash)
Write-Host ('[V73.9] ui_method_probe_installed={0}' -f $installed)
Write-Host '[V73.9] Probe is dormant unless SHARPEMU_TRACE_DEMONS_UI_METHODS=1.'
