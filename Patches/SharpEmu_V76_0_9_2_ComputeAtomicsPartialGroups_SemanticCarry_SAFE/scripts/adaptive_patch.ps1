param([Parameter(Mandatory=$true)][string]$RepoRoot)
. (Join-Path $PSScriptRoot 'common.ps1')
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Repair-V7608FormatStoreDispatchSemantic {
    param($Spec)
    $path=Join-Path $RepoRoot $Spec.Rel
    $raw=[System.IO.File]::ReadAllText($path)
    $useCrLf=$raw.Contains("`r`n")
    $text=$raw.Replace("`r`n","`n")

    if ($text.IndexOf('EmitBufferFormatStoreV7608',[System.StringComparison]::Ordinal) -ge 0) {
        Write-Host "  = $($Spec.Name) AppliedSemantic"
        return
    }

    # Remove the legacy TBUFFER pending branch when present. It must not run
    # before the restored typed-store conversion branch.
    $pendingPattern='(?ms)^\s{12}if\s*\(\s*instruction\.Opcode\.StartsWith\(\s*"TBufferStoreFormat"\s*,\s*StringComparison\.Ordinal\s*\)\s*\)\s*\{.*?typed-buffer store conversion pending.*?^\s{16}return false;\s*\r?\n\s{12}\}\s*\r?\n'
    $pendingMatches=[System.Text.RegularExpressions.Regex]::Matches($text,$pendingPattern)
    if ($pendingMatches.Count -gt 1) { throw "V76.0.8 semantic repair: multiplos pending TBUFFER blocks=$($pendingMatches.Count)" }
    if ($pendingMatches.Count -eq 1) {
        $text=[System.Text.RegularExpressions.Regex]::Replace($text,$pendingPattern,'',1)
    }

    # The legacy generic MUBUF store condition may still include
    # BufferStoreFormat. Remove only that clause so typed stores cannot fall
    # through to raw-dword writes.
    $formatClause='instruction\.Opcode\.StartsWith\(\s*"BufferStoreFormat"\s*,\s*StringComparison\.Ordinal\s*\)\s*\|\|\s*'
    $formatMatches=[System.Text.RegularExpressions.Regex]::Matches($text,$formatClause)
    if ($formatMatches.Count -gt 1) { throw "V76.0.8 semantic repair: multiplas raw BufferStoreFormat clauses=$($formatMatches.Count)" }
    if ($formatMatches.Count -eq 1) {
        $text=[System.Text.RegularExpressions.Regex]::Replace($text,$formatClause,'',1)
    }

    $genericPattern='(?m)^ {12}if\s*\(\s*instruction\.Opcode\.StartsWith\(\s*"BufferStoreDword"\s*,\s*StringComparison\.Ordinal\s*\)\s*\|\|'
    $matches=[System.Text.RegularExpressions.Regex]::Matches(
        $text,
        $genericPattern,
        [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($matches.Count -ne 1) { throw "V76.0.8 semantic repair: generic store anchor occurrences=$($matches.Count)" }

    $typed=@'
            if (instruction.Opcode.StartsWith(
                    "TBufferStoreFormat",
                    StringComparison.Ordinal) ||
                instruction.Opcode.StartsWith(
                    "BufferStoreFormat",
                    StringComparison.Ordinal))
            {
                // V76.0.8 semantic carry-forward: both MTBUF and MUBUF format
                // stores use the RDNA2 typed conversion helper. MTBUF gets
                // FORMAT from the instruction; MUBUF gets FORMAT/dst_sel from
                // the SRD.
                EmitExecConditional(() =>
                    EmitBufferFormatStoreV7608(
                        bindingIndex,
                        byteAddress,
                        control.ScalarResource,
                        control));
                return true;
            }

'@
    $idx=$matches[0].Index
    $text=$text.Substring(0,$idx)+$typed+$text.Substring($idx)
    if ($useCrLf) { $text=$text.Replace("`n","`r`n") }
    [System.IO.File]::WriteAllText($path,$text,$Utf8NoBom)
    Write-Host "  * prerequisite-semantic-repair $($Spec.Name)"
}

function Apply-V7608CarrySpec {
    param($Spec)
    $state=Test-V7608CarrySpec $RepoRoot $Spec
    if ($Spec.Name -eq 'v8_03_format_store_dispatch' -and $state.State -eq 'ReadySemanticRepair') {
        Repair-V7608FormatStoreDispatchSemantic $Spec
        return
    }
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
