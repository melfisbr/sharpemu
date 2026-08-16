param([string]$RepositoryRoot)
. (Join-Path $PSScriptRoot 'common.ps1')
$r=Resolve-Repo $RepositoryRoot
& (Join-Path $PSScriptRoot 'precheck.ps1') -RepositoryRoot $r

# No new source mutation is needed: the current checkout already contains the
# correct fallback recovery path. Build to guarantee the current source and
# executable are synchronized before the test.
Push-Location $r
try{
    & dotnet build '.\src\SharpEmu.Libs\SharpEmu.Libs.csproj' -c Debug --nologo
    if($LASTEXITCODE-ne 0){throw "SharpEmu.Libs build failed: $LASTEXITCODE"}
    & dotnet build '.\src\SharpEmu.CLI\SharpEmu.CLI.csproj' -c Debug -r win-x64 --nologo
    if($LASTEXITCODE-ne 0){throw "SharpEmu.CLI build failed: $LASTEXITCODE"}
}finally{Pop-Location}
Write-Host '[V61.24.3] SUCCESS'
Write-Host '[V61.24.3] Current fallback chroma recovery retained; no duplicate source patch installed.'
