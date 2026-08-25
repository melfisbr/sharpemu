param([Parameter(Mandatory=$true)][string]$RepoRoot)
. (Join-Path $PSScriptRoot 'common.ps1')
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Apply-PatchSpec {
    param($Spec)
    $path = Join-Path $RepoRoot $Spec.Rel
    $raw = [System.IO.File]::ReadAllText($path)
    $useCrLf = $raw.Contains("`r`n")
    $text = $raw.Replace("`r`n", "`n")

    if ($text.IndexOf($Spec.Marker, [System.StringComparison]::Ordinal) -ge 0) {
        Write-Host "  = $($Spec.Name) already"
        return
    }

    $old = Read-NormalizedText (Get-PatchDataPath $Spec.Name 'old')
    $new = Read-NormalizedText (Get-PatchDataPath $Spec.Name 'new')
    $count = Get-OccurrenceCount $text $old
    if ($count -ne 1) {
        throw "Apply anchor invalida: $($Spec.Name) em $($Spec.Rel) occurrences=$count"
    }

    $idx = $text.IndexOf($old, [System.StringComparison]::Ordinal)
    $updated = $text.Substring(0, $idx) + $new + $text.Substring($idx + $old.Length)
    if ($useCrLf) { $updated = $updated.Replace("`n", "`r`n") }
    [System.IO.File]::WriteAllText($path, $updated, $Utf8NoBom)
    Write-Host "  * $($Spec.Name)"
}

Assert-Prerequisites $RepoRoot
foreach ($spec in $PatchSpecs) {
    Apply-PatchSpec $spec
}
Assert-V76072Installed $RepoRoot
