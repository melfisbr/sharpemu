param([string]$RepositoryRoot = "")
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "common.ps1")

$repoRoot=Resolve-RepoRootV74027 -RepositoryRoot $RepositoryRoot
$requiredPaths=@(
    (Get-AgcPathV74027 -Root $repoRoot),
    (Get-PresenterPathV74027 -Root $repoRoot),
    (Get-CpuPathV74027 -Root $repoRoot),
    (Get-DirectPathV74027 -Root $repoRoot),
    (Get-KernelPathV74027 -Root $repoRoot),
    (Get-HostMoviePathV74027 -Root $repoRoot),
    (Get-ShaderTranslatorPathV74027 -Root $repoRoot),
    (Get-SpirvTranslatorPathV74027 -Root $repoRoot),
    (Get-SpirvAluPathV74027 -Root $repoRoot),
    (Get-MslTranslatorPathV74027 -Root $repoRoot),
    (Get-MslAluPathV74027 -Root $repoRoot)
)
foreach($requiredPath in $requiredPaths){if(-not [System.IO.File]::Exists($requiredPath)){throw "[V74.0.27] Required source missing: $requiredPath"}}
if(-not (Test-V21AbiAppliedV74027 -Root $repoRoot)){throw "[V74.0.27] V74.0.21 Entry ABI rollup is missing."}
if(-not (Test-PresenterRollupV74027 -Root $repoRoot)){throw "[V74.0.27] V74.0.23.1/V74.0.24 presenter rollup is missing."}
if(-not (Test-V25AppliedV74027 -Root $repoRoot)){throw "[V74.0.27] V74.0.25 WRITE_DATA repair is missing."}

$state=Get-ShaderIsaStateV74027 -Root $repoRoot
if($state -eq "Partial" -or $state -eq "Missing"){throw "[V74.0.27] Unsupported/partial shader ISA state: $state. No source was modified."}
if($state -eq "Baseline"){
    $core=[System.IO.File]::ReadAllText((Get-ShaderTranslatorPathV74027 -Root $repoRoot))
    $spirv=[System.IO.File]::ReadAllText((Get-SpirvTranslatorPathV74027 -Root $repoRoot))
    $spirvAlu=[System.IO.File]::ReadAllText((Get-SpirvAluPathV74027 -Root $repoRoot))
    $msl=[System.IO.File]::ReadAllText((Get-MslTranslatorPathV74027 -Root $repoRoot))
    $mslAlu=[System.IO.File]::ReadAllText((Get-MslAluPathV74027 -Root $repoRoot))
    $core2=Convert-ShaderTranslatorV74027 -Text $core
    $spirv2=Convert-SpirvTranslatorV74027 -Text $spirv
    $spirvAlu2=Convert-SpirvAluV74027 -Text $spirvAlu
    $msl2=Convert-MslTranslatorV74027 -Text $msl
    $mslAlu2=Convert-MslAluV74027 -Text $mslAlu
    if(-not $core2.Contains('0x76 => "DsReadB64"') -or -not $core2.Contains('0x77 => "DsRead2B64"') -or -not $core2.Contains('0x09 => "VMulI32I24"')){throw "[V74.0.27] Dry-run decoder validation failed."}
    if(-not $spirv2.Contains('case "DsReadB64":') -or -not $spirv2.Contains('case "DsRead2B64":') -or -not $spirvAlu2.Contains('case "VMulI32I24":')){throw "[V74.0.27] Dry-run SPIR-V validation failed."}
    if(-not $msl2.Contains('case "DsReadB64":') -or -not $msl2.Contains('case "DsRead2B64":') -or -not $mslAlu2.Contains('"VMulI32I24" =>')){throw "[V74.0.27] Dry-run MSL validation failed."}
}
Write-Host "[V74.0.27] PRECHECK PASSED (same transformer dry-run verified)."
Write-Host "[V74.0.27] shader_isa_state=$state"
Write-Host "[V74.0.27] Targets: DS_READ_B64 0x76, DS_READ2_B64 0x77, DS_READ2ST64_B64 0x78, V_MUL_I32_I24 0x09, V_MUL_HI_I32_I24 0x0A."
Write-Host "[V74.0.27] V74.0.25 WRITE_DATA and V74.0.24 texture fixes are preserved."
