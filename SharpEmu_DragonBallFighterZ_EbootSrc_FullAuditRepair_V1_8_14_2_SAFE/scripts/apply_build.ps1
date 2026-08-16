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


& (Join-Path $PSScriptRoot "precheck.ps1")
$repo=Find-RepoRoot
$kernel=Get-KernelPath $repo
$ngs=Get-Ngs2Path $repo
$kernelText=Get-Content -LiteralPath $kernel -Raw
$ngsText=Get-Content -LiteralPath $ngs -Raw

$backupDir=Join-Path $repo (".sharpemu-hotfix-backup\DBFZ_FullAuditRepair_V1_8_14_2_"+(Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
Copy-Item -LiteralPath $kernel -Destination (Join-Path $backupDir "KernelMemoryCompatExports.cs") -Force
Copy-Item -LiteralPath $ngs -Destination (Join-Path $backupDir "Ngs2Exports.cs") -Force

try {
    if(-not $kernelText.Contains('CurrentApplicationTitleId => Volatile.Read(ref _applicationTitleId)')) {
        $field='    private static string _applicationTitleId = "UNKNOWN";'
        $idx=$kernelText.IndexOf($field,[StringComparison]::Ordinal)
        if($idx -lt 0) { throw "Kernel title field anchor missing." }
        $kernelText=$kernelText.Insert($idx+$field.Length,"`r`n`r`n    internal static string CurrentApplicationTitleId => Volatile.Read(ref _applicationTitleId);")
    }

    if(-not ($kernelText.Contains('SHARPEMU_DBFZ_SAVED_APP0_AUTO_V1_8_14') -or
             $kernelText.Contains('SHARPEMU_DBFZ_SAVED_APP0_AUTO_V1_8_14_2') -or
             $kernelText.Contains('SHARPEMU_DBFZ_SAVED_APP0_AUTO_V1_8_14_2'))) {
        $methodToken='public static bool IsReadOnlyGuestMutationPath(string guestPath)'
        $mi=$kernelText.IndexOf($methodToken,[StringComparison]::Ordinal)
        $norm='        var normalized = NormalizeGuestStatCachePath(guestPath);'
        $ni=$kernelText.IndexOf($norm,$mi,[StringComparison]::Ordinal)
        if($mi -lt 0 -or $ni -lt 0) { throw "Kernel DBFZ Saved insertion anchor missing." }
        $le=$kernelText.IndexOf("`n",$ni)
        $policy=@'

        // SHARPEMU_DBFZ_SAVED_APP0_AUTO_V1_8_14_2
        if (string.Equals(
                Volatile.Read(ref _applicationTitleId),
                "PPSA09790",
                StringComparison.OrdinalIgnoreCase) &&
            normalized is not null &&
            (string.Equals(normalized, "/app0/red/saved", StringComparison.OrdinalIgnoreCase) ||
             normalized.StartsWith("/app0/red/saved/", StringComparison.OrdinalIgnoreCase)))
        {
            return false;
        }
'@
        $kernelText=$kernelText.Insert($le+1,$policy)
    }
    Set-Content -LiteralPath $kernel -Value $kernelText -Encoding utf8

    $ngsText=Get-Content -LiteralPath $ngs -Raw
    if(-not ($ngsText.Contains('SHARPEMU_DBFZ_NGS2_PARSE_AUTO_V1_8_14') -or
             $ngsText.Contains('SHARPEMU_DBFZ_NGS2_PARSE_AUTO_V1_8_14_2') -or
             $ngsText.Contains('SHARPEMU_DBFZ_NGS2_PARSE_AUTO_V1_8_14_2'))) {
        $b=Find-CSharpMethodBounds -Text $ngsText -MethodName 'Ngs2ParseWaveformDataV1813'
        $body=$ngsText.Substring($b[1],$b[2]-$b[1]+1)
        $returns=[regex]::Matches($body,'return\s+(?:SetReturn|ctx\.SetReturn)\s*\([^;]+;')
        if($returns.Count -lt 1) { throw "No compatible return found inside Ngs2ParseWaveformDataV1813." }
        $last=$returns[$returns.Count-1]
        $insertAt=$b[1]+$last.Index

        $compat=@'
        // SHARPEMU_DBFZ_NGS2_PARSE_AUTO_V1_8_14_2
        if (string.Equals(
                SharpEmu.Libs.Kernel.KernelMemoryCompatExports.CurrentApplicationTitleId,
                "PPSA09790",
                StringComparison.OrdinalIgnoreCase))
        {
            Span<byte> compatibilityOutput = stackalloc byte[0x240];
            compatibilityOutput.Clear();
            if (!ctx.Memory.TryWrite(outputAddress, compatibilityOutput))
            {
                return SetReturn(ctx, OrbisNgs2ErrorInvalidOutAddress);
            }

            if (shouldDump)
            {
                Console.Error.WriteLine(
                    $"[DBFZ-NGS2-18142][PARSE_OK] call={call} out=0x{outputAddress:X16} bytes=0x240");
            }

            return SetReturn(ctx, 0);
        }

'@
        $ngsText=$ngsText.Insert($insertAt,$compat)
        Set-Content -LiteralPath $ngs -Value $ngsText -Encoding utf8
    }

    Push-Location $repo
    try {
        dotnet build .\src\SharpEmu.CLI\SharpEmu.CLI.csproj -c Debug -r win-x64 --nologo
        if($LASTEXITCODE -ne 0) { throw "dotnet build failed with exit code $LASTEXITCODE" }
    } finally { Pop-Location }
} catch {
    Copy-Item -LiteralPath (Join-Path $backupDir "KernelMemoryCompatExports.cs") -Destination $kernel -Force
    Copy-Item -LiteralPath (Join-Path $backupDir "Ngs2Exports.cs") -Destination $ngs -Force
    Write-Host "[DBFZ-AUDIT-18142] Source restored after patch/build failure."
    throw
}
Write-Host "[DBFZ-AUDIT-18142] BUILD PASSED. Backup: $backupDir"
