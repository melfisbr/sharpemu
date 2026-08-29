param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo

$cli=[IO.File]::ReadAllText($CliPath)
if(-not$cli.Contains('[V76.3.20.4][WATCHED_WRITE_PRODUCER_FASTPATH]')){
    Fail 'V20.4 marker ausente; execute os pacotes em ordem'
}

$p=[IO.File]::ReadAllText($PresenterPath)
$has1024 = $p -match '(?s)SHARPEMU_SHADER_GLOBAL_RESIDENCY_MAX_ENTRIES.*?64,\s*1024\s*\);'
$has2048 = $p -match '(?s)SHARPEMU_SHADER_GLOBAL_RESIDENCY_MAX_ENTRIES.*?64,\s*2048\s*\);'
if(-not$has1024 -and -not$has2048){
    Fail 'clamp de shader global residency nao reconhecido'
}

foreach($m in @(
 'SHARPEMU_SHADER_GLOBAL_RESIDENCY',
 'SHARPEMU_VK_DEVICE_BUFFER_CACHE_MB',
 'ResidentReadOnlyGlobal'
)){
    if(-not$p.Contains($m)){Fail "Presenter residency contract ausente: $m"}
}

$clampState = if ($has2048) { 'already-2048' } else { '1024->2048' }
Write-Host "[$Tag] PRECHECK PASSED clamp=$clampState profile=1536/512MB"
