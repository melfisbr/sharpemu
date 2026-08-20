. "$PSScriptRoot\common.ps1"
$pkg=PackageRoot; $repo=RepoRoot; $patches=Patches; $p=Presenter
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'precheck.ps1')
$pre=$LASTEXITCODE
if ($pre -ne 0 -and $pre -ne 10) { exit $pre }
$bdir=$null
if ($pre -ne 10) {
    $stamp=Get-Date -Format yyyyMMdd_HHmmss
    $bdir=Join-Path $pkg ("backup\"+$stamp)
    New-Item -ItemType Directory -Force $bdir | Out-Null
    Copy-Item $p (Join-Path $bdir 'VulkanVideoPresenter.cs') -Force
    Set-Content (Join-Path $pkg 'LAST_BACKUP.txt') $bdir -Encoding UTF8
    try {
        $ps=[IO.File]::ReadAllText($p); $ps=NL $ps

        $field='        private long _v740841UiBinkChromaTraceCount;'
        if ((CountExact $ps $field) -ne 1) { throw "V84.1 field anchor count=$(CountExact $ps $field)" }
        $at=$ps.IndexOf($field,[StringComparison]::Ordinal)+$field.Length
        $fields=Patch 'Presenter.fields.insert.txt'
        $ps=$ps.Substring(0,$at)+$fields+$ps.Substring($at)

        $findDecl='        private HostMovieTextureBindings FindHostMovieTextureBindings('
        if ((CountExact $ps $findDecl) -ne 1) { throw 'FindHostMovieTextureBindings declaration changed' }
        $idx=$ps.IndexOf($findDecl,[StringComparison]::Ordinal)
        $helpers=Patch 'Presenter.helpers.insert.txt'
        $ps=$ps.Substring(0,$idx)+$helpers+$ps.Substring($idx)

        $pump=FindMethodSpan $ps '(?m)^[ \t]*private void PumpHostMovieFrame\(\)\s*$' 'PumpHostMovieFrame'
        $pb=Body $ps $pump
        $resetNeedle=@'
                _hostMovieLumaUploadedFrameSerial = -1;
                _hostMovieChromaUploadedFrameSerial = -1;
'@
        $resetNeedle=NL $resetNeedle
        $resetNeedle=$resetNeedle.Trim("`n")
        if ((CountExact $pb $resetNeedle) -ne 1) { throw "Pump reset anchor count=$(CountExact $pb $resetNeedle)" }
        $resetReplacement=@'
                _hostMovieLumaUploadedFrameSerial = -1;
                _hostMovieChromaUploadedFrameSerial = -1;
                _v740842LearnedUiBinkLumaAddresses.Clear();
                _v740842LearnedUiBinkChromaAddresses.Clear();
'@
        $resetReplacement=NL $resetReplacement
        $resetReplacement=$resetReplacement.Trim("`n")
        $pb=$pb.Replace($resetNeedle,$resetReplacement)

        $frameNeedle=@'
            _hostMovieFramePixels = pixels;
            _hostMovieFrameWidth = width;
            _hostMovieFrameHeight = height;
            _hostMovieFrameSerial = frameSerial;
'@
        $frameNeedle=NL $frameNeedle
        $frameNeedle=$frameNeedle.Trim("`n")
        if ((CountExact $pb $frameNeedle) -ne 1) { throw "Pump frame assignment anchor count=$(CountExact $pb $frameNeedle)" }
        $frameReplacement=@'
            if (HostMovieBridge.IsDemonSoulsUiBinkCompositePathV740841(hostPath))
            {
                if (_v740842OwnedUiBinkFramePixels is null ||
                    _v740842OwnedUiBinkFramePixels.Length != pixels.Length)
                {
                    _v740842OwnedUiBinkFramePixels = new byte[pixels.Length];
                }
                pixels.AsSpan().CopyTo(_v740842OwnedUiBinkFramePixels);
                _hostMovieFramePixels = _v740842OwnedUiBinkFramePixels;

                var snapshot = Interlocked.Increment(
                    ref _v740842UiBinkFrameSnapshotCount);
                if (snapshot <= 16 || (snapshot & (snapshot - 1)) == 0)
                {
                    Console.Error.WriteLine(
                        "[V74.0.84.2.1][UI_BINK_FRAME_SNAPSHOT] " +
                        $"count={snapshot} file='{Path.GetFileName(hostPath)}' " +
                        $"serial={frameSerial} bytes={pixels.Length} " +
                        "source=decoder-buffer copy=presenter-owned");
                }
            }
            else
            {
                _hostMovieFramePixels = pixels;
            }
            _hostMovieFrameWidth = width;
            _hostMovieFrameHeight = height;
            _hostMovieFrameSerial = frameSerial;
'@
        $frameReplacement=NL $frameReplacement
        $frameReplacement=$frameReplacement.Trim("`n")
        $pb=$pb.Replace($frameNeedle,$frameReplacement)
        $ps=ReplaceBody $ps $pump $pb

        $find=FindMethodSpan $ps '(?m)^[ \t]*private HostMovieTextureBindings FindHostMovieTextureBindings\(' 'FindHostMovieTextureBindings'
        $fb=Body $ps $find

        # V84.2.1 structural repair: the accumulated checkout can contain
        # comments or additional guards inside the "pair not found" branch.
        # Do not require an exact multi-line block. The first None return is
        # the no-host-frame guard; the last None return is the discovery miss.
        $noneRx=[regex]::new(
            '(?m)^(?<indent>[ \t]*)return HostMovieTextureBindings\.None;[ \t]*$')
        $noneMatches=$noneRx.Matches($fb)
        if ($noneMatches.Count -lt 2) {
            throw "FindHostMovieTextureBindings None-return count=$($noneMatches.Count); expected at least 2"
        }
        $lastNone=$noneMatches[$noneMatches.Count-1]
        $noneIndent=$lastNone.Groups['indent'].Value
        $fallback=$noneIndent+'return FindLearnedUiBinkTextureBindingsV740842(textures);'
        $fb=$fb.Substring(0,$lastNone.Index)+$fallback+$fb.Substring($lastNone.Index+$lastNone.Length)
        $ps=ReplaceBody $ps $find $fb

        $remember=FindMethodSpan $ps '(?m)^[ \t]*private HostMovieTextureBindings RememberHostMovieTextureMappings\(' 'RememberHostMovieTextureMappings'
        $rb=Body $ps $remember
        $rememberReturnRx=[regex]::new(
            '(?m)^(?<indent>[ \t]*)return new HostMovieTextureBindings\(lumaIndex, chromaIndex\);[ \t]*$')
        $rememberReturns=$rememberReturnRx.Matches($rb)
        if ($rememberReturns.Count -ne 1) {
            throw "RememberHostMovieTextureMappings return count=$($rememberReturns.Count)"
        }
        $rr=$rememberReturns[0]
        $ri=$rr.Groups['indent'].Value
        $learn=@'
            if (IsUiBinkStickyPlaneEnabledV740842() &&
                HostMovieBridge.IsDemonSoulsUiBinkCompositePathV740841(
                    _hostMovieFramePath))
            {
                var learnedLuma = _v740842LearnedUiBinkLumaAddresses.Add(
                    textures[lumaIndex].Address);
                var learnedChroma = _v740842LearnedUiBinkChromaAddresses.Add(
                    textures[chromaIndex].Address);
                if (learnedLuma || learnedChroma)
                {
                    var trace = Interlocked.Increment(
                        ref _v740842UiBinkPlaneLearnCount);
                    Console.Error.WriteLine(
                        "[V74.0.84.2.1][UI_BINK_PLANE_LEARN] " +
                        $"count={trace} file='{Path.GetFileName(_hostMovieFramePath)}' " +
                        $"y=0x{textures[lumaIndex].Address:X16} " +
                        $"uv=0x{textures[chromaIndex].Address:X16} " +
                        $"learned_y={_v740842LearnedUiBinkLumaAddresses.Count} " +
                        $"learned_uv={_v740842LearnedUiBinkChromaAddresses.Count}");
                }
            }

'@
        $learn=NL $learn
        # The inserted block is authored at the method's normal indentation.
        # Re-indent if the checkout uses a different return indentation.
        $learnLines=$learn.Trim("`n") -split "`n"
        $learnAdjusted=($learnLines | ForEach-Object {
            if ($_.Length -ge 12) { $ri+$_.Substring(12) } else { $ri+$_ }
        }) -join "`n"
        $rb=$rb.Substring(0,$rr.Index)+$learnAdjusted+"`n"+$rb.Substring($rr.Index)
        $ps=ReplaceBody $ps $remember $rb

        WritePreserving $p $ps
        $pv=[IO.File]::ReadAllText($p); $pv=NL $pv
        foreach ($m in @(
            'SHARPEMU_V74_0_84_2_1_UI_BINK_FRAME_OWNERSHIP',
            'SHARPEMU_V74_0_84_2_1_UI_BINK_STICKY_PLANE_INTEGRITY',
            'UI_BINK_FRAME_SNAPSHOT',
            'UI_BINK_STICKY_PLANE',
            'UI_BINK_PLANE_LEARN')) {
            if (-not $pv.Contains($m)) { throw "post-apply marker missing: $m" }
        }
        Write-Host '[V74.0.84.2.1] STRUCTURAL PATCH APPLIED.' -ForegroundColor Green
        Write-Host "PresenterPostSHA256=$(Sha $p)"
        Write-Host "Backup=$bdir"
    } catch {
        $src=Join-Path $bdir 'VulkanVideoPresenter.cs'
        if (Test-Path $src) { Copy-Item $src $p -Force }
        Write-Host "[V74.0.84.2.1][ERROR] APPLY FAILED: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host '[V74.0.84.2.1] SAFE rollback completed.' -ForegroundColor Yellow
        exit 1
    }
}
Get-Process SharpEmu -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
$log=Join-Path $patches ("SharpEmu_V74_0_84_2_1_UI_BINK_INTEGRITY_BUILD_"+(Get-Date -Format yyyyMMdd_HHmmss)+'.log')
& dotnet build (Join-Path $repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj') -c Debug -r win-x64 2>&1 | Tee-Object -FilePath $log
$code=$LASTEXITCODE
if ($code -ne 0) {
    if ($bdir) {
        $src=Join-Path $bdir 'VulkanVideoPresenter.cs'
        if (Test-Path $src) { Copy-Item $src $p -Force }
    }
    Write-Host '[V74.0.84.2.1][ERROR] BUILD FAILED; SAFE rollback completed.' -ForegroundColor Red
    exit $code
}
Write-Host '[V74.0.84.2.1] APPLY + BUILD PASSED.' -ForegroundColor Green
Write-Host "BuildLog=$log"
