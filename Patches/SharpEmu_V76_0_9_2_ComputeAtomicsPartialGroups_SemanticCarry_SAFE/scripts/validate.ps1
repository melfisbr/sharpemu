. (Join-Path $PSScriptRoot 'common.ps1')
$manifestPath=Join-Path $PackageRoot 'manifest.sha256'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'manifest.sha256 ausente' }
$checked=0
foreach ($line in Get-Content -LiteralPath $manifestPath) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    if ($line -notmatch '^([0-9a-fA-F]{64})\s+\*(.+)$') { throw "Linha invalida no manifest: $line" }
    $expected=$Matches[1].ToLowerInvariant(); $relative=$Matches[2].Replace('/','\'); $path=Join-Path $PackageRoot $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Arquivo do manifest ausente: $relative" }
    $actual=Get-Sha256 $path
    if ($actual -ne $expected) { throw "Hash invalido: $relative expected=$expected actual=$actual" }
    $checked++
}
foreach ($scriptFile in Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File) {
    $tokens=$null; $parseIssues=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($scriptFile.FullName,[ref]$tokens,[ref]$parseIssues)
    if ($parseIssues -and $parseIssues.Count -gt 0) { throw "PowerShell parse failure em $($scriptFile.Name): $(($parseIssues | ForEach-Object {$_.Message}) -join '; ')" }
}
$helperPayload=Join-Path $PackageRoot $HelperPayloadRel
if ((Get-Sha256 $helperPayload) -ne $HelperHash) { throw 'Atomic helper payload hash interno divergente.' }
if (-not (Test-FileContains $helperPayload @('DeclareRdnaAtomicCompatV7609','AtomicCompareExchange','UGreaterThanEqual','UGreaterThan'))) { throw 'Atomic helper payload incompleto.' }
$partialOld=Read-NormalizedText (Get-PatchDataPath '09_partial_thread_groups' 'old')
$partialNew=Read-NormalizedText (Get-PatchDataPath '09_partial_thread_groups' 'new')
if ($partialOld.IndexOf('unrepresentable-partial-group(',[System.StringComparison]::Ordinal) -lt 0 -or $partialNew.IndexOf('threadCountX = (uint)exactEndX;',[System.StringComparison]::Ordinal) -lt 0) { throw 'Contrato partial-group invalido.' }

foreach ($name in @('v8_01_mubuf_decode','v8_02_mubuf_ir','v8_03_format_store_dispatch','v8_04_d16_narrow_integer_kind')) {
    $oldPath=Get-PatchDataPath $name 'old'; $newPath=Get-PatchDataPath $name 'new'
    if (-not (Test-Path -LiteralPath $oldPath -PathType Leaf) -or -not (Test-Path -LiteralPath $newPath -PathType Leaf)) { throw "V76.0.8 carry patchdata ausente: $name" }
}
$v8DispatchNew=Read-NormalizedText (Get-PatchDataPath 'v8_03_format_store_dispatch' 'new')
$v8NarrowNew=Read-NormalizedText (Get-PatchDataPath 'v8_04_d16_narrow_integer_kind' 'new')
if ($v8DispatchNew.IndexOf('EmitBufferFormatStoreV7608(',[System.StringComparison]::Ordinal) -lt 0 -or
    $v8NarrowNew.IndexOf('Equal(numberFormat, 4)',[System.StringComparison]::Ordinal) -lt 0 -or
    $v8NarrowNew.IndexOf('Equal(numberFormat, 5)',[System.StringComparison]::Ordinal) -lt 0) { throw 'Contrato carry-forward V76.0.8 invalido.' }

$commonText=Read-NormalizedText (Join-Path $PSScriptRoot 'common.ps1')
$adaptiveText=Read-NormalizedText (Join-Path $PSScriptRoot 'adaptive_patch.ps1')
if ($commonText.IndexOf('ReadySemanticRepair',[System.StringComparison]::Ordinal) -lt 0 -or
    $commonText.IndexOf('Semantic prerequisite V76.0.8 invalida',[System.StringComparison]::Ordinal) -lt 0 -or
    $adaptiveText.IndexOf('Repair-V7608FormatStoreDispatchSemantic',[System.StringComparison]::Ordinal) -lt 0 -or
    $adaptiveText.IndexOf('prerequisite-semantic-repair',[System.StringComparison]::Ordinal) -lt 0) {
    throw 'Contrato semantic carry V76.0.9.2 ausente.'
}

Write-Host "[$PackageTag] PACKAGE VALIDATION PASSED ($checked hashed files; PowerShell parsed; V76.0.9.2 contracts + adaptive V76.0.8 prerequisite passed)."
