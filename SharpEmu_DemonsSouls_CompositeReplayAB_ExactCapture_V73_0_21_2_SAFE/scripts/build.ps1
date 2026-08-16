param(
    [Parameter(Mandatory=$true)][string]$RepoRoot,
    [string]$Eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'
)
. ([IO.Path]::Combine($PSScriptRoot,'common.ps1'))

$repo=[IO.Path]::GetFullPath($RepoRoot)
$pkg=[IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'..'))

& ([IO.Path]::Combine($pkg,'scripts\validate.ps1'))
& ([IO.Path]::Combine($pkg,'scripts\precheck.ps1')) -RepoRoot $repo -Eboot $Eboot

$base=Resolve-SourceBase $repo
$presenter=[IO.Path]::Combine($base,'SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs')
$agc=[IO.Path]::Combine($base,'SharpEmu.Libs\Agc\AgcExports.cs')

$phBefore=(Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash
$ahBefore=(Get-FileHash -LiteralPath $agc -Algorithm SHA256).Hash

$libs=[IO.Path]::Combine($base,'SharpEmu.Libs\SharpEmu.Libs.csproj')
& dotnet restore $libs --nologo
if($LASTEXITCODE -ne 0){throw 'dotnet restore failed.'}
& dotnet build $libs -c Debug --no-restore --nologo
if($LASTEXITCODE -ne 0){throw 'SharpEmu.Libs build failed.'}

$cli=[IO.Path]::Combine($base,'SharpEmu.CLI\SharpEmu.CLI.csproj')
if([IO.File]::Exists($cli)){
    & dotnet build $cli -c Debug --nologo
    if($LASTEXITCODE -ne 0){throw 'SharpEmu.CLI build failed.'}
}

$phAfter=(Get-FileHash -LiteralPath $presenter -Algorithm SHA256).Hash
$ahAfter=(Get-FileHash -LiteralPath $agc -Algorithm SHA256).Hash

if($phAfter -ne $phBefore -or $ahAfter -ne $ahBefore){
    throw "READ-ONLY BUILD INVARIANT FAILED: source hash changed during build."
}

Write-Host '[V73.0.21.2] BUILD PASSED. Source hashes unchanged.' -ForegroundColor Green
Write-Host "Presenter SHA256: $phAfter"
Write-Host "AgcExports SHA256: $ahAfter"
