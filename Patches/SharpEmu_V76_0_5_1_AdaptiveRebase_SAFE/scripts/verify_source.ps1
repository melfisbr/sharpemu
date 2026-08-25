param(
    [string]$RepoRoot = 'C:\Users\Edpo\Documents\GitHub\sharpemu',
    [string]$PatchesRoot = 'C:\Users\Edpo\Documents\GitHub\sharpemu\Patches'
)
. (Join-Path $PSScriptRoot 'common.ps1')
$repo = Get-RepoRoot $RepoRoot
$patches = Get-PatchesRoot $PatchesRoot
Assert-InstalledMarkers $repo

$extra = New-Object System.Collections.Generic.List[string]
$soft = Join-Path $repo 'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.SoftFailV7604.cs'
if (Test-Path -LiteralPath $soft -PathType Leaf) {
    $softText = [System.IO.File]::ReadAllText($soft)
    if ($softText.IndexOf('semantic corruption must never be the default', [System.StringComparison]::Ordinal) -lt 0) {
        throw 'V7604 SoftFail existe, mas nao foi convertido para opt-in.'
    }
    $extra.Add('V7604SoftFail=OPT_IN')
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$outPath = Join-Path $patches "SharpEmu_V76_0_5_1_SOURCE_VERIFY_$stamp.txt"
$lines = @(
    "Tag=$PackageTag",
    "RepositoryRoot=$repo",
    'BackendAndNewPayloadHashes=PASSED',
    'AdaptiveMarkers=PASSED'
) + $extra
Set-Content -LiteralPath $outPath -Value $lines -Encoding UTF8
Write-Host "[$PackageTag] SOURCE VERIFY PASSED. $outPath"
