. "$PSScriptRoot\common.ps1"
$pkg=PackageRoot; $repo=RepoRoot; $patches=Patches; $h=Host; $a=Assist; $p=Presenter
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'precheck.ps1')
$pre=$LASTEXITCODE
if ($pre -ne 0 -and $pre -ne 10) { exit $pre }
$bdir=$null
if ($pre -ne 10) {
    $stamp=Get-Date -Format yyyyMMdd_HHmmss
    $bdir=Join-Path $pkg ("backup\"+$stamp)
    New-Item -ItemType Directory -Force $bdir | Out-Null
    foreach ($src in @($h,$a,$p)) { Copy-Item $src (Join-Path $bdir (Split-Path $src -Leaf)) -Force }
    Set-Content (Join-Path $pkg 'LAST_BACKUP.txt') $bdir -Encoding UTF8
    try {
        $hs=[IO.File]::ReadAllText($h); $hs=NL $hs
        $as=[IO.File]::ReadAllText($a); $as=NL $as
        $ps=[IO.File]::ReadAllText($p); $ps=NL $ps
        $baseOrder=GetBaseChromaOrder $ps
        $baseIsUv=if ($baseOrder -eq 'UV') { 'true' } else { 'false' }

        $stateMarker='    // SHARPEMU_V74_0_81_TITLE_LOOP_COMPOSITE_STATE'
        if ((CountExact $hs $stateMarker) -ne 1) { throw 'V81 title-loop state marker changed' }
        $idx=$hs.IndexOf($stateMarker,[StringComparison]::Ordinal)
        $hostHelpers=Patch 'Host.helpers.insert.txt'
        $hs=$hs.Substring(0,$idx)+$hostHelpers+$hs.Substring($idx)

        $hostAttach=Patch 'Host.attach.insert.txt'
        $hs=InsertBodyStart $hs '(?m)^[ \t]*private static void AttachMovieLocked\(string hostPath, MovieMode mode\)\s*$' 'AttachMovieLocked' $hostAttach

        $oldState='return IsTitleLoopPathV74081(_activePath) &&'
        if ((CountExact $hs $oldState) -ne 1) { throw "V81 composite-state expression count=$(CountExact $hs $oldState)" }
        $hs=$hs.Replace($oldState,'return IsDemonSoulsUiBinkCompositePathV740841(_activePath) &&')

        $oldAssist=Patch 'Assist.ui_passthrough.anchor.txt'
        $newAssist=Patch 'Assist.ui_passthrough.replace.txt'
        if ((CountExact $as $oldAssist) -ne 1) { throw "V83 passthrough anchor count=$(CountExact $as $oldAssist)" }
        $as=$as.Replace($oldAssist,$newAssist)

        $field='        private long _v74083TitleUiCandidateCount;'
        if ((CountExact $ps $field) -ne 1) { throw "V83 Presenter field anchor count=$(CountExact $ps $field)" }
        $at=$ps.IndexOf($field,[StringComparison]::Ordinal)+$field.Length
        $presenterField=Patch 'Presenter.field.insert.txt'
        $ps=$ps.Substring(0,$at)+$presenterField+$ps.Substring($at)

        $helper=@'
        // SHARPEMU_V74_0_84_1_UI_BINK_GUEST_CHROMA_ORDER
        // The live Bluepoint Bink shader samples the interleaved chroma plane
        // through its original R/G swizzle. Historical SharpEmu paths used VU
        // here and the recovered fallback color path also required UV swap.
        // Default to VU only for Demon's Souls UI Binks; set
        // SHARPEMU_DS_UI_BINK_CHROMA_ORDER=uv for an instant A/B opt-out.
        private const bool V740841BaseConversionProducesUv = __BASE_IS_UV__;

        private static void SwapUiBinkChromaPairsV740841(Span<byte> chroma)
        {
            for (var index = 0; index + 1 < chroma.Length; index += 2)
            {
                (chroma[index], chroma[index + 1]) =
                    (chroma[index + 1], chroma[index]);
            }
        }

        private bool NormalizeDemonSoulsUiBinkChromaV740841(
            Span<byte> chroma)
        {
            if (!HostMovieBridge.IsDemonSoulsUiBinkCompositePathV740841(
                    _hostMovieFramePath))
            {
                return false;
            }

            var desiredUv = string.Equals(
                Environment.GetEnvironmentVariable(
                    "SHARPEMU_DS_UI_BINK_CHROMA_ORDER"),
                "uv",
                StringComparison.OrdinalIgnoreCase);
            var shouldSwap = V740841BaseConversionProducesUv
                ? !desiredUv
                : desiredUv;
            if (shouldSwap)
            {
                SwapUiBinkChromaPairsV740841(chroma);
            }

            var trace = Interlocked.Increment(
                ref _v740841UiBinkChromaTraceCount);
            if (trace <= 16 || (trace & (trace - 1)) == 0)
            {
                Console.Error.WriteLine(
                    "[V74.0.84.1][UI_BINK_CHROMA] " +
                    $"count={trace} file='{Path.GetFileName(_hostMovieFramePath)}' " +
                    $"base={(V740841BaseConversionProducesUv ? "UV" : "VU")} " +
                    $"desired={(desiredUv ? "UV" : "VU")} swap={shouldSwap} " +
                    "matrix=BT709 plane=interleaved-rg");
            }

            return shouldSwap;
        }

'@
        $helper=$helper.Replace('__BASE_IS_UV__',$baseIsUv)
        $ensureDecl='        private void EnsureHostMovieYuvFrame()'
        if ((CountExact $ps $ensureDecl) -ne 1) { throw 'EnsureHostMovieYuvFrame locator changed' }
        $idx=$ps.IndexOf($ensureDecl,[StringComparison]::Ordinal)
        $ps=$ps.Substring(0,$idx)+$helper+$ps.Substring($idx)

        $ensure=FindMethodSpan $ps '(?m)^[ \t]*private void EnsureHostMovieYuvFrame\(\)\s*$' 'EnsureHostMovieYuvFrame'
        $eb=Body $ps $ensure
        $needle=@'
            ConvertBgraToYuv420(
                bgra,
                width,
                height,
                _hostMovieLumaPixels,
                _hostMovieChromaPixels);
            _hostMovieConvertedFrameSerial = _hostMovieFrameSerial;
'@
        $needle=NL $needle
        $needle=$needle.Trim("`n")
        if ((CountExact $eb $needle) -ne 1) { throw "EnsureHostMovieYuvFrame conversion anchor count=$(CountExact $eb $needle)" }
        $replacement=@'
            ConvertBgraToYuv420(
                bgra,
                width,
                height,
                _hostMovieLumaPixels,
                _hostMovieChromaPixels);
            NormalizeDemonSoulsUiBinkChromaV740841(
                _hostMovieChromaPixels);
            _hostMovieConvertedFrameSerial = _hostMovieFrameSerial;
'@
        $replacementNormalized=NL $replacement
        $replacementNormalized=$replacementNormalized.Trim("`n")
        $eb=$eb.Replace($needle,$replacementNormalized)
        $ps=ReplaceBody $ps $ensure $eb

        WritePreserving $h $hs
        WritePreserving $a $as
        WritePreserving $p $ps

        $hv=[IO.File]::ReadAllText($h); $hv=NL $hv
        $av=[IO.File]::ReadAllText($a); $av=NL $av
        $pv=[IO.File]::ReadAllText($p); $pv=NL $pv
        foreach ($m in @('SHARPEMU_V74_0_84_1_DEMONS_UI_BINK_INTERNAL_COMPOSITOR','SHARPEMU_V74_0_84_1_UI_BINK_INTERNAL_ROUTING','IsDemonSoulsUiBinkCompositePathV740841')) {
            if (-not $hv.Contains($m)) { throw "Host marker missing: $m" }
        }
        if (-not $av.Contains('SHARPEMU_V74_0_84_1_UI_BINK_GUEST_LIVE_PASSTHROUGH')) { throw 'Assist V84.1 marker missing' }
        foreach ($m in @('SHARPEMU_V74_0_84_1_UI_BINK_COLOR_CONTRACT','SHARPEMU_V74_0_84_1_UI_BINK_GUEST_CHROMA_ORDER','NormalizeDemonSoulsUiBinkChromaV740841')) {
            if (-not $pv.Contains($m)) { throw "Presenter marker missing: $m" }
        }

        Write-Host '[V74.0.84.1] STRUCTURAL PATCH APPLIED.' -ForegroundColor Green
        Write-Host "BaseBGRAChromaOrder=$baseOrder"
        Write-Host "HostPostSHA256=$(Sha $h)"
        Write-Host "AssistPostSHA256=$(Sha $a)"
        Write-Host "PresenterPostSHA256=$(Sha $p)"
        Write-Host "Backup=$bdir"
    } catch {
        foreach ($dst in @($h,$a,$p)) {
            $src=Join-Path $bdir (Split-Path $dst -Leaf)
            if (Test-Path $src) { Copy-Item $src $dst -Force }
        }
        Write-Host "[V74.0.84.1][ERROR] APPLY FAILED: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host '[V74.0.84.1] SAFE rollback completed.' -ForegroundColor Yellow
        exit 1
    }
}
Get-Process SharpEmu -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
$log=Join-Path $patches ("SharpEmu_V74_0_84_1_UI_BINK_COLOR_SYNC_BUILD_"+(Get-Date -Format yyyyMMdd_HHmmss)+'.log')
& dotnet build (Join-Path $repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj') -c Debug -r win-x64 2>&1 | Tee-Object -FilePath $log
$code=$LASTEXITCODE
if ($code -ne 0) {
    if ($bdir) {
        foreach ($dst in @($h,$a,$p)) {
            $src=Join-Path $bdir (Split-Path $dst -Leaf)
            if (Test-Path $src) { Copy-Item $src $dst -Force }
        }
    }
    Write-Host '[V74.0.84.1][ERROR] BUILD FAILED; SAFE rollback completed.' -ForegroundColor Red
    exit $code
}
Write-Host '[V74.0.84.1] APPLY + BUILD PASSED.' -ForegroundColor Green
Write-Host "BuildLog=$log"
