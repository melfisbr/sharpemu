. (Join-Path $PSScriptRoot "common.ps1")

function Find-CSharpBraceEnd {
    param([string]$Text,[int]$OpenIndex)
    if($OpenIndex -lt 0 -or $OpenIndex -ge $Text.Length -or $Text[$OpenIndex] -ne '{') {
        throw "Invalid opening brace index: $OpenIndex"
    }

    $depth=0
    $inString=$false
    $verbatim=$false
    $inChar=$false
    $lineComment=$false
    $blockComment=$false
    $escape=$false

    for($i=$OpenIndex;$i -lt $Text.Length;$i++) {
        $c=$Text[$i]
        $n=if($i+1 -lt $Text.Length){$Text[$i+1]}else{[char]0}

        if($lineComment) {
            if($c -eq "`n"){$lineComment=$false}
            continue
        }
        if($blockComment) {
            if($c -eq '*' -and $n -eq '/'){$blockComment=$false;$i++}
            continue
        }
        if($inChar) {
            if($escape){$escape=$false;continue}
            if($c -eq '\'){$escape=$true;continue}
            if($c -eq "'"){$inChar=$false}
            continue
        }
        if($inString) {
            if($verbatim) {
                if($c -eq '"' -and $n -eq '"'){$i++;continue}
                if($c -eq '"'){$inString=$false;$verbatim=$false}
                continue
            }
            if($escape){$escape=$false;continue}
            if($c -eq '\'){$escape=$true;continue}
            if($c -eq '"'){$inString=$false}
            continue
        }

        if($c -eq '/' -and $n -eq '/'){$lineComment=$true;$i++;continue}
        if($c -eq '/' -and $n -eq '*'){$blockComment=$true;$i++;continue}
        if($c -eq "'"){$inChar=$true;continue}
        if($c -eq '"'){
            $inString=$true
            $verbatim=($i -gt 0 -and $Text[$i-1] -eq '@')
            continue
        }
        if($c -eq '{'){$depth++;continue}
        if($c -eq '}'){
            $depth--
            if($depth -eq 0){return $i}
        }
    }
    throw "Closing brace not found."
}

$repo=Find-RepoRoot
$ngs=Join-Path $repo "src\SharpEmu.Libs\Ngs2\Ngs2Exports.cs"
$kernel=Join-Path $repo "src\SharpEmu.Libs\Kernel\KernelMemoryCompatExports.cs"
$nt=Get-Content -LiteralPath $ngs -Raw
$kt=Get-Content -LiteralPath $kernel -Raw

foreach($r in @(
    'Ngs2ParseWaveformDataV1813',
    'SHARPEMU_DBFZ_NGS2_PARSE_AUTO_V1_8_14_2',
    'stackalloc byte[0x240]',
    'CurrentApplicationTitleId',
    'IsReadOnlyGuestMutationPath'
)) {
    if(-not($nt.Contains($r) -or $kt.Contains($r))) {
        throw "Required cumulative anchor missing: $r"
    }
}

$marker='        // SHARPEMU_DBFZ_NGS2_PARSE_AUTO_V1_8_14_2'
$markerAt=$nt.IndexOf($marker,[StringComparison]::Ordinal)
$ifAt=$nt.IndexOf('        if (string.Equals(', $markerAt, [StringComparison]::Ordinal)
$open=$nt.IndexOf('{',$ifAt)
if($markerAt -lt 0 -or $ifAt -lt 0 -or $open -lt 0) {
    throw "Cannot structurally identify V1.8.14.2 compatibility block."
}
$close=Find-CSharpBraceEnd -Text $nt -OpenIndex $open
if($close -le $open) {
    throw "Invalid compatibility block bounds."
}

Write-Host "[DBFZ-RIFF-181511] RepoRoot=$repo"
Write-Host "[DBFZ-RIFF-181511] Ngs2 SHA=$((Get-FileHash -Algorithm SHA256 -LiteralPath $ngs).Hash.ToLowerInvariant())"
Write-Host "[DBFZ-RIFF-181511] Kernel SHA=$((Get-FileHash -Algorithm SHA256 -LiteralPath $kernel).Hash.ToLowerInvariant())"
Write-Host "[DBFZ-RIFF-181511] old_block_bounds=0x$($markerAt.ToString('X'))..0x$($close.ToString('X'))"
Write-Host "[DBFZ-RIFF-181511] destructive_zero_fill_present=$($nt.Contains('stackalloc byte[0x240]'))"
Write-Host "[DBFZ-RIFF-181511] PRECHECK PASSED."
