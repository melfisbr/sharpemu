param([string]$RepositoryRoot)
. (Join-Path $PSScriptRoot 'common.ps1')
$r=Repo $RepositoryRoot
$media=Join-Path $r 'src\SharpEmu.Libs\Media\NihavBink2Decoder.cs'
$ajm=Join-Path $r 'src\SharpEmu.Libs\Audio\AjmExports.cs'
$bridge=Join-Path $r 'src\SharpEmu.Libs\Media\HostMovieBridge.cs'
foreach($p in @($media,$ajm,$bridge)){if(!(Test-Path -LiteralPath $p -PathType Leaf)){throw "PRECHECK ERROR: missing $p"}}
$m=[IO.File]::ReadAllText($media)
if($m.IndexOf('SHARPEMU_BINK_FFMPEG_COLOR',[StringComparison]::Ordinal)-lt 0){throw 'PRECHECK ERROR: current FFmpeg color-converter path missing.'}
if($m.IndexOf('SHARPEMU_NIHAV_UV_SWAP',[StringComparison]::Ordinal)-lt 0){throw 'PRECHECK ERROR: current UV control missing.'}
$a=[IO.File]::ReadAllText($ajm)
if($a.IndexOf('SHARPEMU_LOG_AJM',[StringComparison]::Ordinal)-lt 0){throw 'PRECHECK ERROR: AJM trace control missing.'}
Write-Host '[V61.24.1] PRECHECK PASSED.'
Write-Host '[V61.24.1] V61.24.0.1 proved PS Studios playback reaches frame 254/255.'
Write-Host '[V61.24.1] Color correction will use the existing FFmpeg swscale path; AJM route tracing enabled.'
