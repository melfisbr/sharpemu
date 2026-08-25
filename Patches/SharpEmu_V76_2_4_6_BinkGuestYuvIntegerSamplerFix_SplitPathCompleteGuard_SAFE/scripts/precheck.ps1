param([string]$PatchesRoot='C:\Users\Edpo\Documents\GitHub\sharpemu\Patches')
. (Join-Path $PSScriptRoot 'common.ps1')
$patches = Get-PatchesRoot $PatchesRoot
$target = Get-TargetPackage $patches
$runner = Get-TargetRunner $target
$scripts = @(Get-ScriptFiles $target)
if ($scripts.Count -eq 0) { throw "Nenhum .ps1 no pacote-alvo: $target" }
$rawCount = 0
$alreadyGuarded = 0
foreach ($script in $scripts) {
    $rawCount += @(Get-SplitPathCommandSpans $script.FullName).Count
    $text = [System.IO.File]::ReadAllText($script.FullName)
    if ($text.IndexOf($GuardMarker,[System.StringComparison]::Ordinal) -ge 0) { $alreadyGuarded++ }
}
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$context = Join-Path $patches "SharpEmu_V76_2_4_6_PRECHECK_CONTEXT_$stamp.txt"
@(
    "Tag=$PackageTag",
    "Target=$target",
    "Runner=$runner",
    "PowerShellScripts=$($scripts.Count)",
    "RawSplitPathCommands=$rawCount",
    "AlreadyGuardedScripts=$alreadyGuarded",
    'Strategy=AST-command-name-rewrite-plus-safe-wrapper',
    'TargetSourceMutation=none-at-precheck'
) | Set-Content -LiteralPath $context -Encoding UTF8
Write-Host "[$PackageTag] Target=$target RawSplitPathCommands=$rawCount AlreadyGuardedScripts=$alreadyGuarded"
Write-Host "[$PackageTag] PRECHECK PASSED. Context=$context"
