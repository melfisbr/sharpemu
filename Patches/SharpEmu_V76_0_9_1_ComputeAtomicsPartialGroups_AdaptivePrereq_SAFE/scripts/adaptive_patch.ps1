param([Parameter(Mandatory=$true)][string]$RepoRoot)
. (Join-Path $PSScriptRoot 'common.ps1')
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Apply-V7608CarrySpec {
    param($Spec)
    $state=Test-V7608CarrySpec $RepoRoot $Spec
    if ($state.State -ne 'ReadyRepair') { Write-Host "  = $($Spec.Name) $($state.State)"; return }
    $path=Join-Path $RepoRoot $Spec.Rel
    $raw=[System.IO.File]::ReadAllText($path)
    $useCrLf=$raw.Contains("`r`n")
    $text=$raw.Replace("`r`n","`n")
    $old=Read-NormalizedText (Get-PatchDataPath $Spec.Name 'old')
    $new=Read-NormalizedText (Get-PatchDataPath $Spec.Name 'new')
    $count=Get-OccurrenceCount $text $old
    if ($count -ne 1) { throw "V76.0.8 repair anchor invalida: $($Spec.Name) em $($Spec.Rel) occurrences=$count" }
    $idx=$text.IndexOf($old,[System.StringComparison]::Ordinal)
    $updated=$text.Substring(0,$idx)+$new+$text.Substring($idx+$old.Length)
    if ($useCrLf) { $updated=$updated.Replace("`n","`r`n") }
    [System.IO.File]::WriteAllText($path,$updated,$Utf8NoBom)
    Write-Host "  * prerequisite-repair $($Spec.Name)"
}
function Apply-PatchSpec {
    param($Spec)
    $path=Join-Path $RepoRoot $Spec.Rel
    $raw=[System.IO.File]::ReadAllText($path)
    $useCrLf=$raw.Contains("`r`n")
    $text=$raw.Replace("`r`n","`n")
    if ($text.IndexOf($Spec.Marker,[System.StringComparison]::Ordinal) -ge 0) { Write-Host "  = $($Spec.Name) already"; return }
    $old=Read-NormalizedText (Get-PatchDataPath $Spec.Name 'old')
    $new=Read-NormalizedText (Get-PatchDataPath $Spec.Name 'new')
    $count=Get-OccurrenceCount $text $old
    if ($count -ne 1) { throw "Apply anchor invalida: $($Spec.Name) em $($Spec.Rel) occurrences=$count" }
    $idx=$text.IndexOf($old,[System.StringComparison]::Ordinal)
    $updated=$text.Substring(0,$idx)+$new+$text.Substring($idx+$old.Length)
    if ($useCrLf) { $updated=$updated.Replace("`n","`r`n") }
    [System.IO.File]::WriteAllText($path,$updated,$Utf8NoBom)
    Write-Host "  * $($Spec.Name)"
}
Assert-V7608Base $RepoRoot
foreach ($spec in $V7608CarrySpecs) { Apply-V7608CarrySpec $spec }
Assert-V7608Installed $RepoRoot
foreach ($spec in $PatchSpecs) { Apply-PatchSpec $spec }
$helperTarget=Join-Path $RepoRoot $HelperRel
if ((Get-HelperState $RepoRoot) -eq 'Ready') {
    New-Item -ItemType Directory -Path (Split-Path -Parent $helperTarget) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PackageRoot $HelperPayloadRel) -Destination $helperTarget -Force
    Write-Host '  * atomic-compat-helper'
} else { Write-Host '  = atomic-compat-helper already' }
Assert-V7609Installed $RepoRoot
