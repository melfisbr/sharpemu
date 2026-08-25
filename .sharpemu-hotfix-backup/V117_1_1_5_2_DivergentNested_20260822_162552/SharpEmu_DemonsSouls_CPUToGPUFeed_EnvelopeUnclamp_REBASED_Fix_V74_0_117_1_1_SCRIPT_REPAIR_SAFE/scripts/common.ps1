$ErrorActionPreference='Stop'
$script:Tag='[V74.0.117.1.1-SCRIPT-REPAIR]'
$script:OriginalFolderName='SharpEmu_DemonsSouls_CPUToGPUFeed_EnvelopeUnclamp_REBASED_Fix_V74_0_117_1_SAFE'

function Write-Tag([string]$m){ Write-Host "$script:Tag $m" }

function PackageRoot { Split-Path -Parent $PSScriptRoot }
function PatchesRoot { Split-Path -Parent (PackageRoot) }

function OriginalRoot {
    $p=Join-Path (PatchesRoot) $script:OriginalFolderName
    if(-not(Test-Path -LiteralPath $p)){
        throw "$script:Tag original V117.1 folder not found: $p"
    }
    return $p
}

function Assert-OriginalLayout {
    $o=OriginalRoot
    foreach($rel in @(
        'scripts\patch_envelope.ps1',
        'scripts\precheck.ps1',
        'RUN_2_PRECHECK.cmd',
        'RUN_3_APPLY_BUILD.cmd',
        'RUN_4_TEST_DEMONS_CPU_GPU_FEED.cmd',
        'RUN_5_ANALYZE_LATEST.cmd'
    )){
        if(-not(Test-Path -LiteralPath (Join-Path $o $rel))){
            throw "$script:Tag required original V117.1 file missing: $rel"
        }
    }
}

function Parse-PowerShellTree([string]$Root){
    Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.ps1' | ForEach-Object {
        $tok=$null
        $err=$null
        [void][System.Management.Automation.Language.Parser]::ParseFile(
            $_.FullName,[ref]$tok,[ref]$err)
        if($err.Count -gt 0){
            throw "$script:Tag PowerShell parse failed: $($_.FullName): $($err[0].Message)"
        }
    }
}

function Invoke-OriginalCmd([string]$Name){
    $o=OriginalRoot
    $cmd=Join-Path $o $Name
    if(-not(Test-Path -LiteralPath $cmd)){
        throw "$script:Tag original command missing: $cmd"
    }
    Write-Tag "Invoking original: $Name"
    & $cmd
    if($LASTEXITCODE -ne 0){
        throw "$script:Tag original $Name failed exit=$LASTEXITCODE"
    }
}
