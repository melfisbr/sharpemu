Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")
try {
    if (-not (Test-Path -LiteralPath $script:TargetV1Root -PathType Container)) { throw "Pacote funcional V76.2.4.1 ausente: $script:TargetV1Root" }
    if (-not (Test-Path -LiteralPath (Join-Path $script:TargetV1Root 'scripts\patch_target.ps1') -PathType Leaf)) { throw "patch_target.ps1 da V76.2.4.1 ausente" }
    $guardScript = Get-TargetGuardScript
    Assert-PowerShellParses $guardScript
    $state = Get-ContainmentState $guardScript
    if ($state -eq 'Divergent') { throw "Guard da V76.2.4.6 divergente: $guardScript" }
    $msg = "TargetV6=$script:TargetV6Root GuardScript=$guardScript GuardState=$state TargetV1=$script:TargetV1Root"
    [IO.File]::WriteAllText($script:ResultSummary, $msg + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    Write-Tag $msg
    Write-Tag "PRECHECK PASSED. Context=$script:ResultSummary"
} catch {
    [IO.File]::WriteAllText($script:ResultSummary, $_.Exception.ToString(), [Text.UTF8Encoding]::new($false))
    throw "PRECHECK FAILED: $($_.Exception.Message) Context=$script:ResultSummary"
}
