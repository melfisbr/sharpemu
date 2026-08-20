. "$PSScriptRoot\common.ps1"
$pkg=PackageRoot;$repo=RepoRoot;$patches=Patches;$h=Host;$a=Assist;$p=Presenter
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'precheck.ps1');$pre=$LASTEXITCODE
if($pre-ne 0-and$pre-ne 10){exit $pre}
$bdir=$null
if($pre-ne 10){
 $stamp=Get-Date -Format yyyyMMdd_HHmmss;$bdir=Join-Path $pkg ("backup\"+$stamp);New-Item -ItemType Directory -Force $bdir|Out-Null
 foreach($src in @($h,$a,$p)){Copy-Item $src (Join-Path $bdir (Split-Path $src -Leaf)) -Force}
 Set-Content (Join-Path $pkg 'LAST_BACKUP.txt') $bdir -Encoding UTF8
 try{
  $hs=NL([IO.File]::ReadAllText($h));$as=NL([IO.File]::ReadAllText($a));$ps=NL([IO.File]::ReadAllText($p))
  $baseOrder=GetBaseChromaOrder $ps
  $baseIsUv=if($baseOrder-eq'UV'){'true'}else{'false'}

  $stateMarker='    // SHARPEMU_V74_0_81_TITLE_LOOP_COMPOSITE_STATE'
  if((CountExact $hs $stateMarker)-ne 1){throw 'V81 title-loop state marker changed'}
  $idx=$hs.IndexOf($stateMarker,[StringComparison]::Ordinal)
  $hs=$hs.Substring(0,$idx)+(Patch 'Host.helpers.insert.txt')+$hs.Substring($idx)

  $hs=InsertBodyStart $hs '(?m)^[ \t]*private static void AttachMovieLocked\(string hostPath, MovieMode mode\)\s*$' 'AttachMovieLocked' (Patch 'Host.attach.insert.txt')

  $oldState='return IsTitleLoopPathV74081(_activePath) &&'
  if((CountExact $hs $oldState)-ne 1){throw "V81 composite-state expression count=$(CountExact $hs $oldState)"}
  $hs=$hs.Replace(
      $oldState,
      'return IsDemonSoulsUiBinkCompositePathV74084(_activePath) &&')

  $oldAssist=Patch 'Assist.ui_passthrough.anchor.txt';$newAssist=Patch 'Assist.ui_passthrough.replace.txt'
  if((CountExact $as $oldAssist)-ne 1){throw "V83 passthrough anchor count=$(CountExact $as $oldAssist)"}
  $as=$as.Replace($oldAssist,$newAssist)

  $field='        private long _v74083TitleUiCandidateCount;'
  if((CountExact $ps $field)-ne 1){throw "V83 Presenter field anchor count=$(CountExact $ps $field)"}
  $at=$ps.IndexOf($field,[StringComparison]::Ordinal)+$field.Length
  $ps=$ps.Substring(0,$at)+(Patch 'Presenter.field.insert.txt')+$ps.Substring($at)

  $helper=@"
        // SHARPEMU_V74_0_84_UI_BINK_GUEST_CHROMA_ORDER
        // The live Bluepoint Bink shader samples the interleaved chroma plane
        // through its original R/G swizzle. Historical SharpEmu paths used VU
        // here and the recovered fallback color path also required UV swap.
        // Default to VU only for Demon's Souls UI Binks; set
        // SHARPEMU_DS_UI_BINK_CHROMA_ORDER=uv for an instant A/B opt-out.
        private const bool V74084BaseConversionProducesUv = $baseIsUv;

        private static void SwapUiBinkChromaPairsV74084(Span<byte> chroma)
        {
            for (var index = 0; index + 1 < chroma.Length; index += 2)
            {
                (chroma[index], chroma[index + 1]) =
                    (chroma[index + 1], chroma[index]);
            }
        }

        private bool NormalizeDemonSoulsUiBinkChromaV74084(
            Span<byte> chroma)
        {
            if (!HostMovieBridge.IsDemonSoulsUiBinkCompositePathV74084(
                    _hostMovieFramePath))
            {
                return false;
            }

            var desiredUv = string.Equals(
                Environment.GetEnvironmentVariable(
                    "SHARPEMU_DS_UI_BINK_CHROMA_ORDER"),
                "uv",
                StringComparison.OrdinalIgnoreCase);
            var shouldSwap = V74084BaseConversionProducesUv
                ? !desiredUv
                : desiredUv;
            if (shouldSwap)
            {
                SwapUiBinkChromaPairsV74084(chroma);
            }

            var trace = Interlocked.Increment(
                ref _v74084UiBinkChromaTraceCount);
            if (trace <= 16 || (trace & (trace - 1)) == 0)
            {
                Console.Error.WriteLine(
                    "[V74.0.84][UI_BINK_CHROMA] " +
                    $"count={trace} file='{Path.GetFileName(_hostMovieFramePath)}' " +
                    $"base={(V74084BaseConversionProducesUv ? "UV" : "VU")} " +
                    $"desired={(desiredUv ? "UV" : "VU")} swap={shouldSwap} " +
                    "matrix=BT709 plane=interleaved-rg");
            }

            return shouldSwap;
        }

"@
  $ensureDecl='        private void EnsureHostMovieYuvFrame()'
  if((CountExact $ps $ensureDecl)-ne 1){throw 'EnsureHostMovieYuvFrame locator changed'}
  $idx=$ps.IndexOf($ensureDecl,[StringComparison]::Ordinal)
  $ps=$ps.Substring(0,$idx)+$helper+$ps.Substring($idx)

  $ensure=FindMethodSpan $ps '(?m)^[ \t]*private void EnsureHostMovieYuvFrame\(\)\s*$' 'EnsureHostMovieYuvFrame';$eb=Body $ps $ensure
  $needle=@'
            ConvertBgraToYuv420(
                bgra,
                width,
                height,
                _hostMovieLumaPixels,
                _hostMovieChromaPixels);
            _hostMovieConvertedFrameSerial = _hostMovieFrameSerial;
'@
  $needle=NL($needle).Trim("`n")
  if((CountExact $eb $needle)-ne 1){throw "EnsureHostMovieYuvFrame conversion anchor count=$(CountExact $eb $needle)"}
  $replacement=@'
            ConvertBgraToYuv420(
                bgra,
                width,
                height,
                _hostMovieLumaPixels,
                _hostMovieChromaPixels);
            NormalizeDemonSoulsUiBinkChromaV74084(
                _hostMovieChromaPixels);
            _hostMovieConvertedFrameSerial = _hostMovieFrameSerial;
'@
  $eb=$eb.Replace($needle,NL($replacement).Trim("`n"));$ps=ReplaceBody $ps $ensure $eb

  WritePreserving $h $hs;WritePreserving $a $as;WritePreserving $p $ps

  $hv=NL([IO.File]::ReadAllText($h));$av=NL([IO.File]::ReadAllText($a));$pv=NL([IO.File]::ReadAllText($p))
  foreach($m in @('SHARPEMU_V74_0_84_DEMONS_UI_BINK_INTERNAL_COMPOSITOR','SHARPEMU_V74_0_84_UI_BINK_INTERNAL_ROUTING','IsDemonSoulsUiBinkCompositePathV74084')){if(-not$hv.Contains($m)){throw "Host marker missing: $m"}}
  if(-not$av.Contains('SHARPEMU_V74_0_84_UI_BINK_GUEST_LIVE_PASSTHROUGH')){throw 'Assist V84 marker missing'}
  foreach($m in @('SHARPEMU_V74_0_84_UI_BINK_COLOR_CONTRACT','SHARPEMU_V74_0_84_UI_BINK_GUEST_CHROMA_ORDER','NormalizeDemonSoulsUiBinkChromaV74084')){if(-not$pv.Contains($m)){throw "Presenter marker missing: $m"}}

  Write-Host '[V74.0.84] STRUCTURAL PATCH APPLIED.' -ForegroundColor Green
  Write-Host "BaseBGRAChromaOrder=$baseOrder"
  Write-Host "HostPostSHA256=$(Sha $h)";Write-Host "AssistPostSHA256=$(Sha $a)";Write-Host "PresenterPostSHA256=$(Sha $p)";Write-Host "Backup=$bdir"
 }catch{
  foreach($dst in @($h,$a,$p)){$src=Join-Path $bdir (Split-Path $dst -Leaf);if(Test-Path $src){Copy-Item $src $dst -Force}}
  Write-Host "[V74.0.84][ERROR] APPLY FAILED: $($_.Exception.Message)" -ForegroundColor Red
  Write-Host '[V74.0.84] SAFE rollback completed.' -ForegroundColor Yellow;exit 1
 }
}
Get-Process SharpEmu -ErrorAction SilentlyContinue|Stop-Process -Force -ErrorAction SilentlyContinue
$log=Join-Path $patches ("SharpEmu_V74_0_84_UI_BINK_COLOR_SYNC_BUILD_"+(Get-Date -Format yyyyMMdd_HHmmss)+'.log')
& dotnet build (Join-Path $repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj') -c Debug -r win-x64 2>&1|Tee-Object -FilePath $log
$code=$LASTEXITCODE
if($code-ne 0){
 if($bdir){foreach($dst in @($h,$a,$p)){Copy-Item (Join-Path $bdir (Split-Path $dst -Leaf)) $dst -Force}}
 Write-Host '[V74.0.84][ERROR] BUILD FAILED; SAFE rollback completed.' -ForegroundColor Red;exit $code
}
Write-Host '[V74.0.84] APPLY + BUILD PASSED.' -ForegroundColor Green
Write-Host "BuildLog=$log"
