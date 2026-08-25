param([string]$PatchesRoot='C:\Users\Edpo\Documents\GitHub\sharpemu\Patches')
. (Join-Path $PSScriptRoot 'common.ps1')
$patches = Get-PatchesRoot $PatchesRoot
$target = Get-TargetPackage $patches
$scripts = @(Get-ScriptFiles $target)
$raw = 0
$guarded = 0
foreach ($script in $scripts) {
    $raw += @(Get-SplitPathCommandSpans $script.FullName).Count
    $text = [System.IO.File]::ReadAllText($script.FullName)
    if ($text.IndexOf($GuardMarker,[System.StringComparison]::Ordinal) -ge 0) { $guarded++ }
}
if ($raw -ne 0) { throw "VERIFY FAILED: raw Split-Path commands=$raw" }
[void](Test-TargetManifest $target)
Write-Host "[$PackageTag] TARGET VERIFY PASSED. GuardedScripts=$guarded RawSplitPathCommands=0 Manifest=OK"
