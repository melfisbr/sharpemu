param([string]$RuntimePath='')
. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepositoryRoot
$patches=Get-PatchesRoot
$runtimeLabel='local-fork-only'

function Add-Candidate([System.Collections.Generic.List[string]]$List,[string]$Path){
  if([string]::IsNullOrWhiteSpace($Path)){return}
  try{$full=[IO.Path]::GetFullPath($Path.Trim().Trim('"'))}catch{return}
  if(Test-Path -LiteralPath $full -PathType Leaf){
    if([IO.Path]::GetFileName($full)-ieq 'ffmpeg.exe' -and -not $List.Contains($full)){$List.Add($full)}
    return
  }
  if(Test-Path -LiteralPath $full -PathType Container){
    $items=@(Get-ChildItem -LiteralPath $full -Recurse -File -Filter 'ffmpeg.exe' -ErrorAction SilentlyContinue | Select-Object -First 8)
    foreach($item in $items){if(-not $List.Contains($item.FullName)){$List.Add($item.FullName)}}
  }
}
function Find-ProbeMovie {
  $roots=New-Object System.Collections.Generic.List[string]
  foreach($r in @([Environment]::GetEnvironmentVariable('SHARPEMU_APP0_DIR'),'F:\JOGOSPS5\PPSA01341')){
    if($r -and (Test-Path -LiteralPath $r -PathType Container) -and -not $roots.Contains($r)){$roots.Add($r)}
  }
  foreach($r in $roots){
    $item=Get-ChildItem -LiteralPath $r -Recurse -File -Filter 'ps_studios_logo.bk2' -ErrorAction SilentlyContinue | Select-Object -First 1
    if($null -ne $item){return $item.FullName}
  }
  return $null
}
function Test-FfmpegCandidate([string]$Exe,[string]$ProbeMovie){
  if((Get-PeMachine $Exe)-ne 0x8664){Write-Tag "SKIP runtime non-AMD64 path=$Exe";return $false}
  try{
    $version=@(& $Exe -hide_banner -version 2>&1 | Select-Object -First 2 | ForEach-Object{$_.ToString()})
    if($LASTEXITCODE -ne 0){Write-Tag "SKIP runtime start-failed path=$Exe";return $false}
    if($ProbeMovie){
      & $Exe -hide_banner -loglevel error -nostdin -i $ProbeMovie -map 0:v:0 -frames:v 1 -f null NUL *> $null
      if($LASTEXITCODE -ne 0){Write-Tag "SKIP runtime Bink2-probe-failed path=$Exe";return $false}
      Write-Tag ("LOCAL RUNTIME VERIFIED path=$Exe probe=Bink2-first-frame version="+($version -join ' | '))
      return $true
    }
    # Without a real BK2 asset we refuse to claim Bink2 capability unless the
    # user explicitly opts into unprobed local runtime use.
    if([Environment]::GetEnvironmentVariable('SHARPEMU_BINK_ALLOW_UNPROBED_FFMPEG') -eq '1'){
      Write-Tag ("LOCAL RUNTIME ACCEPTED UNPROBED path=$Exe version="+($version -join ' | '))
      return $true
    }
    Write-Tag "SKIP runtime cannot verify Bink2 because ps_studios_logo.bk2 was not found; set SHARPEMU_BINK_ALLOW_UNPROBED_FFMPEG=1 only for diagnostic use"
    return $false
  }catch{Write-Tag "SKIP runtime exception path=$Exe detail=$($_.Exception.Message)";return $false}
}
function Deploy-Runtime([string]$Exe){
  $srcDir=Split-Path -Parent $Exe
  foreach($plugin in Get-PluginDirs){
    New-Item -ItemType Directory -Path $plugin -Force|Out-Null
    $dst=Join-Path $plugin 'ffmpeg-runtime'
    if(Test-Path -LiteralPath $dst){Remove-Item -LiteralPath $dst -Recurse -Force}
    New-Item -ItemType Directory -Path $dst -Force|Out-Null
    Copy-Item -LiteralPath $Exe -Destination (Join-Path $dst 'ffmpeg.exe') -Force
    Get-ChildItem -LiteralPath $srcDir -File -Filter '*.dll' -ErrorAction SilentlyContinue | ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination $dst -Force}
    'SharpEmu Bink Native V75.0.4.3 LOCAL-FORK-ONLY runtime; no git/network operation performed.' | Set-Content -LiteralPath (Join-Path $dst '.v75_0_4_3_local_runtime') -Encoding ASCII
    Write-Tag "RUNTIME DEPLOYED=$dst source=$Exe"
  }
}

Write-Tag 'LOCAL-FORK POLICY: git clone/fetch/checkout/reset/clean and network download are DISABLED.'
Write-Tag "RepositoryRoot=$repo"
$candidates=New-Object 'System.Collections.Generic.List[string]'
Add-Candidate $candidates $RuntimePath
Add-Candidate $candidates ([Environment]::GetEnvironmentVariable('SHARPEMU_FFMPEG_CORE_EXE'))
foreach($plugin in Get-PluginDirs){Add-Candidate $candidates (Join-Path $plugin 'ffmpeg-runtime\ffmpeg.exe')}

# Search only local user-controlled SharpEmu/fork areas. Nothing is cloned,
# fetched, reset or checked out. Existing local improvements are untouched.
foreach($rel in @('artifacts','tools','third_party','external','vendor','deps','dependencies')){
  $p=Join-Path $repo $rel
  if(Test-Path -LiteralPath $p -PathType Container){Add-Candidate $candidates $p}
}
Get-ChildItem -LiteralPath $patches -Directory -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match '(?i)ffmpeg' } |
  Select-Object -First 20 |
  ForEach-Object { Add-Candidate $candidates $_.FullName }
$pathFfmpeg=Get-Command ffmpeg.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if($null -ne $pathFfmpeg){Add-Candidate $candidates $pathFfmpeg.Source}

$probeMovie=Find-ProbeMovie
if($probeMovie){Write-Tag "BINK2 PROBE movie=$probeMovie"}else{Write-Tag 'BINK2 PROBE movie not found automatically'}
$selected=$null
foreach($candidate in $candidates){if(Test-FfmpegCandidate $candidate $probeMovie){$selected=$candidate;break}}
if(-not $selected){
  throw "$script:Tag LOCAL Bink2-capable ffmpeg.exe not found. No Git/network action was attempted. Supply an existing local runtime with RUN_4_SETUP_FFMPEGCORE_RUNTIME.cmd `"C:\local\ffmpeg.exe`" or place a compatible runtime inside your fork."
}
Deploy-Runtime $selected
Write-Tag "SETUP PASSED backend=local-only source=$selected external_rad=False proprietary_bink2w64=False git_used=False network_used=False"
