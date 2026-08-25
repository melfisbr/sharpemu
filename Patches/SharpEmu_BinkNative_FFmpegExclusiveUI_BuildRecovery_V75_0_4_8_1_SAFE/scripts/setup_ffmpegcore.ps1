$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepositoryRoot
$patches=Get-PatchesRoot
Assert-FfmpegAbiMatch
$required=@('avcodec-61.dll','avformat-61.dll','avutil-59.dll','swscale-8.dll','swresample-5.dll')
$releasePlugins=Join-Path (Get-ReleaseRoot) 'plugins'
$debugPlugins=Join-Path (Get-DebugRoot) 'plugins'
New-Item -ItemType Directory -Path $releasePlugins -Force|Out-Null
New-Item -ItemType Directory -Path $debugPlugins -Force|Out-Null
$alreadyReady=$true
foreach($name in $required){
  $p=Join-Path $releasePlugins $name
  if(-not(Test-Path -LiteralPath $p -PathType Leaf) -or (Get-PeMachine $p) -ne 0x8664){$alreadyReady=$false;break}
}
if($alreadyReady){
  foreach($name in $required){
    $src=Join-Path $releasePlugins $name
    Copy-Item -LiteralPath $src -Destination (Join-Path $debugPlugins $name) -Force
    Write-Tag "READY $name sha=$(Get-Sha $src) machine=AMD64 source=existing-release-plugins"
  }
  Write-Tag 'FFMPEG-CORE RUNTIME ALREADY READY; no fetch target invocation was needed.'
  Write-Tag 'NEXT: RUN_5_DEMONS_FFMPEG_EXCLUSIVE_UI_TEST.cmd'
  exit 0
}

$project=Join-Path $repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
if(-not(Test-Path -LiteralPath $project -PathType Leaf)){throw "$script:Tag SharpEmu.CLI.csproj missing: $project"}
$projectText=[IO.File]::ReadAllText($project)
$tagMatch=[regex]::Match($projectText,'<FfmpegRuntimeTag>\s*([^<]+)\s*</FfmpegRuntimeTag>',[Text.RegularExpressions.RegexOptions]::IgnoreCase)
if(-not $tagMatch.Success){throw "$script:Tag local fork CLI project has no FfmpegRuntimeTag"}
$runtimeTag=$tagMatch.Groups[1].Value.Trim()
if($runtimeTag -ne '3b502d4'){throw "$script:Tag unexpected local FfmpegRuntimeTag=$runtimeTag expected=3b502d4"}
if(-not $projectText.Contains('FetchFfmpegRuntime')){throw "$script:Tag local fork CLI project has no FetchFfmpegRuntime target"}
if(-not $projectText.Contains('ffmpeg-windows-x64.zip')){throw "$script:Tag local fork CLI project has no win-x64 ffmpeg runtime package"}
if(-not $projectText.Contains('releases/download/$(FfmpegRuntimeTag)/$(FfmpegRuntimePackage)')){throw "$script:Tag local FetchFfmpegRuntime source template is unexpected; refusing alternate source"}
Write-Tag "LOCAL FORK FFMPEG TARGET runtime_tag=$runtimeTag project=$project"
Write-Tag 'Invoking only the existing local MSBuild FetchFfmpegRuntime target. No Git source operation touches your fork.'
$dotnet=(Get-Command dotnet -CommandType Application -ErrorAction Stop).Source
$fetchLog=Join-Path $patches ("SharpEmu_V75_0_4_8_1_FFMPEG_FETCH_"+(Get-Date -Format 'yyyyMMdd_HHmmss')+'.log')
& $dotnet msbuild $project '-t:FetchFfmpegRuntime' '-p:RuntimeIdentifier=win-x64' '-p:Configuration=Release' '-nologo' '-verbosity:minimal' 2>&1 | Tee-Object -FilePath $fetchLog
if($LASTEXITCODE -ne 0){throw "$script:Tag FetchFfmpegRuntime failed exit=$LASTEXITCODE log=$fetchLog"}
$projectDir=Split-Path -Parent $project
$searchRoots=New-Object System.Collections.Generic.List[string]
foreach($candidate in @((Join-Path $projectDir 'obj'),(Join-Path $repo 'artifacts\obj'),(Join-Path $repo 'obj'))){if(Test-Path -LiteralPath $candidate -PathType Container){$searchRoots.Add($candidate)}}
if($searchRoots.Count -eq 0){throw "$script:Tag FetchFfmpegRuntime completed but no intermediate obj root exists"}
$codecCandidates=New-Object System.Collections.Generic.List[System.IO.FileInfo]
foreach($searchRoot in $searchRoots){Get-ChildItem -LiteralPath $searchRoot -Recurse -File -Filter 'avcodec-61.dll' -ErrorAction SilentlyContinue|Where-Object{$_.FullName -match [regex]::Escape($runtimeTag) -and $_.FullName -match 'win-x64'}|ForEach-Object{$codecCandidates.Add($_)}}
if($codecCandidates.Count -eq 0){foreach($searchRoot in $searchRoots){Get-ChildItem -LiteralPath $searchRoot -Recurse -File -Filter 'avcodec-61.dll' -ErrorAction SilentlyContinue|ForEach-Object{$codecCandidates.Add($_)}}}
if($codecCandidates.Count -eq 0){throw "$script:Tag FetchFfmpegRuntime completed but avcodec-61.dll was not found"}
$codec=$codecCandidates|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 1
$runtimeBin=$codec.Directory.FullName
foreach($name in $required){$p=Join-Path $runtimeBin $name;if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw "$script:Tag extracted runtime missing $name"};if((Get-PeMachine $p)-ne 0x8664){throw "$script:Tag extracted runtime DLL is not AMD64: $p"}}
$runtimeDlls=@(Get-ChildItem -LiteralPath $runtimeBin -File -Filter '*.dll')
foreach($dll in $runtimeDlls){if((Get-PeMachine $dll.FullName)-ne 0x8664){throw "$script:Tag non-AMD64 runtime DLL: $($dll.FullName)"};Copy-Item $dll.FullName (Join-Path $releasePlugins $dll.Name) -Force;Copy-Item $dll.FullName (Join-Path $debugPlugins $dll.Name) -Force}
foreach($name in $required){$p=Join-Path $releasePlugins $name;Write-Tag "READY $name sha=$(Get-Sha $p) machine=AMD64"}
Write-Tag "FFMPEG-CORE RUNTIME READY source=$runtimeBin deployed_dlls=$($runtimeDlls.Count) runtime_tag=$runtimeTag"
Write-Tag "FETCH_LOG=$fetchLog"
Write-Tag 'NEXT: RUN_5_DEMONS_FFMPEG_EXCLUSIVE_UI_TEST.cmd'
