
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


$sample=@'
    internal static long Ngs2ParseWaveformDataV1813 (
        CpuContext ctx
    )
    {
        var x = "{not a brace}";
        // } ignored
        if (x.Length > 0)
        {
            return ctx.SetReturn(1);
        }
        /* { ignored } */
        return SetReturn(ctx, OrbisGen2Result.ORBIS_GEN2_ERROR_INVALID_ARGUMENT);
    }
'@
$b=Find-CSharpMethodBounds -Text $sample -MethodName 'Ngs2ParseWaveformDataV1813'
$body=$sample.Substring($b[1],$b[2]-$b[1]+1)
$r=[regex]::Matches($body,'return\s+(?:SetReturn|ctx\.SetReturn)\s*\([^;]+;')
if($r.Count -ne 2) { throw "offline return count=$($r.Count)" }
if(-not $r[1].Value.Contains('INVALID_ARGUMENT')) { throw "offline final return selection failed" }

$csv=Import-Csv -LiteralPath (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")).Path "data\DBFZ_EBOOT_IMPORT_AUDIT.csv")
if($csv.Count -ne 2766) { throw "offline inventory count=$($csv.Count)" }
Write-Host "[DBFZ-AUDIT-18142] OFFLINE CSHARP-BRACE/METHOD REGRESSION PASSED."
