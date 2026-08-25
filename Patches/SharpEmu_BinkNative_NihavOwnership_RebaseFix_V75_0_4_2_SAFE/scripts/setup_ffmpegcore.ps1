param([string]$RuntimePath='')
. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepositoryRoot;$patches=Get-PatchesRoot
$tag='3b502d4'
$vcpkgCommit='34823ada10080ddca99b60e85f80f55e18a44eea'
$triplet='x64-win-llvm-dynamic-release'

function Find-ExeIn([string]$Path){
  if([string]::IsNullOrWhiteSpace($Path)){return $null}
  $p=$Path.Trim().Trim('"')
  if(Test-Path -LiteralPath $p -PathType Leaf){if([IO.Path]::GetFileName($p)-ieq 'ffmpeg.exe'){return (Get-Item $p).FullName};return $null}
  if(Test-Path -LiteralPath $p -PathType Container){$item=Get-ChildItem -LiteralPath $p -Recurse -File -Filter ffmpeg.exe -ErrorAction SilentlyContinue|Select-Object -First 1;if($null -ne $item){return $item.FullName};return $null}
  return $null
}
function Invoke-Native([string]$Exe,[string[]]$Args,[string]$What){
  & $Exe @Args
  if($LASTEXITCODE -ne 0){throw "$script:Tag $What failed exit=$LASTEXITCODE"}
}
function Ensure-GitRepo([string]$Url,[string]$Dir,[string]$Ref){
  if(-not(Test-Path (Join-Path $Dir '.git') -PathType Container)){
    if(Test-Path $Dir){Remove-Item $Dir -Recurse -Force}
    Write-Tag "CLONING $Url"
    Invoke-Native 'git' @('clone','--filter=blob:none',$Url,$Dir) 'git clone'
  }
  Invoke-Native 'git' @('-C',$Dir,'fetch','--tags','origin') 'git fetch'
  Invoke-Native 'git' @('-C',$Dir,'checkout','--force',$Ref) "git checkout $Ref"
}
function Copy-FfmpegRuntime([string]$Exe,[string]$FfmpegPackageRoot){
  $machine=Get-PeMachine $Exe
  if($machine -ne 0x8664){throw "$script:Tag ffmpeg.exe is not AMD64 machine=0x$('{0:X4}' -f $machine) path=$Exe"}
  $version=@(& $Exe -hide_banner -version 2>&1|Select-Object -First 3|ForEach-Object{$_.ToString()})
  if($LASTEXITCODE -ne 0){throw "$script:Tag ffmpeg.exe failed to start path=$Exe"}
  Write-Tag ("FFMPEG READY machine=AMD64 "+($version -join ' | '))
  foreach($plugin in Get-PluginDirs){
    $dst=Join-Path $plugin 'ffmpeg-runtime';New-Item -ItemType Directory -Path $plugin -Force|Out-Null
    if(Test-Path $dst){Remove-Item $dst -Recurse -Force};New-Item -ItemType Directory -Path $dst -Force|Out-Null
    Copy-Item -LiteralPath $Exe -Destination (Join-Path $dst 'ffmpeg.exe') -Force
    if($FfmpegPackageRoot){
      $bin=Join-Path $FfmpegPackageRoot 'bin'
      if(Test-Path $bin -PathType Container){Get-ChildItem -LiteralPath $bin -File -Filter '*.dll' -ErrorAction SilentlyContinue|ForEach-Object{Copy-Item -LiteralPath $_.FullName -Destination $dst -Force}}
    }
    # If caller supplied a ready runtime folder, preserve sibling DLLs too.
    $srcDir=Split-Path -Parent $Exe
    Get-ChildItem -LiteralPath $srcDir -File -Filter '*.dll' -ErrorAction SilentlyContinue|ForEach-Object{Copy-Item -LiteralPath $_.FullName -Destination $dst -Force}
    if(-not(Test-Path (Join-Path $dst 'ffmpeg.exe'))){throw "$script:Tag deploy missing ffmpeg.exe: $dst"}
    "SharpEmu Bink Native V75.0.4.2 ffmpeg-core tag $tag"|Set-Content -LiteralPath (Join-Path $dst '.v75_0_4_2_ffmpeg_core_runtime') -Encoding ASCII
    Write-Tag "RUNTIME DEPLOYED=$dst"
  }
}

$ffmpeg=$null;$ffmpegPackageRoot=$null
if($RuntimePath){
  $ffmpeg=Find-ExeIn $RuntimePath
  if(-not$ffmpeg){throw "$script:Tag explicit runtime path contains no ffmpeg.exe: $RuntimePath"}
}
if(-not$ffmpeg){
  foreach($plugin in Get-PluginDirs){$candidate=Join-Path $plugin 'ffmpeg-runtime\ffmpeg.exe';if(Test-Path $candidate){$ffmpeg=$candidate;break}}
}
if(-not$ffmpeg){
  $git=(Get-Command git -ErrorAction SilentlyContinue)
  if($null -eq $git){throw "$script:Tag git.exe not found. RUN_4 needs Git to build the Bink2-capable ffmpeg application from sharpemu/ffmpeg-core."}

  $src=Join-Path $patches "SharpEmu_ffmpeg_core_$tag"
  $vcpkg=Join-Path $patches "SharpEmu_vcpkg_ffmpeg_core_$vcpkgCommit"
  Write-Tag "NO READY ffmpeg.exe FOUND; building the ffmpeg application from official sharpemu/ffmpeg-core source tag=$tag"
  Ensure-GitRepo 'https://github.com/sharpemu/ffmpeg-core.git' $src $tag
  $actual=(& git -C $src rev-parse HEAD).Trim()
  Write-Tag "FFMPEG-CORE SOURCE HEAD=$actual"

  Ensure-GitRepo 'https://github.com/microsoft/vcpkg.git' $vcpkg $vcpkgCommit
  Invoke-Native 'git' @('-C',$vcpkg,'reset','--hard',$vcpkgCommit) 'vcpkg reset'
  Invoke-Native 'git' @('-C',$vcpkg,'clean','-fd') 'vcpkg clean'

  $binkPatch=Join-Path $src 'bink2.patch';$ffmpegPatch=Join-Path $src 'ffmpeg.patch'
  if(-not(Test-Path $binkPatch)){throw "$script:Tag missing bink2.patch in ffmpeg-core source"}
  if(-not(Test-Path $ffmpegPatch)){throw "$script:Tag missing ffmpeg.patch in ffmpeg-core source"}
  Copy-Item -LiteralPath $binkPatch -Destination (Join-Path $vcpkg 'ports\ffmpeg\bink2.patch') -Force
  Push-Location $vcpkg
  try{
    & git apply --ignore-space-change --ignore-whitespace --3way $ffmpegPatch
    if($LASTEXITCODE -ne 0){throw "$script:Tag applying ffmpeg-core vcpkg patch failed exit=$LASTEXITCODE"}
  } finally {Pop-Location}

  $vcpkgExe=Join-Path $vcpkg 'vcpkg.exe'
  if(-not(Test-Path $vcpkgExe)){
    Write-Tag 'BOOTSTRAPPING vcpkg'
    $bootstrap=Join-Path $vcpkg 'bootstrap-vcpkg.bat'
    & $bootstrap -disableMetrics
    if($LASTEXITCODE -ne 0){throw "$script:Tag vcpkg bootstrap failed exit=$LASTEXITCODE"}
  }

  # sharpemu/ffmpeg-core CI builds libraries. The extra 'ffmpeg' feature below
  # deliberately builds the CLI application from the SAME patched source so the
  # native adapter can use it headlessly without RAD/radvideo64/bink2w64.
  $features="ffmpeg[avcodec,avfilter,avdevice,avformat,swresample,swscale,ffmpeg]:$triplet"
  Write-Tag "BUILDING BINK2-CAPABLE FFMPEG APP triplet=$triplet features=$features"
  & $vcpkgExe "--overlay-triplets=$src\triplets" install $features
  if($LASTEXITCODE -ne 0){throw "$script:Tag ffmpeg-core application build failed. A Windows C/C++ build toolchain compatible with the official clang-cl triplet is required."}

  $ffmpegPackageRoot=Join-Path $vcpkg "packages\ffmpeg_$triplet"
  $ffmpeg=Find-ExeIn $ffmpegPackageRoot
  if(-not$ffmpeg){
    # Some vcpkg revisions place tools under installed/<triplet>/tools.
    $ffmpeg=Find-ExeIn (Join-Path $vcpkg "installed\$triplet")
  }
  if(-not$ffmpeg){throw "$script:Tag build completed but ffmpeg.exe was not found in vcpkg package/install roots"}
}

Copy-FfmpegRuntime $ffmpeg $ffmpegPackageRoot

# Real one-frame Bink2 decoder probe when the user's Demon's Souls tree is present.
$probeMovie=$null
$roots=@([Environment]::GetEnvironmentVariable('SHARPEMU_APP0_DIR'),'F:\JOGOSPS5\PPSA01341')|Where-Object{$_ -and (Test-Path $_ -PathType Container)}
foreach($r in $roots){
  $probeItem=Get-ChildItem -LiteralPath $r -Recurse -File -Filter ps_studios_logo.bk2 -ErrorAction SilentlyContinue|Select-Object -First 1
  if($null -ne $probeItem){$probeMovie=$probeItem.FullName;break}
}
$pluginDirs=@(Get-PluginDirs)
$deployed=Join-Path $pluginDirs[0] 'ffmpeg-runtime\ffmpeg.exe'
if($probeMovie){
  Write-Tag "BINK2 PROBE movie=$probeMovie"
  & $deployed -hide_banner -loglevel error -nostdin -i $probeMovie -map 0:v:0 -frames:v 1 -f null NUL 2>&1 | ForEach-Object { Write-Host $_ }
  if($LASTEXITCODE -ne 0){throw "$script:Tag BINK2 VIDEO PROBE FAILED: custom decoder could not decode first frame"}
  Write-Tag 'BINK2 VIDEO PROBE PASSED first_frame=True'
}else{Write-Tag 'BINK2 PROBE SKIPPED ps_studios_logo.bk2 not found automatically; runtime deployment itself passed.'}
Write-Tag 'SETUP PASSED backend=sharpemu/ffmpeg-core headless=True external_rad=False proprietary_bink2w64=False'
