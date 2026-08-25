param([Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference = "Stop"
$path = Join-Path $Root "src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs"
if (-not (Test-Path $path)) {
  $path = Join-Path $Root "SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs"
}
if (-not (Test-Path $path)) { throw "VulkanVideoPresenter.cs not found under $Root" }

$t = [IO.File]::ReadAllText($path)
$orig = $t

# Remove ALL submit hooks that may have landed mid-expression
$t = $t -replace '(?m)^[ \t]*VulkanQueueSubmitHooksV7622\.NoteGraphicsSubmit\(\);\r?\n', ''
$t = $t -replace '(?m)^[ \t]*VulkanQueueSubmitHooksV7622\.NoteComputeSubmit\(\);\r?\n', ''

# Keep / ensure present hook after HostFramePacer (safe site)
if ($t -notmatch 'VulkanQueueSubmitHooksV7622\.NotePresented\(\)') {
  if ($t -match 'HostFramePacerV7617\.PaceBeforePresent\(\);') {
    $t = $t.Replace(
      'HostFramePacerV7617.PaceBeforePresent();',
      "HostFramePacerV7617.PaceBeforePresent();`r`n                    VulkanQueueSubmitHooksV7622.NotePresented();")
  } elseif ($t -match 'VulkanSubmitThrottleV7610\.OnPresented\(\);') {
    $t = $t.Replace(
      'VulkanSubmitThrottleV7610.OnPresented();',
      "VulkanSubmitThrottleV7610.OnPresented();`r`n                    VulkanQueueSubmitHooksV7622.NotePresented();")
  }
}

# Re-insert graphics hooks ONLY on lines that are solely a QueueSubmit call start
# matching typical "            queue.QueueSubmit(" or "_api.QueueSubmit(" full statement lines
$lines = $t -split "`r?`n"
$out = New-Object System.Collections.Generic.List[string]
$gfx = 0
for ($i = 0; $i -lt $lines.Count; $i++) {
  $line = $lines[$i]
  if ($gfx -lt 2 -and $line -match '^\s+\w[\w\.]*QueueSubmit\s*\(' -and $line -notmatch 'NoteGraphicsSubmit') {
    $indent = ($line -replace '^(\s*).*','$1')
    # Look back 3 lines for compute context
    $ctx = ""
    for ($j = [Math]::Max(0,$i-3); $j -lt $i; $j++) { $ctx += $lines[$j] }
    if ($ctx -match '(?i)compute') {
      $out.Add("${indent}VulkanQueueSubmitHooksV7622.NoteComputeSubmit();")
    } else {
      $out.Add("${indent}VulkanQueueSubmitHooksV7622.NoteGraphicsSubmit();")
      $gfx++
    }
  }
  $out.Add($line)
}
$t = [string]::Join("`r`n", $out)

if ($t -eq $orig) {
  Write-Host "[FIX V76.2.2] no text change (already clean?)"
} else {
  [IO.File]::WriteAllText($path, $t)
  Write-Host "[FIX V76.2.2] repaired $path (gfx hooks reinserted=$gfx)"
}

Write-Host "Rebuild: cd `"$Root`"; dotnet build"
