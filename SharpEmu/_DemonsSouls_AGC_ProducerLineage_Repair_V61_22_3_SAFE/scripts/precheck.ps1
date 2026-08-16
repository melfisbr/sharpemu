param([string]$RepositoryRoot)
. (Join-Path $PSScriptRoot "common.ps1")

$root = Resolve-SharpEmuRepoRoot $RepositoryRoot
$agc = Get-AgcTarget $root
$registry = Get-WaitRegistryTarget $root
if (-not (Test-Path -LiteralPath $agc)) { throw "AgcExports.cs nao encontrado: $agc" }
if (-not (Test-Path -LiteralPath $registry)) { throw "GpuWaitRegistry.cs nao encontrado: $registry" }

$agcText = Normalize-Lf (Read-Utf8Text $agc)
$regText = Normalize-Lf (Read-Utf8Text $registry)
$writeSlice = Get-MethodDeclarationSlice -Text $agcText -MethodName "ApplySubmittedWriteData"
if ($null -eq $writeSlice) { throw "PRECHECK ERROR: ApplySubmittedWriteData nao localizado." }

$writeHasDirectRecord = $writeSlice.Contains("GpuWaitRegistry.RecordProduced(")
$writeHasRangeRecord = $writeSlice.Contains("RecordProducedLabelsInRange(")
$hasRangeHelper = $agcText.Contains("RecordProducedLabelsInRange(") -and $agcText.Contains("SnapshotWatchedLabelsInRange(")
$hasDmaCompletion = $agcText.Contains("producerCompletionAction") -and $agcText.Contains("ApplySubmittedDmaData")
$hasReleaseRecord = $agcText.Contains("producedValue") -and $agcText.Contains("dataSelection") -and $agcText.Contains("GpuWaitRegistry.RecordProduced(")
$hasRegistryRecord = $regText.Contains("public static bool RecordProduced(")

if (-not $writeHasDirectRecord) {
    throw "PRECHECK ERROR: o WRITE_DATA atual nao possui RecordProduced. Este estado e mais antigo que o baseline suportado pela V61.22.3."
}
if (-not $writeHasRangeRecord) {
    throw "PRECHECK ERROR: o WRITE_DATA atual nao possui RecordProducedLabelsInRange. Este estado e mais antigo que o baseline suportado pela V61.22.3."
}
if (-not $hasRangeHelper -or -not $hasDmaCompletion -or -not $hasReleaseRecord -or -not $hasRegistryRecord) {
    throw "PRECHECK ERROR: cobertura de produtores AGC incompleta. A V61.22.3 nao vai sobrescrever esse baseline automaticamente."
}

if ($agcText.Contains("V61.22.0 WRITE_DATA active-wait latch")) {
    Write-Host "[V61.22.3] WARNING: marcador da V61.22.0 encontrado. O coletor continuara sem duplicar a logica." -ForegroundColor Yellow
}

$agcSha = (Get-FileHash -LiteralPath $agc -Algorithm SHA256).Hash
$regSha = (Get-FileHash -LiteralPath $registry -Algorithm SHA256).Hash
Write-Host "[V61.22.3] PRECHECK PASSED." -ForegroundColor Green
Write-Host "[V61.22.3] Repository: $root"
Write-Host "[V61.22.3] Existing WRITE_DATA RecordProduced: YES"
Write-Host "[V61.22.3] Existing WRITE_DATA range latch:     YES"
Write-Host "[V61.22.3] Existing DMA completion tracking:    YES"
Write-Host "[V61.22.3] Existing RELEASE_MEM tracking:       YES"
Write-Host "[V61.22.3] AgcExports SHA256: $agcSha"
Write-Host "[V61.22.3] GpuWaitRegistry SHA256: $regSha"
Write-Host "[V61.22.3] No emulator source will be modified by this repair package."
