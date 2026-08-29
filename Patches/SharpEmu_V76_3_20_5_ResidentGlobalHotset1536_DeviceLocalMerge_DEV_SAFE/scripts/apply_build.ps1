param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo
& (Join-Path $PSScriptRoot 'precheck.ps1')

$files=@($CliRel,$PresenterRel)
$backup=New-Backup 'V76_3_20_5' $files

try {
    # Presenter: widen only the implementation clamp. Runtime profile stays lower.
    $pc=Read-Utf8Preserve $PresenterPath
    $pt=$pc.Text

    if(-not($pt -match '(?s)SHARPEMU_SHADER_GLOBAL_RESIDENCY_MAX_ENTRIES.*?64,\s*2048\s*\);')){
        $pattern='(?s)(SHARPEMU_SHADER_GLOBAL_RESIDENCY_MAX_ENTRIES"\s*,\s*\d+\s*\)\s*,\s*64\s*,\s*)1024(\s*\);)'
        $matches=[regex]::Matches($pt,$pattern)
        if($matches.Count -ne 1){
            Fail "residency clamp transform exige 1 match; encontrados=$($matches.Count)"
        }
        $pt=[regex]::Replace($pt,$pattern,'${1}2048${2}',1)
        Write-Utf8Preserve $PresenterPath $pt $pc.HasBom
    }

    $verify=[IO.File]::ReadAllText($PresenterPath)
    if(-not($verify -match '(?s)SHARPEMU_SHADER_GLOBAL_RESIDENCY_MAX_ENTRIES.*?64,\s*2048\s*\);')){
        Fail 'residency clamp 2048 nao confirmado'
    }

    # CLI: 1536 entries is intentionally below the new 2048 implementation cap.
    $c=Read-Utf8Preserve $CliPath
    $t=$c.Text
    $block=@'
        // V76.3.20.5 - expand only the proven immutable DEVICE_LOCAL hotset.
        // V20.0 saturated 1024 entries at ~371.6 MiB with zero budget fallback.
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY", "1");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MAX_ENTRIES", "1536");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MB", "512");
        Set("SHARPEMU_VK_HOST_BUFFER_CACHE_MB", "256");
        Set("SHARPEMU_VK_DEVICE_BUFFER_CACHE_MB", "1024");
        Set("SHARPEMU_GPU_RESIDENT_SHADER_MAX_V1180", "2048");
        Set("SHARPEMU_DESCRIPTOR_SET_CACHE_MAX_SETS_V11716", "4096");

        // Preserve V19 admission thresholds; do not make one-off globals resident.
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_HOT_ADMIT", "1");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_ADMIT_OBSERVATIONS", "3");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MEDIUM_KB", "256");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_MEDIUM_ADMIT_OBSERVATIONS", "2");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_LARGE_KB", "1024");
        Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY_LARGE_ADMIT_OBSERVATIONS", "2");

        Console.Error.WriteLine(
            "[V76.3.20.5][RESIDENT_GLOBAL_HOTSET1536] " +
            "entries=1536 resident_mb=512 host_pool_mb=256 device_pool_mb=1024 " +
            "resident_shader=2048 descriptor_sets=4096 admission=V19 " +
            "queue=192/96 burst=4 inflight=16 dual_physical=1 V20.4=preserved");
'@
    $t=Insert-FinalApplyBlock $t $block '[V76.3.20.5][RESIDENT_GLOBAL_HOTSET1536]'
    Write-Utf8Preserve $CliPath $t $c.HasBom

    if(-not([IO.File]::ReadAllText($CliPath).Contains('[V76.3.20.5][RESIDENT_GLOBAL_HOTSET1536]'))){
        Fail 'V20.5 marker ausente apos apply'
    }

    $buildLog=Build-Debug $backup.Stamp 'V76_3_20_5'
    Write-Host "[$Tag] APPLY+BUILD PASSED configuration=Debug"
    Write-Host "[$Tag] presenter_sha256=$(Get-HashLower $PresenterPath)"
    Write-Host "[$Tag] cli_sha256=$(Get-HashLower $CliPath)"
    Write-Host "[$Tag] backup=$($backup.Zip)"
    Write-Host "[$Tag] build_log=$buildLog"
}
catch {
    Restore-Backup $backup $files
    Write-Host "[$Tag] rollback=completed backup=$($backup.Zip)" -ForegroundColor Yellow
    throw
}
finally {
    if(Test-Path $backup.Root){Remove-Item $backup.Root -Recurse -Force -ErrorAction SilentlyContinue}
}
