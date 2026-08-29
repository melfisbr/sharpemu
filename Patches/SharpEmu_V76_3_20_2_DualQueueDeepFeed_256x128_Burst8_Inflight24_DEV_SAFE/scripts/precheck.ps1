param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo

$t = [IO.File]::ReadAllText($CliPath)

$required = @(
        '[V76.3.20.1][EVENT_FIRST_WAIT]',
        '[V76.3.20.0][GLOBAL_RESIDENCY_CAPACITY]',
        '[V76.3.18.0][RPCS3_QUEUE_MERGE]',
        '[V76.3.17.1][COMPUTE_CHAIN4_BROAD_PROFILE]'
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
