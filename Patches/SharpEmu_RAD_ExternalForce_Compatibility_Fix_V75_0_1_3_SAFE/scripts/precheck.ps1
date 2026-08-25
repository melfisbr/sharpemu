param()
. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'validate_package.ps1')
$s=Assert-CompatibilityBaseline

$patches=Get-PatchesRoot
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$tmp=Join-Path ([IO.Path]::GetTempPath()) ("SharpEmu_V75013_"+[Guid]::NewGuid().ToString('N')+'.cs')
try{
    $r=Invoke-HostPatch $s.Host $tmp
    $patchedText=[IO.File]::ReadAllText($tmp)
    if($patchedText.Contains('requested=rad resolved=native-rad')){
        throw "$script:Tag native RAD auto-select remains after preview patch"
    }
    foreach($marker in @(
        'SHARPEMU_V75_0_1_3_EXTERNAL_RAD_COMPATIBILITY_FORCE',
        'SHARPEMU_V75_0_1_3_NATIVE_RAD_CASE_EXTERNALIZED',
        'return MovieMode.Rad;')){
        if(-not$patchedText.Contains($marker)){throw "$script:Tag postcondition missing: $marker"}
    }

    Write-Tag "preflight_HostMovie_would_apply=$($r.Applied) already=$($r.Already) source_write=0 preview_sha=$($r.After)"
    $report=Join-Path $patches "SharpEmu_V75_0_1_3_RAD_EXTERNAL_PRECHECK_$stamp.txt"
    @(
        "version=$script:Version",
        "host_before=$($s.HostSha)",
        "host_preview_after=$($r.After)",
        "playback_preserved=$($s.PlaybackSha)",
        "abi_preserved=$($s.AbiSha)",
        "decoder_preserved=$($s.DecoderSha)",
        "media_frame_pixel_layout=$($s.HasPixelLayout)",
        "media_frame_pixel_layout_source=$($s.HasPixelLayoutSource)",
        "v74_0_105_direct_yuv=$($s.HasV74105)",
        "v74_0_110_reservoir=$($s.HasV74110)",
        'strategy=disable only V75 native selection; do not restore old playback/source',
        'runtime=official external RAD',
        'native managed sources=compile-only retained',
        'native plugin dll=removed'
    )|Set-Content -LiteralPath $report -Encoding UTF8
    Write-Tag "PRECHECK=$report"
    Write-Tag 'PRECHECK PASSED. Nothing changed.'
}finally{
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}
