param([Parameter(Mandatory=$true)][string]$Root)
. (Join-Path $PSScriptRoot 'common.ps1')

if(-not(Test-Path -LiteralPath $Root -PathType Container)){
    throw "$script:Tag search root missing: $Root"
}

Write-Tag "SearchRoot=$Root"
$files=@(
    Get-ChildItem -LiteralPath $Root -Filter 'bink2w64.dll' -File -Recurse -ErrorAction SilentlyContinue
)
if($files.Count -eq 0){
    Write-Tag 'SearchResult=NOT_FOUND'
    exit 0
}

$accepted=$null
foreach($file in $files){
    $runtimeProbe=Test-BinkRuntime $file.FullName
    Write-Tag "SearchCandidate='$($file.FullName)' x64=$($runtimeProbe.IsX64) exports_ok=$($runtimeProbe.ExportsOk)"
    if($runtimeProbe.IsX64 -and $runtimeProbe.ExportsOk -and $null -eq $accepted){
        $accepted=$file.FullName
    }
}

if($null -eq $accepted){
    Write-Tag 'CompatibleSearchResult=NOT_FOUND'
    exit 0
}

& (Join-Path $PSScriptRoot 'probe_runtime.ps1') -RuntimeDll $accepted
exit $LASTEXITCODE
