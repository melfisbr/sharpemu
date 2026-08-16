param([string]$RepositoryRoot)
. (Join-Path $PSScriptRoot 'common.ps1')
$root = Resolve-RepoRoot $RepositoryRoot

& (Join-Path $PSScriptRoot 'precheck.ps1') -RepositoryRoot $root

Push-Location $root
try {
    & dotnet build '.\src\SharpEmu.Libs\SharpEmu.Libs.csproj' -c Debug --nologo
    if ($LASTEXITCODE -ne 0) { throw "SharpEmu.Libs build failed: $LASTEXITCODE" }

    & dotnet build '.\src\SharpEmu.CLI\SharpEmu.CLI.csproj' -c Debug -r win-x64 --nologo
    if ($LASTEXITCODE -ne 0) { throw "SharpEmu.CLI build failed: $LASTEXITCODE" }
}
finally {
    Pop-Location
}

Write-Host '[V61.23.3] SUCCESS'
Write-Host '[V61.23.3] No emulator source semantics changed.'
Write-Host '[V61.23.3] Runtime correction: full AGC/Shader/Vulkan-resource tracing removed from post-video performance test.'
