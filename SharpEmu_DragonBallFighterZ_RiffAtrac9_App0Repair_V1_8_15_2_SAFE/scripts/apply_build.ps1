. (Join-Path $PSScriptRoot "common.ps1")
& (Join-Path $PSScriptRoot "precheck.ps1")
$repo=Find-RepoRoot
$ngs=Join-Path $repo "src\SharpEmu.Libs\Ngs2\Ngs2Exports.cs"
$kernel=Join-Path $repo "src\SharpEmu.Libs\Kernel\KernelMemoryCompatExports.cs"
$nt=Get-Content -LiteralPath $ngs -Raw
$kt=Get-Content -LiteralPath $kernel -Raw

if($nt.Contains('SHARPEMU_DBFZ_RIFF_ATRAC9_PRESERVE_V1_8_15_1') -and
   $kt.Contains('SHARPEMU_DBFZ_FULL_APP0_WRITE_V1_8_15_1')){
    Write-Host "[DBFZ-RIFF-18152] Source changes=None (V1.8.15.1 already applied)."
    Write-Host "[DBFZ-RIFF-18152] Rebuilding only."
} else {
    throw "V1.8.15.2 is an idempotent validation/continuation package. Apply V1.8.15.1 first if State=NeedsV1_8_15_1Apply."
}

Push-Location $repo
try {
    dotnet build .\src\SharpEmu.CLI\SharpEmu.CLI.csproj -c Debug -r win-x64 --nologo
    if($LASTEXITCODE -ne 0){throw "dotnet build failed with exit code $LASTEXITCODE"}
} finally {Pop-Location}
Write-Host "[DBFZ-RIFF-18152] BUILD PASSED."
