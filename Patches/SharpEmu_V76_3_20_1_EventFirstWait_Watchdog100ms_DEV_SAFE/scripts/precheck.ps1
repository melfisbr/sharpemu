param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo

$t = [IO.File]::ReadAllText($CliPath)

$required = @(
        '[V76.3.20.0][GLOBAL_RESIDENCY_CAPACITY]',
        '[V76.3.19.0][SHADER_FRONTEND_HOTSET_PROFILE]',
        '[V76.3.18.0][RPCS3_QUEUE_MERGE]'
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
