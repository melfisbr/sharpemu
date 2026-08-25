$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepositoryRoot;$patches=Get-PatchesRoot
Assert-FfmpegAbiMatch
$project=Join-Path $repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
if(-not(Test-Path -LiteralPath $project -PathType Leaf)){throw "$script:Tag SharpEmu.CLI.csproj missing: $project"}
$projectText=[IO.File]::ReadAllText($project)
$tagMatch=[regex]::Match($projectText,'<FfmpegRuntimeTag>\s*([^<]+)\s*</FfmpegRuntimeTag>',[Text.RegularExpressions.RegexOptions]::IgnoreCase)
if(-not$tagMatch.Success){throw "$script:Tag local fork CLI project has no FfmpegRuntimeTag; refusing to invent an external runtime source"}
$runtimeTag=$tagMatch.Groups[1].Value.Trim()
if(-not$projectText.Contains('FetchFfmpegRuntime')){throw "$script:Tag local fork CLI project has no FetchFfmpegRuntime target"}
if(-not$projectText.Contains('ffmpeg-windows-x64.zip')){throw "$script:Tag local fork CLI project has no win-x64 ffmpeg runtime package"}
Write-Tag "LOCAL FORK FFMPEG TARGET runtime_tag=$runtimeTag project=$project"
Write-Tag 'No Git command is used. Runtime acquisition, if needed, is performed only by the existing MSBuild target in your fork.'
$releasePlugins=Join-Path (Get-ReleaseRoot) 'plugins';$debugPlugins=Join-Path (Get-DebugRoot) 'plugins'
$required=@('avcodec-61.dll','avformat-61.dll','avutil-59.dll','swscale-8.dll','swresample-5.dll')
$missing=@($required|Where-Object{-not(Test-Path -LiteralPath (Join-Path $releasePlugins $_) -PathType Leaf)})
if($missing.Count -gt 0){
    Write-Tag "Runtime missing after previous build: $($missing -join ', '). Rebuilding LOCAL SharpEmu.CLI so its pinned FetchFfmpegRuntime target can populate plugins."
    $dotnet=(Get-Command dotnet -CommandType Application -ErrorAction Stop).Source
    $log=Join-Path $patches ("SharpEmu_V75_0_4_5_FFMPEG_RUNTIME_BUILD_"+(Get-Date -Format 'yyyyMMdd_HHmmss')+'.log')
    & $dotnet build $project -c Release -r win-x64 2>&1|Tee-Object -FilePath $log
    if($LASTEXITCODE -ne 0){throw "$script:Tag local CLI runtime build failed exit=$LASTEXITCODE log=$log"}
}
foreach($name in $required){$p=Join-Path $releasePlugins $name;if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw "$script:Tag local fork build did not provide required ffmpeg runtime DLL: $name"};if((Get-PeMachine $p)-ne 0x8664){throw "$script:Tag runtime DLL is not AMD64: $name"}}
New-Item -ItemType Directory -Path $debugPlugins -Force|Out-Null
# Sync the complete native runtime dependency set, not only the five top-level FFmpeg DLLs.
$runtimeExtract=Join-Path (Split-Path -Parent $project) ("obj\ffmpeg-runtime\$runtimeTag\win-x64\extracted\bin")
if(Test-Path -LiteralPath $runtimeExtract -PathType Container){
    $runtimeDlls=@(Get-ChildItem -LiteralPath $runtimeExtract -File -Filter '*.dll')
    foreach($dll in $runtimeDlls){Copy-Item -LiteralPath $dll.FullName -Destination (Join-Path $releasePlugins $dll.Name) -Force;Copy-Item -LiteralPath $dll.FullName -Destination (Join-Path $debugPlugins $dll.Name) -Force}
    Write-Tag "SYNC complete runtime DLLs=$($runtimeDlls.Count) source=$runtimeExtract"
}else{
    $runtimeDlls=@(Get-ChildItem -LiteralPath $releasePlugins -File -Filter '*.dll')
    foreach($dll in $runtimeDlls){Copy-Item -LiteralPath $dll.FullName -Destination (Join-Path $debugPlugins $dll.Name) -Force}
    Write-Tag "SYNC fallback from Release plugins DLLs=$($runtimeDlls.Count)"
}
foreach($name in $required){$p=Join-Path $releasePlugins $name;Write-Tag "READY $name sha=$(Get-Sha $p) machine=AMD64"}
Write-Tag "FFMPEG-CORE RUNTIME READY root=$releasePlugins runtime_tag=$runtimeTag source=local-fork-msbuild-target"
Write-Tag 'NEXT: RUN_5_DEMONS_FFMPEG_NATIVE_AV_TEST.cmd'
