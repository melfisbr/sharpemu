. "$PSScriptRoot\common.ps1"
$pkg=PackageRoot;$repo=RepoRoot;$patches=Patches;$h=Host
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'precheck.ps1');$pre=$LASTEXITCODE
if($pre-ne 0-and$pre-ne 10){exit $pre}
$bdir=$null
if($pre-ne 10){
 $stamp=Get-Date -Format yyyyMMdd_HHmmss;$bdir=Join-Path $pkg ("backup\"+$stamp);New-Item -ItemType Directory -Force $bdir|Out-Null
 Copy-Item $h (Join-Path $bdir 'HostMovieBridge.cs') -Force;Set-Content (Join-Path $pkg 'LAST_BACKUP.txt') $bdir -Encoding UTF8
 try{
  $s=NL([IO.File]::ReadAllText($h))
  $helper=@'
    // SHARPEMU_V74_0_77_2_DEMONS_ATTRACT_GUEST_COMPLETION
    // The host RAD player owns attract_movie visually, but the guest still owns
    // the Bink object/state machine. Reconcile the guest header to one frame and
    // gate that completion on the real host end/Options skip. This lets the
    // game's own MusicSkipIntro/StartIntro/SceneAboutToBeUncovered path advance.
    private static int _v740772AttractGuestCompletionCount;

    private static bool ShouldUseDemonSoulsAttractGuestCompletionV740772(string hostPath)
    {
        if (string.Equals(
                Environment.GetEnvironmentVariable(
                    "SHARPEMU_BINK_ATTRACT_GUEST_COMPLETION"),
                "0",
                StringComparison.Ordinal))
        {
            return false;
        }

        if (ResolveMode() != MovieMode.Rad ||
            !string.Equals(
                Path.GetFileName(hostPath),
                "attract_movie.bk2",
                StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        try
        {
            var app0 = Environment.GetEnvironmentVariable("SHARPEMU_APP0_DIR");
            if (!string.IsNullOrWhiteSpace(app0))
            {
                var root = Path.TrimEndingDirectorySeparator(Path.GetFullPath(app0));
                var movie = Path.GetFullPath(hostPath);
                if (!movie.StartsWith(
                        root + Path.DirectorySeparatorChar,
                        StringComparison.OrdinalIgnoreCase))
                {
                    return false;
                }

                var rootName = Path.GetFileName(root);
                return
                    string.Equals(rootName, "PPSA01341", StringComparison.OrdinalIgnoreCase) ||
                    rootName.StartsWith("PPSA25646", StringComparison.OrdinalIgnoreCase) ||
                    File.Exists(Path.Combine(root, "DemonsSoul_PROSPERO_Release.elf"));
            }
        }
        catch
        {
        }

        return hostPath.Contains(
                   $"{Path.DirectorySeparatorChar}PPSA01341{Path.DirectorySeparatorChar}",
                   StringComparison.OrdinalIgnoreCase) ||
               hostPath.Contains(
                   $"{Path.DirectorySeparatorChar}PPSA25646",
                   StringComparison.OrdinalIgnoreCase);
    }

'@
  $decl='    internal static bool TryTakeOverGuestMovie('
  if((CountExact $s $decl)-ne 1){throw "TryTakeOverGuestMovie locator count=$(CountExact $s $decl)"}
  $idx=$s.IndexOf($decl,[StringComparison]::Ordinal);$s=$s.Substring(0,$idx)+$helper+$s.Substring($idx)

  $span=FindMethodSpan $s '(?m)^[ \t]*internal static bool TryTakeOverGuestMovie\(' 'TryTakeOverGuestMovie';$b=Body $s $span
  $needle="        var v7405610LegacyStartupCompletionShim =`n            IsOneShotStartupBinkV74013(hostPath);"
  if((CountExact $b $needle)-ne 1){throw "legacy var anchor count=$(CountExact $b $needle)"}
  $replacement=$needle+"`n        var v740772AttractGuestCompletionHandoff =`n            ShouldUseDemonSoulsAttractGuestCompletionV740772(hostPath);"
  $b=$b.Replace($needle,$replacement)

  $rx=[regex]::new('if\s*\(!observed\s*\|\|\s*\(\s*!v7405610RadGuestCompletionHandoff\s*&&\s*!v7405610LegacyStartupCompletionShim\s*\)\s*\)\s*\{\s*return false;\s*\}',[Text.RegularExpressions.RegexOptions]::Singleline)
  if($rx.Matches($b).Count-ne 1){throw "takeover condition count=$($rx.Matches($b).Count)"}
  $b=$rx.Replace($b,@'
if (!observed ||
            (!v7405610RadGuestCompletionHandoff &&
             !v7405610LegacyStartupCompletionShim &&
             !v740772AttractGuestCompletionHandoff))
        {
            return false;
        }
'@,1)

  $branch='        if (v7405610RadGuestCompletionHandoff)'
  if((CountExact $b $branch)-ne 1){throw "logging branch count=$(CountExact $b $branch)"}
  $new=@'
        if (v740772AttractGuestCompletionHandoff)
        {
            var n = Interlocked.Increment(
                ref _v740772AttractGuestCompletionCount);
            Console.Error.WriteLine(
                precise
                    ? "[V74.0.77.2][ATTRACT_GUEST_COMPLETION] armed mode=precise n=" + n +
                        " file='" + Path.GetFileName(hostPath) +
                        "' guest_open=success num_frames=1 wait_on_header_read=True release=host-end-or-options-skip guest_state_machine_owner=True"
                    : "[V74.0.77.2][ATTRACT_GUEST_COMPLETION] armed mode=header-fallback n=" + n +
                        " file='" + Path.GetFileName(hostPath) +
                        "' guest_open=success num_frames=1 wait_on_header_read=True release=host-end-or-options-skip guest_state_machine_owner=True");
        }
        else if (v7405610RadGuestCompletionHandoff)
'@
  $b=$b.Replace($branch,$new.TrimEnd("`r","`n"))
  $s=ReplaceBody $s $span $b
  WritePreserving $h $s

  $v=NL([IO.File]::ReadAllText($h))
  foreach($m in @('SHARPEMU_V74_0_77_2_DEMONS_ATTRACT_GUEST_COMPLETION','ShouldUseDemonSoulsAttractGuestCompletionV740772','v740772AttractGuestCompletionHandoff','[V74.0.77.2][ATTRACT_GUEST_COMPLETION]')){if(-not$v.Contains($m)){throw "post-apply marker missing: $m"}}
  Write-Host '[V74.0.77.2] STRUCTURAL PATCH APPLIED.' -ForegroundColor Green
  Write-Host "Backup=$bdir";Write-Host "HostPostSHA256=$(Sha $h)"
 }catch{
  Copy-Item (Join-Path $bdir 'HostMovieBridge.cs') $h -Force
  Write-Host "[V74.0.77.2][ERROR] APPLY FAILED: $($_.Exception.Message)" -ForegroundColor Red
  Write-Host '[V74.0.77.2] SAFE rollback completed.' -ForegroundColor Yellow;exit 1
 }
}
Get-Process SharpEmu -ErrorAction SilentlyContinue|Stop-Process -Force -ErrorAction SilentlyContinue
$log=Join-Path $patches ("SharpEmu_V74_0_77_2_ATTRACT_GUEST_COMPLETION_BUILD_"+(Get-Date -Format yyyyMMdd_HHmmss)+'.log')
& dotnet build (Join-Path $repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj') -c Debug -r win-x64 2>&1|Tee-Object -FilePath $log
$code=$LASTEXITCODE
if($code-ne 0){
 if($bdir){Copy-Item (Join-Path $bdir 'HostMovieBridge.cs') $h -Force}
 Write-Host '[V74.0.77.2][ERROR] BUILD FAILED; SAFE rollback completed.' -ForegroundColor Red;exit $code
}
Write-Host '[V74.0.77.2] APPLY + BUILD PASSED.' -ForegroundColor Green
Write-Host "BuildLog=$log"
