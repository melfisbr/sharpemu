$ErrorActionPreference="Stop"

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

$sample=@'
private static int Ngs2ParseWaveformDataV1813(CpuContext ctx)
{
    if (x)
    {
        return SetReturn(ctx, 1);
    }

    // SHARPEMU_DBFZ_NGS2_PARSE_AUTO_V1_8_14_2
    if (string.Equals(
            "a",
            "b",
            StringComparison.OrdinalIgnoreCase))
    {
        Span<byte> compatibilityOutput = stackalloc byte[0x240];
        compatibilityOutput.Clear();
        if (!ctx.Memory.TryWrite(outputAddress, compatibilityOutput))
        {
            return SetReturn(ctx, -1);
        }

        if (shouldDump)
        {
            Console.Error.WriteLine("{ braces in string }");
        }

        return SetReturn(ctx, 0);
    }

    if (y)
    {
        return SetReturn(ctx, 2);
    }

    return SetReturn(ctx, -99);
}
'@

$marker='    // SHARPEMU_DBFZ_NGS2_PARSE_AUTO_V1_8_14_2'
$m=$sample.IndexOf($marker,[StringComparison]::Ordinal)
$ifAt=$sample.IndexOf('    if (string.Equals(',$m,[StringComparison]::Ordinal)
$open=$sample.IndexOf('{',$ifAt)
$close=Find-CSharpBraceEnd -Text $sample -OpenIndex $open
if($m -lt 0 -or $ifAt -lt 0 -or $open -lt 0 -or $close -le $open) {
    throw "offline marked-block locator failed"
}

$after=$sample.Remove($m,$close+1-$m)
if($after.Contains('stackalloc byte[0x240]')) {
    throw "offline old block removal failed"
}
if(-not $after.Contains('return SetReturn(ctx, -99);')) {
    throw "offline fallback was damaged"
}
if(-not $after.Contains('return SetReturn(ctx, 2);')) {
    throw "offline post-block return was damaged"
}

Write-Host "[DBFZ-RIFF-181511] OFFLINE MARKED-BLOCK/BRACE REGRESSION PASSED."
