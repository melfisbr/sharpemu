param([string]$RepositoryRoot)
. (Join-Path $PSScriptRoot "common.ps1")

$root = Resolve-SharpEmuRepoRoot $RepositoryRoot
$target = Get-ApplyTarget $root
$registry = Get-WaitRegistryTarget $root
if (-not (Test-Path $target)) { throw "AgcExports.cs nao encontrado: $target" }
if (-not (Test-Path $registry)) { throw "GpuWaitRegistry.cs nao encontrado: $registry" }

$text = Read-Utf8Text $target
$normalized = Normalize-Lf $text
$registryText = Normalize-Lf (Read-Utf8Text $registry)

if ($normalized.Contains("V61.22.0 WRITE_DATA active-wait latch")) {
    Write-Host "[V61.22.0] PRECHECK: ALREADY APPLIED." -ForegroundColor Yellow
    return
}

$slice = Get-WriteDataMethodSlice $normalized
if ($null -eq $slice) {
    throw "PRECHECK ERROR: ApplySubmittedWriteData baseline nao foi localizado."
}

if ($slice.Contains("GpuWaitRegistry.RecordProduced(")) {
    throw "PRECHECK ERROR: ApplySubmittedWriteData ja possui RecordProduced sem o marcador V61.22.0. Baseline divergente; nao aplicar transformacao automaticamente."
}

$old = Normalize-Lf (Get-OldWriteDataBlock)
$first = $normalized.IndexOf($old, [System.StringComparison]::Ordinal)
if ($first -lt 0) {
    throw "PRECHECK ERROR: bloco WRITE_DATA esperado nao encontrado."
}
$second = $normalized.IndexOf($old, $first + $old.Length, [System.StringComparison]::Ordinal)
if ($second -ge 0) {
    throw "PRECHECK ERROR: bloco WRITE_DATA apareceu mais de uma vez."
}

foreach ($required in @(
    "public static bool RecordProduced(",
    "public static List<(ulong Address, int Count)> SnapshotInRange(",
    "public static List<WaitingDcb>? CollectDeadlockBroken("
)) {
    if (-not $registryText.Contains($required)) {
        throw "PRECHECK ERROR: GpuWaitRegistry baseline sem '$required'."
    }
}

$sha = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
Write-Host "[V61.22.0] PRECHECK PASSED." -ForegroundColor Green
Write-Host "[V61.22.0] Repository: $root"
Write-Host "[V61.22.0] Target SHA256: $sha"
Write-Host "[V61.22.0] Fix scope: WRITE_DATA -> active WAIT_REG_MEM producer latch only."
