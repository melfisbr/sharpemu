. "$PSScriptRoot\common.ps1"
$repo=RepoRoot;$patches=Patches;$pkg=PackageRoot
$eboot=$env:SHARPEMU_DEMONS_EBOOT;if([string]::IsNullOrWhiteSpace($eboot)){$eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'}
$exe=Join-Path $repo 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'
if(-not(Test-Path $exe)){Write-Host "[V74.0.77.2][ERROR] build artifact missing: $exe" -ForegroundColor Red;exit 1}
if(-not(Test-Path $eboot)){Write-Host "[V74.0.77.2][ERROR] eboot missing: $eboot" -ForegroundColor Red;exit 1}
Get-Process SharpEmu -ErrorAction SilentlyContinue|Stop-Process -Force -ErrorAction SilentlyContinue
$stamp=Get-Date -Format yyyyMMdd_HHmmss
$runtime=Join-Path $patches ("SharpEmu_V74_0_77_2_ATTRACT_GUEST_COMPLETION_RUNTIME_"+$stamp+'.log')
$report=Join-Path $patches ("SharpEmu_V74_0_77_2_ATTRACT_GUEST_COMPLETION_RESULT_"+$stamp+'.log')
$zip=Join-Path $patches ("SharpEmu_V74_0_77_2_ATTRACT_GUEST_COMPLETION_RESULT_"+$stamp+'.zip')
$env:SHARPEMU_BINK_ATTRACT_GUEST_COMPLETION='1'
Write-Host ''
Write-Host '[V74.0.77.2] TESTE:' -ForegroundColor Cyan
Write-Host '1. Deixe o jogo chegar ao attract_movie.'
Write-Host '2. Pressione TAB uma unica vez para pular o attract.'
Write-Host '3. Aguarde o guest tentar iniciar a transicao/intro natural.'
Write-Host '4. Depois da evidencia visual, feche o SharpEmu.'
Write-Host ''
$psi=[Diagnostics.ProcessStartInfo]::new();$psi.FileName=$exe;$psi.ArgumentList.Add($eboot)
$psi.UseShellExecute=$false;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
$p=[Diagnostics.Process]::new();$p.StartInfo=$psi;[void]$p.Start()
$outTask=$p.StandardOutput.ReadToEndAsync();$errTask=$p.StandardError.ReadToEndAsync();$p.WaitForExit()
$all=$errTask.Result+"`r`n"+$outTask.Result
[IO.File]::WriteAllText($runtime,$all,(New-Object Text.UTF8Encoding($false)))
$lines=$all -split "`r?`n"
$arm=@($lines|Where-Object{$_ -match '\[V74\.0\.77\.2\]\[ATTRACT_GUEST_COMPLETION\] armed'})
$skip=@($lines|Where-Object{$_ -match 'movie_skipped.*attract_movie\.bk2'})
$logo=@($lines|Where-Object{$_ -match "natural_guest_movie_observed.*logo_intro\.bk2"})
$loop=@($lines|Where-Object{$_ -match "natural_guest_movie_observed.*logo_intro_loop\.bk2|INTERNAL_TITLE_MENU_LOOP.*logo_intro_loop\.bk2"})
$idx=-1;for($i=0;$i-lt$lines.Length;$i++){if($lines[$i]-match 'movie_skipped.*attract_movie\.bk2'){$idx=$i;break}}
$post=if($idx-ge 0){$lines[($idx+1)..($lines.Length-1)]}else{@()}
$postWait=@($post|Where-Object{$_ -match 'agc\.wait_suspended'})
$postDirect=@($post|Where-Object{$_ -match '\[DIRECT_SCANOUT\]'})
$postBink=@($post|Where-Object{$_ -match 'bink2\.natural_guest_movie_observed|logo_intro\.bk2|logo_intro_loop\.bk2|ATTRACT_GUEST_COMPLETION'})
$o=@()
$o+='[V74.0.77.2] RUNTIME RESULT'
$o+="ExitCode=$($p.ExitCode)"
$o+="attract_guest_completion_arm_count=$($arm.Count)"
$o+="attract_skip_count=$($skip.Count)"
$o+="natural_logo_intro_count=$($logo.Count)"
$o+="natural_logo_intro_loop_or_internal_count=$($loop.Count)"
$o+="post_skip_wait_suspended_count=$($postWait.Count)"
$o+="post_skip_direct_scanout_count=$($postDirect.Count)"
if($arm.Count-gt 0-and$skip.Count-gt 0-and$logo.Count-gt 0){$o+='verdict=PASS_GUEST_STATE_ADVANCED_TO_NATURAL_LOGO_INTRO'}
elseif($arm.Count-eq 0){$o+='verdict=FAIL_ATTRACT_COMPLETION_SHIM_NOT_ARMED'}
elseif($skip.Count-eq 0){$o+='verdict=INCOMPLETE_ATTRACT_NOT_SKIPPED'}
else{$o+='verdict=GUEST_COMPLETION_RELEASED_BUT_NEXT_STATE_NOT_OBSERVED'}
$o+='--- relevant post-skip Bink/title lines ---';$o+=@($postBink|Select-Object -First 200)
$o|Set-Content $report -Encoding UTF8;$o|ForEach-Object{Write-Host $_}
$stage=Join-Path $env:TEMP ("SharpEmuV740772_"+$stamp);New-Item -ItemType Directory -Force $stage|Out-Null
Copy-Item $runtime (Join-Path $stage 'runtime.log');Copy-Item $report (Join-Path $stage 'result.log');Copy-Item (Join-Path $pkg 'ANALYSIS.txt') $stage
$latestAudit=Get-ChildItem $patches -Filter 'SharpEmu_V74_0_77_2_EBOOT_AUDIT_*.log'|Sort LastWriteTime -Descending|Select -First 1;if($latestAudit){Copy-Item $latestAudit.FullName (Join-Path $stage 'eboot_audit.log')}
$latestBuild=Get-ChildItem $patches -Filter 'SharpEmu_V74_0_77_2_ATTRACT_GUEST_COMPLETION_BUILD_*.log'|Sort LastWriteTime -Descending|Select -First 1;if($latestBuild){Copy-Item $latestBuild.FullName (Join-Path $stage 'build.log')}
Compress-Archive (Join-Path $stage '*') $zip -Force;Remove-Item $stage -Recurse -Force
Write-Host "RuntimeLog=$runtime";Write-Host "ResultLog=$report";Write-Host "RESULT ZIP=$zip"
