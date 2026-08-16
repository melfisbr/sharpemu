. (Join-Path $PSScriptRoot "common.ps1")

function Find-CSharpMethodBounds {
    param([string]$Text,[string]$MethodName)
    $nameIndex=$Text.IndexOf($MethodName,[StringComparison]::Ordinal)
    if($nameIndex -lt 0) { throw "Method name not found: $MethodName" }

    $open=$Text.IndexOf('{',$nameIndex)
    if($open -lt 0) { throw "Opening brace not found after method: $MethodName" }

    $depth=0
    $inString=$false
    $verbatim=$false
    $inChar=$false
    $lineComment=$false
    $blockComment=$false
    $escape=$false

    for($i=$open;$i -lt $Text.Length;$i++) {
        $c=$Text[$i]
        $n=if($i+1 -lt $Text.Length) {$Text[$i+1]} else {[char]0}

        if($lineComment) {
            if($c -eq "`n") {$lineComment=$false}
            continue
        }
        if($blockComment) {
            if($c -eq '*' -and $n -eq '/') {$blockComment=$false;$i++}
            continue
        }
        if($inChar) {
            if($escape) {$escape=$false;continue}
            if($c -eq '\') {$escape=$true;continue}
            if($c -eq "'") {$inChar=$false}
            continue
        }
        if($inString) {
            if($verbatim) {
                if($c -eq '"' -and $n -eq '"') {$i++;continue}
                if($c -eq '"') {$inString=$false;$verbatim=$false}
                continue
            }
            if($escape) {$escape=$false;continue}
            if($c -eq '\') {$escape=$true;continue}
            if($c -eq '"') {$inString=$false}
            continue
        }

        if($c -eq '/' -and $n -eq '/') {$lineComment=$true;$i++;continue}
        if($c -eq '/' -and $n -eq '*') {$blockComment=$true;$i++;continue}
        if($c -eq "'") {$inChar=$true;continue}
        if($c -eq '"') {
            $inString=$true
            $verbatim=($i -gt 0 -and $Text[$i-1] -eq '@')
            continue
        }
        if($c -eq '{') {$depth++;continue}
        if($c -eq '}') {
            $depth--
            if($depth -eq 0) {
                return @($nameIndex,$open,$i)
            }
        }
    }
    throw "Closing brace not found for method: $MethodName"
}

$repo=Find-RepoRoot
$kernel=Get-KernelPath $repo
$ngs=Get-Ngs2Path $repo
$kt=Get-Content -LiteralPath $kernel -Raw
$nt=Get-Content -LiteralPath $ngs -Raw

if(-not $kt.Contains('public static bool IsReadOnlyGuestMutationPath(string guestPath)')) {
    throw "Kernel read-only policy method missing."
}
if(-not $nt.Contains('SHARPEMU_DBFZ_NGS2_PARSE_WAVEFORM_ABI_PROBE_V1_8_13')) {
    throw "V1.8.13 ParseWaveform marker missing."
}
if(-not $nt.Contains('Nid = "hyVLT2VlOYk"')) { throw "hyVLT2VlOYk export missing." }

$bounds=Find-CSharpMethodBounds -Text $nt -MethodName 'Ngs2ParseWaveformDataV1813'
$methodBody=$nt.Substring($bounds[1],$bounds[2]-$bounds[1]+1)
$setReturns=[regex]::Matches($methodBody,'return\s+(?:SetReturn|ctx\.SetReturn)\s*\([^;]+;')
if($setReturns.Count -lt 1) { throw "No return SetReturn/ctx.SetReturn found inside Ngs2ParseWaveformDataV1813." }

$kernelState=if($kt.Contains('SHARPEMU_DBFZ_SAVED_APP0_AUTO_V1_8_14') -or
                 $kt.Contains('SHARPEMU_DBFZ_SAVED_APP0_AUTO_V1_8_14_2') -or
                 $kt.Contains('SHARPEMU_DBFZ_SAVED_APP0_AUTO_V1_8_14_2')) {"AlreadyApplied"} else {"ReadyStructural"}
$ngsState=if($nt.Contains('SHARPEMU_DBFZ_NGS2_PARSE_AUTO_V1_8_14') -or
              $nt.Contains('SHARPEMU_DBFZ_NGS2_PARSE_AUTO_V1_8_14_2') -or
              $nt.Contains('SHARPEMU_DBFZ_NGS2_PARSE_AUTO_V1_8_14_2')) {"AlreadyApplied"} else {"ReadyMethodBody"}

Write-Host "[DBFZ-AUDIT-18142] RepoRoot=$repo"
Write-Host "[DBFZ-AUDIT-18142] Kernel SHA=$((Get-FileHash -Algorithm SHA256 -LiteralPath $kernel).Hash.ToLowerInvariant()) State=$kernelState"
Write-Host "[DBFZ-AUDIT-18142] Ngs2 SHA=$((Get-FileHash -Algorithm SHA256 -LiteralPath $ngs).Hash.ToLowerInvariant()) State=$ngsState"
Write-Host "[DBFZ-AUDIT-18142] Ngs2 method bounds=0x$($bounds[1].ToString('X'))..0x$($bounds[2].ToString('X')) SetReturnCount=$($setReturns.Count)"
Write-Host "[DBFZ-AUDIT-18142] PRECHECK PASSED."
