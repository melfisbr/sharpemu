param([Parameter(Mandatory=$true)][string]$RepoRoot)
. (Join-Path $PSScriptRoot 'common.ps1')
Assert-V76093Baseline $RepoRoot

$cacheTarget=Join-Path $RepoRoot $CacheRel
$cacheHash=Get-Sha256 $cacheTarget
if ($cacheHash -eq $CacheOldHash) {
    Copy-Item -LiteralPath (Join-Path $PackageRoot $CachePayloadRel) -Destination $cacheTarget -Force
    Write-Host '  * shader-cache-v7610-version-key-filter-async-persist'
} elseif ($cacheHash -eq $CacheNewHash) {
    Write-Host '  = shader-cache-v7610-version-key-filter-async-persist already'
} else {
    throw "Cache helper divergente antes do apply: $cacheHash"
}

$translator=Join-Path $RepoRoot $TranslatorRel
$old=@'
            if (instruction.Opcode is
                "SNop" or
                "SWaitcnt" or
                "SInstPrefetch" or
'@
$new=@'
            if (instruction.Opcode is
                "SNop" or
                "SWaitcnt" or
                // V76.0.10: S_CLAUSE is a hardware scheduling hint. SPIR-V/Vulkan
                // does not expose guest wave clause scheduling, so preserving the
                // instruction stream means treating it as host-irrelevant.
                "SClause" or
                // V76.0.10: dependency-scoreboard waits serialize hazards that are
                // represented explicitly by SPIR-V SSA/data dependencies. They do
                // not imply a guest memory barrier (unlike S_BARRIER).
                "SWaitcntDepctr" or
                "SInstPrefetch" or
'@
Replace-OnceRequired $translator $old $new '"SWaitcntDepctr" or' 'vulkan-sopp-clause-depctr'

$metal=Join-Path $RepoRoot $MetalRel
$old=@'
                case "SWaitcnt":
                case "SInstPrefetch":
'@
$new=@'
                case "SWaitcnt":
                // V76.0.10 parity with Vulkan: dependency-counter waits are
                // hardware scoreboard controls, not a shader-language memory barrier.
                case "SWaitcntDepctr":
                case "SInstPrefetch":
'@
Replace-OnceRequired $metal $old $new 'case "SWaitcntDepctr":' 'metal-sopp-depctr-parity'

Assert-V7610Installed $RepoRoot
