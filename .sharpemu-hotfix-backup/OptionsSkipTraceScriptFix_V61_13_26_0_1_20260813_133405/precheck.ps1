. (Join-Path $PSScriptRoot 'common.ps1')
$root=Resolve-RepoRoot $RepositoryRoot
$files=Get-SourceFiles $root
$host=Join-Path $root 'src\SharpEmu.Libs\Media\HostMovieBridge.cs'
if(-not(Test-Path -LiteralPath $host)){throw "[V61.13.26.0] Required source missing: $host"}
$hostText=[IO.File]::ReadAllText($host)
foreach($m in @('RunConfiguredBootSequence','ObserveMovie','bink2.direct_boot')){
    if($hostText.IndexOf($m,[StringComparison]::OrdinalIgnoreCase)-lt 0){throw "[V61.13.26.0] HostMovieBridge marker missing: $m"}
}
$matches=Find-SourceMatches $files @('Keyboard controls are active','Tab','Options','scePadRead','scePadReadState')
Write-Host "[V61.13.26.0] Input/pad relevant matches=$($matches.Count)"
foreach($m in $matches|Select-Object -First 30){Write-Host "[V61.13.26.0][SOURCE] pattern='$($m.Pattern)' file='$($m.File)'"}
$project=Join-Path $root 'src\SharpEmu.Libs\SharpEmu.Libs.csproj'
if(-not(Test-Path -LiteralPath $project)){throw "[V61.13.26.0] SharpEmu.Libs project missing: $project"}
Write-Host '[V61.13.26.0] PRECHECK PASSED.'
