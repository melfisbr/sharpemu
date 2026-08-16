param([string]$RepositoryRoot="",[string]$Eboot='F:\JOGOSPS5\PPSA01341\eboot.bin')
. (Join-Path $PSScriptRoot 'common.ps1')
$root=Resolve-RepoV74026 -RepositoryRoot $RepositoryRoot
$agc=Get-AgcV74026 -Root $root
$host=Get-HostMovieV74026 -Root $root
$ah=(Get-FileHash -LiteralPath $agc -Algorithm SHA256).Hash
if($ah -ne 'BDA0ACF6EF270F108628682ED890786AF2A1119E59F3A4E55853F427ED09E804'){throw "[V74.0.26] AGC correction not installed: $ah"}
$ms=Get-MediaDedupeStateV74026 -Text ([IO.File]::ReadAllText($host))
if($ms -ne 'Applied'){throw "[V74.0.26] Media correction not installed: $ms"}
$eh=(Get-FileHash -LiteralPath $Eboot -Algorithm SHA256).Hash
if($eh -ne '22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E'){throw "[V74.0.26] EBOOT SHA256 mismatch: $eh"}

$rr=[IO.Path]::Combine($root,'artifacts','bin','Release','net10.0','win-x64')
$exe=[IO.Path]::Combine($rr,'SharpEmu.exe')
$dll=[IO.Path]::Combine($rr,'SharpEmu.dll')
if([IO.File]::Exists($exe)){$file=$exe;$args=@($Eboot)}elseif([IO.File]::Exists($dll)){$file='dotnet';$args=@($dll,$Eboot)}else{throw '[V74.0.26] Release executable missing.'}

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$out=[IO.Path]::Combine($root,"SharpEmu_V74_0_26_FAST_WRITE_DEDUPE_RESULT_$stamp")
[IO.Directory]::CreateDirectory($out)|Out-Null
$stdout=[IO.Path]::Combine($out,'stdout.log')
$stderr=[IO.Path]::Combine($out,'stderr.log')
[IO.File]::Copy($agc,[IO.Path]::Combine($out,'AgcExports_V74_0_26.cs'),$true)
[IO.File]::Copy($host,[IO.Path]::Combine($out,'HostMovieBridge_V31_7_11.cs'),$true)

$vars=@('SHARPEMU_WRITE_DATA_PACKET_POSITION','SHARPEMU_BINK_DEDUPE_HOST_BOOT_REPLAY','SHARPEMU_LOG_AGC','SHARPEMU_LOG_AGC_SHADER','SHARPEMU_LOG_VK_SHADER','SHARPEMU_LOG_VK_COMPUTE_RESOURCES','SHARPEMU_TRACE_RENDER_WORK','SHARPEMU_TRACE_ORDERED_ACTION_LATENCY','SHARPEMU_TRACE_DCC_ALIAS','SHARPEMU_TRACE_GUEST_IMAGES','SHARPEMU_TRACE_SCANOUT_LINEAGE','SHARPEMU_PROFILE_RENDER','SHARPEMU_PERF_MEM','SHARPEMU_OVERLAY')
$old=@{}
foreach($v in $vars){$old[$v]=[Environment]::GetEnvironmentVariable($v,'Process')}
try{
    $env:SHARPEMU_WRITE_DATA_PACKET_POSITION='1'
    Remove-Item Env:SHARPEMU_BINK_DEDUPE_HOST_BOOT_REPLAY -ErrorAction SilentlyContinue
    foreach($v in @('SHARPEMU_LOG_AGC','SHARPEMU_LOG_AGC_SHADER','SHARPEMU_LOG_VK_SHADER','SHARPEMU_LOG_VK_COMPUTE_RESOURCES','SHARPEMU_TRACE_RENDER_WORK','SHARPEMU_TRACE_ORDERED_ACTION_LATENCY','SHARPEMU_TRACE_DCC_ALIAS','SHARPEMU_TRACE_GUEST_IMAGES','SHARPEMU_TRACE_SCANOUT_LINEAGE','SHARPEMU_PROFILE_RENDER','SHARPEMU_PERF_MEM','SHARPEMU_OVERLAY')){[Environment]::SetEnvironmentVariable($v,'0','Process')}
    Write-Host '[V74.0.26] RELEASE low-trace test: expect one PS Studios RAD playback and much shorter WRITE_DATA waits.' -ForegroundColor Cyan
    Write-Host '[V74.0.26] Close SharpEmu when LANGUAGE SELECT/interactive UI appears.' -ForegroundColor Cyan
    $sw=[Diagnostics.Stopwatch]::StartNew()
    $p=Start-Process -FilePath $file -ArgumentList $args -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    $p.WaitForExit();$p.WaitForExit();$sw.Stop()
    try{$exitCode=$p.ExitCode}catch{$exitCode='unavailable'}
    $wall=[Math]::Round($sw.Elapsed.TotalSeconds,3)
} finally {
    foreach($v in $vars){if($null -eq $old[$v]){Remove-Item ('Env:'+$v) -ErrorAction SilentlyContinue}else{[Environment]::SetEnvironmentVariable($v,[string]$old[$v],'Process')}}
}

$so=@();$se=@()
if([IO.File]::Exists($stdout)){$so=@([IO.File]::ReadAllLines($stdout))}
if([IO.File]::Exists($stderr)){$se=@([IO.File]::ReadAllLines($stderr))}
function M([string[]]$l,[string]$n){@($l|Where-Object{$_.IndexOf($n,[StringComparison]::OrdinalIgnoreCase)-ge 0})}

$dd=-1
for($i=0;$i -lt $se.Count;$i++){if($dd -lt 0 -and $se[$i] -match 'bink2\.direct_boot_completed'){$dd=$i}}
$psAll=@($se|Where-Object{$_ -match 'Bink RAD bridge attached: ps_studios_logo\.bk2'})
$psPost=@()
if($dd -ge 0){for($i=$dd+1;$i -lt $se.Count;$i++){if($se[$i] -match 'Bink RAD bridge attached: ps_studios_logo\.bk2'){$psPost += $se[$i]}}}
$natural=@(M $se 'bink2.natural_guest_movie_observed')
$dedupe=@(M $se 'bink2.guest_replay_deduped')
$wait=@(M $se '[V74.0.25][WAIT_RESUME]')
$wp=@(M $se '[V74.0.25][WRITE_DATA_PACKET_POSITION]')
$guest=@(M $se 'Vulkan VideoOut presented guest frame')
$main=@(M $so 'Starting main loop')
$unres=@(M $se 'unresolved:')
$lost=@(M $se 'deviceLost=True')

$vals=New-Object 'System.Collections.Generic.List[double]'
foreach($line in $wait){if($line -match 'waited_ms=([0-9]+[\.,][0-9]+)'){$vals.Add([double]::Parse($matches[1].Replace(',','.'),[Globalization.CultureInfo]::InvariantCulture))}}
$max=if($vals.Count){($vals|Measure-Object -Maximum).Maximum}else{0}
$avg=if($vals.Count){($vals|Measure-Object -Average).Average}else{0}
$over1=@($vals|Where-Object{$_ -ge 1000}).Count
$over4=@($vals|Where-Object{$_ -ge 4000}).Count

foreach($pair in @(@('PS_STUDIOS_ATTACH_ALL.txt',$psAll),@('PS_STUDIOS_ATTACH_POST_DIRECT.txt',$psPost),@('NATURAL_GUEST_MOVIES.txt',$natural),@('GUEST_REPLAY_DEDUPED.txt',$dedupe),@('WAIT_RESUME.txt',$wait),@('WRITE_DATA_PACKET_POSITION.txt',$wp))){[IO.File]::WriteAllLines([IO.Path]::Combine($out,$pair[0]),[string[]]$pair[1],[Text.UTF8Encoding]::new($false))}

$summary=@(
'version=74.0.26',
'mode=write-data-packet-position-no-gpu-readback+host-boot-replay-dedupe-default',
"wall_seconds=$wall",
"exit_code=$exitCode",
"stderr_lines=$($se.Count)",
"stdout_lines=$($so.Count)",
"agc_sha256=$ah",
"media_state=$ms",
"ps_studios_rad_attaches_total=$($psAll.Count)",
"ps_studios_rad_attaches_post_direct=$($psPost.Count)",
"natural_guest_movie_observed=$($natural.Count)",
"guest_replay_deduped=$($dedupe.Count)",
"write_data_packet_position_logs=$($wp.Count)",
"wait_resume_logs=$($wait.Count)",
"wait_max_ms=$([Math]::Round([double]$max,3))",
"wait_avg_ms=$([Math]::Round([double]$avg,3))",
"wait_over_1s=$over1",
"wait_over_4s=$over4",
"guest_frames=$($guest.Count)",
"main_loop=$($main.Count)",
"runtime_unresolved=$($unres.Count)",
"device_lost=$($lost.Count)"
)
[IO.File]::WriteAllLines([IO.Path]::Combine($out,'SUMMARY.txt'),$summary,[Text.UTF8Encoding]::new($false))
$zip=$out+'.zip'
Compress-Archive -Path ([IO.Path]::Combine($out,'*')) -DestinationPath $zip -Force
Write-Host "[V74.0.26] RESULT: $zip" -ForegroundColor Green
Write-Host ($summary -join ' | ')
