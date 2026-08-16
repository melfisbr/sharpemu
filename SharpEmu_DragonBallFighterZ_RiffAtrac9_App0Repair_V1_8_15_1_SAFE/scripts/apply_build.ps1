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

& (Join-Path $PSScriptRoot "precheck.ps1")
$repo=Find-RepoRoot
$ngs=Join-Path $repo "src\SharpEmu.Libs\Ngs2\Ngs2Exports.cs"
$kernel=Join-Path $repo "src\SharpEmu.Libs\Kernel\KernelMemoryCompatExports.cs"

$backupDir=Join-Path $repo (".sharpemu-hotfix-backup\DBFZ_RiffAtrac9App0_V1_8_15_1_1_"+(Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force -Path $backupDir|Out-Null
Copy-Item -LiteralPath $ngs -Destination (Join-Path $backupDir "Ngs2Exports.cs") -Force
Copy-Item -LiteralPath $kernel -Destination (Join-Path $backupDir "KernelMemoryCompatExports.cs") -Force

try {
    $nt=Get-Content -LiteralPath $ngs -Raw
    $kt=Get-Content -LiteralPath $kernel -Raw

    if(-not $nt.Contains('SHARPEMU_DBFZ_RIFF_ATRAC9_PRESERVE_V1_8_15_1_1')) {
        $marker='        // SHARPEMU_DBFZ_NGS2_PARSE_AUTO_V1_8_14_2'
        $markerAt=$nt.IndexOf($marker,[StringComparison]::Ordinal)
        if($markerAt -lt 0) {
            throw "V1.8.14.2 NGS2 compatibility marker not found."
        }

        $ifAt=$nt.IndexOf('        if (string.Equals(', $markerAt, [StringComparison]::Ordinal)
        if($ifAt -lt 0) {
            throw "Compatibility if-block not found after V1.8.14.2 marker."
        }

        $open=$nt.IndexOf('{', $ifAt)
        if($open -lt 0) {
            throw "Compatibility if-block opening brace not found."
        }
        $close=Find-CSharpBraceEnd -Text $nt -OpenIndex $open

        # Remove trailing CR/LF belonging to the old block, but nothing else.
        $removeEnd=$close+1
        while($removeEnd -lt $nt.Length -and
              ($nt[$removeEnd] -eq "`r" -or $nt[$removeEnd] -eq "`n")) {
            $removeEnd++
        }

        $replacement=@'
        // SHARPEMU_DBFZ_RIFF_ATRAC9_PRESERVE_V1_8_15_1_1
        // DBFZ supplies RIFF/WAVE_EXTENSIBLE ATRAC9. The caller already
        // initializes the 0x240 output descriptor, so preserve it verbatim.
        if (string.Equals(
                SharpEmu.Libs.Kernel.KernelMemoryCompatExports.CurrentApplicationTitleId,
                "PPSA09790",
                StringComparison.OrdinalIgnoreCase))
        {
            Span<byte> riff = stackalloc byte[68];
            if (dataAddress != 0 &&
                dataSize >= 68 &&
                ctx.Memory.TryRead(dataAddress, riff) &&
                riff[0] == (byte)'R' && riff[1] == (byte)'I' &&
                riff[2] == (byte)'F' && riff[3] == (byte)'F' &&
                riff[8] == (byte)'W' && riff[9] == (byte)'A' &&
                riff[10] == (byte)'V' && riff[11] == (byte)'E')
            {
                var formatTag = BinaryPrimitives.ReadUInt16LittleEndian(riff[20..22]);
                var channels = BinaryPrimitives.ReadUInt16LittleEndian(riff[22..24]);
                var sampleRate = BinaryPrimitives.ReadUInt32LittleEndian(riff[24..28]);
                var blockAlign = BinaryPrimitives.ReadUInt16LittleEndian(riff[32..34]);
                var bitsPerSample = BinaryPrimitives.ReadUInt16LittleEndian(riff[34..36]);
                var cbSize = BinaryPrimitives.ReadUInt16LittleEndian(riff[36..38]);

                var atrac9 =
                    formatTag == 0xFFFE &&
                    riff[44] == 0xD2 && riff[45] == 0x42 &&
                    riff[46] == 0xE1 && riff[47] == 0x47 &&
                    riff[48] == 0xBA && riff[49] == 0x36 &&
                    riff[50] == 0x8D && riff[51] == 0x4D &&
                    riff[52] == 0x88 && riff[53] == 0xFC &&
                    riff[54] == 0x61 && riff[55] == 0x65 &&
                    riff[56] == 0x4F && riff[57] == 0x8C &&
                    riff[58] == 0x83 && riff[59] == 0x6C;

                if (shouldDump)
                {
                    Console.Error.WriteLine(
                        $"[DBFZ-NGS2-18151][RIFF] call={call} size=0x{dataSize:X} " +
                        $"fmt=0x{formatTag:X4} ch={channels} rate={sampleRate} " +
                        $"align={blockAlign} bits={bitsPerSample} cb={cbSize} " +
                        $"atrac9={atrac9} out=0x{outputAddress:X16} preserved=1");
                }

                return SetReturn(ctx, 0);
            }
        }

'@

        $nt=$nt.Remove($markerAt,$removeEnd-$markerAt).Insert($markerAt,$replacement)
        Set-Content -LiteralPath $ngs -Value $nt -Encoding utf8
        Write-Host "[DBFZ-RIFF-181511] Replaced only the V1.8.14.2 marked compatibility block."
    }

    if(-not $kt.Contains('SHARPEMU_DBFZ_FULL_APP0_WRITE_V1_8_15_1_1')) {
        $needle=@'
        if (_writableApp0)
        {
            return false;
        }
'@
        $idx=$kt.IndexOf($needle,[StringComparison]::Ordinal)
        if($idx -lt 0) {
            throw "Kernel writable-app0 policy anchor missing."
        }

        $insertAt=$idx+$needle.Length
        $block=@'

        // SHARPEMU_DBFZ_FULL_APP0_WRITE_V1_8_15_1_1
        // The prior writable-app0 A/B eliminated DBFZ mkdir/open permission
        // failures. Apply that behavior only to PPSA09790.
        if (string.Equals(
                Volatile.Read(ref _applicationTitleId),
                "PPSA09790",
                StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }
'@
        $kt=$kt.Insert($insertAt,$block)
        Set-Content -LiteralPath $kernel -Value $kt -Encoding utf8
        Write-Host "[DBFZ-RIFF-181511] PPSA09790-only writable app0 policy installed."
    }

    Push-Location $repo
    try {
        dotnet build .\src\SharpEmu.CLI\SharpEmu.CLI.csproj -c Debug -r win-x64 --nologo
        if($LASTEXITCODE -ne 0) {
            throw "dotnet build failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
} catch {
    Copy-Item -LiteralPath (Join-Path $backupDir "Ngs2Exports.cs") -Destination $ngs -Force
    Copy-Item -LiteralPath (Join-Path $backupDir "KernelMemoryCompatExports.cs") -Destination $kernel -Force
    Write-Host "[DBFZ-RIFF-181511] Source restored after patch/build failure."
    throw
}

Write-Host "[DBFZ-RIFF-181511] BUILD PASSED. Backup: $backupDir"
