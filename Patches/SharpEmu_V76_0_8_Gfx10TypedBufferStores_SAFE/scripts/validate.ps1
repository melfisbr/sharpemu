. (Join-Path $PSScriptRoot 'common.ps1')
$manifestPath = Join-Path $PackageRoot 'manifest.sha256'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'manifest.sha256 ausente' }
$checked = 0
foreach ($line in Get-Content -LiteralPath $manifestPath) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    if ($line -notmatch '^([0-9a-fA-F]{64})\s+\*(.+)$') { throw "Linha invalida no manifest: $line" }
    $expected = $Matches[1].ToLowerInvariant()
    $relative = $Matches[2].Replace('/', '\')
    $path = Join-Path $PackageRoot $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Arquivo do manifest ausente: $relative" }
    $actual = Get-Sha256 $path
    if ($actual -ne $expected) { throw "Hash invalido: $relative expected=$expected actual=$actual" }
    $checked++
}
foreach ($scriptFile in Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File) {
    $tokens = $null
    $parseIssues = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($scriptFile.FullName,[ref]$tokens,[ref]$parseIssues)
    if ($parseIssues -and $parseIssues.Count -gt 0) {
        throw "PowerShell parse failure em $($scriptFile.Name): $(($parseIssues | ForEach-Object {$_.Message}) -join '; ')"
    }
}

$helperPayload = Join-Path $PackageRoot $HelperPayloadRel
if ((Get-Sha256 $helperPayload) -ne $HelperHash) { throw 'Helper payload hash interno divergente.' }
if (-not (Test-FileContains $helperPayload @(
    'EmitBufferFormatStoreV7608',
    'ConvertGfx10BufferStoreComponentV7608',
    'EncodeUnsignedMiniFloatV7608'))) {
    throw 'Helper payload sem marcadores V76.0.8.'
}
$decodeNew = Read-NormalizedText (Get-PatchDataPath '01_mubuf_decode' 'new')
if ($decodeNew.IndexOf('& 0xFF', [System.StringComparison]::Ordinal) -lt 0 -or
    $decodeNew.IndexOf('0x80 => "BufferLoadFormatD16X"', [System.StringComparison]::Ordinal) -lt 0 -or
    $decodeNew.IndexOf('0x87 => "BufferStoreFormatD16Xyzw"', [System.StringComparison]::Ordinal) -lt 0) {
    throw 'Patch MUBUF D16 incompleto.'
}
$storeOld = Read-NormalizedText (Get-PatchDataPath '03_format_store_dispatch' 'old')
$storeNew = Read-NormalizedText (Get-PatchDataPath '03_format_store_dispatch' 'new')
if ($storeOld.IndexOf('typed-buffer store conversion pending', [System.StringComparison]::Ordinal) -lt 0 -or
    $storeNew.IndexOf('EmitBufferFormatStoreV7608', [System.StringComparison]::Ordinal) -lt 0 -or
    $storeNew.IndexOf('typed-buffer store conversion pending', [System.StringComparison]::Ordinal) -ge 0) {
    throw 'Contrato typed-store pending->implemented invalido.'
}
Write-Host "[$PackageTag] PACKAGE VALIDATION PASSED ($checked hashed files; PowerShell parsed; V76.0.8 contracts passed)."
