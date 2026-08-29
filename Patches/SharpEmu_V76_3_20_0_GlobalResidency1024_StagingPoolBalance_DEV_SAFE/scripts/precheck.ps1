param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo

$t = [IO.File]::ReadAllText($CliPath)

$required = @(
        '[V76.3.19.0][SHADER_FRONTEND_HOTSET_PROFILE]',
        '[V76.3.18.0][RPCS3_QUEUE_MERGE]',
        '[V76.3.17.0.1][ASYNC_AGC_CP_ADAPTIVE]',
        'Set("SHARPEMU_SHADER_GLOBAL_RESIDENCY", "1");'
)
foreach ($m in $required) {
    if (-not $t.Contains($m)) {
        Fail "baseline marker/setting ausente: $m"
    }
}

$dotnet = (Get-Command dotnet.exe -ErrorAction SilentlyContinue).Source
if (-not $dotnet) {
    $dotnet = (Get-Command dotnet -ErrorAction SilentlyContinue).Source
}
if (-not $dotnet) {
    Fail 'dotnet nao encontrado no PATH'
}

Write-Host "[$Tag] PRECHECK PASSED cli_sha256=$(Get-HashLower $CliPath)"
