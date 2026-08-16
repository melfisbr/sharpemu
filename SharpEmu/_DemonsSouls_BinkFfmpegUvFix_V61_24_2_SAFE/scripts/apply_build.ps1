param([string]$RepositoryRoot)
. (Join-Path $PSScriptRoot 'common.ps1')
$r=Resolve-Repo $RepositoryRoot
& (Join-Path $PSScriptRoot 'precheck.ps1') -RepositoryRoot $r

$t=Join-Path $r 'src\SharpEmu.Libs\Media\NihavBink2Decoder.cs'
$s=[IO.File]::ReadAllText($t)
if($s.IndexOf('V61.24.2 FFMPEG_UV_SWAP',[StringComparison]::Ordinal)-lt 0){
    $old=@'
        // The reusable repacked buffer is true I420/YUV420P, so both native
        // swscale and the LUT fallback now consume the same correct planes.
        if (!TryConvertYuvViaFfmpeg(
                _pgmPlanarBuffer!,
                0,
                requiredPayload,
                destination))
        {
            ConvertYuv420ToBgra(
                yPlane,
                uPlane,
                vPlane,
                visibleWidth,
                visibleHeight,
                chromaWidth,
                destination,
                useFullRange);

            TryRepairGreenFallback(
                yPlane,
                uPlane,
                vPlane,
                visibleWidth,
                visibleHeight,
                chromaWidth,
                destination,
                useFullRange);
        }
'@
    $new=@'
        // [V61.24.2 FFMPEG_UV_SWAP]
        // _swapUv used to affect only the LUT fallback because FFmpeg consumed
        // _pgmPlanarBuffer directly. That made SHARPEMU_NIHAV_UV_SWAP a no-op
        // whenever the persistent swscale converter was active. Swap the two
        // contiguous chroma planes around the FFmpeg call, then restore them so
        // the existing LUT fallback continues to see the original buffer.
        var ffmpegSwapUv = string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_BINK_FFMPEG_UV_SWAP"),
            "1",
            StringComparison.Ordinal);

        var ffmpegConverted = false;
        if (ffmpegSwapUv)
        {
            SwapEqualPlanes(planarU, planarV);
        }

        try
        {
            ffmpegConverted = TryConvertYuvViaFfmpeg(
                _pgmPlanarBuffer!,
                0,
                requiredPayload,
                destination);
        }
        finally
        {
            if (ffmpegSwapUv)
            {
                SwapEqualPlanes(planarU, planarV);
            }
        }

        if (!ffmpegConverted)
        {
            ConvertYuv420ToBgra(
                yPlane,
                uPlane,
                vPlane,
                visibleWidth,
                visibleHeight,
                chromaWidth,
                destination,
                useFullRange);

            TryRepairGreenFallback(
                yPlane,
                uPlane,
                vPlane,
                visibleWidth,
                visibleHeight,
                chromaWidth,
                destination,
                useFullRange);
        }
'@
    if($s.IndexOf($old,[StringComparison]::Ordinal)-lt 0){
        throw 'APPLY ERROR: exact FFmpeg conversion block not found.'
    }
    $s=$s.Replace($old,$new)

    $methodAnchor='    private bool TryConvertYuvViaFfmpeg('
    $helper=@'
    private static void SwapEqualPlanes(Span<byte> first, Span<byte> second)
    {
        if (first.Length != second.Length)
        {
            throw new ArgumentException("Chroma plane lengths must match.");
        }

        for (var index = 0; index < first.Length; index++)
        {
            (first[index], second[index]) = (second[index], first[index]);
        }
    }

'@
    $pos=$s.IndexOf($methodAnchor,[StringComparison]::Ordinal)
    if($pos-lt 0){throw 'APPLY ERROR: TryConvertYuvViaFfmpeg anchor missing.'}
    $s=$s.Insert($pos,$helper)

    $stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupDir=Join-Path $r ".sharpemu-hotfix-backup\BinkFfmpegUv_V61_24_2_$stamp"
    New-Item -ItemType Directory -Force -Path $backupDir|Out-Null
    $backup=Join-Path $backupDir 'NihavBink2Decoder.cs'
    Copy-Item -LiteralPath $t -Destination $backup
    [IO.File]::WriteAllText($t,$s,[Text.UTF8Encoding]::new($false))
    Write-Host "[V61.24.2] Source patched. Backup: $backupDir"
}else{
    Write-Host '[V61.24.2] Source already patched.'
    $backup=$null
}

try{
    Push-Location $r
    try{
        & dotnet build '.\src\SharpEmu.Libs\SharpEmu.Libs.csproj' -c Debug --nologo
        if($LASTEXITCODE-ne 0){throw "SharpEmu.Libs build failed: $LASTEXITCODE"}
        & dotnet build '.\src\SharpEmu.CLI\SharpEmu.CLI.csproj' -c Debug -r win-x64 --nologo
        if($LASTEXITCODE-ne 0){throw "SharpEmu.CLI build failed: $LASTEXITCODE"}
    }finally{Pop-Location}
}catch{
    if($null-ne $backup -and (Test-Path -LiteralPath $backup)){
        Copy-Item -LiteralPath $backup -Destination $t -Force
        Write-Host '[V61.24.2] Build failed; source restored.' -ForegroundColor Yellow
    }
    throw
}
Write-Host '[V61.24.2] SUCCESS'
Write-Host '[V61.24.2] FFmpeg path now honors an explicit U/V plane swap.'
