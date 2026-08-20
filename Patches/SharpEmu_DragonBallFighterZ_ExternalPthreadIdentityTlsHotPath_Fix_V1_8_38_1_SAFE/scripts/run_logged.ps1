param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('Validate','Precheck','ApplyBuild','PostAudit','Diagnostic')]
    [string]$Mode,
    [int]$Seconds=240
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$patches=Get-PatchesRoot
$logName = switch($Mode) {
    'Validate'    { 'DBFZ_V1_8_38_1_RUN1_VALIDATE.log' }
    'Precheck'    { 'DBFZ_V1_8_38_1_RUN2_PRECHECK.log' }
    'ApplyBuild'  { 'DBFZ_V1_8_38_1_RUN3_APPLY_BUILD.log' }
    'PostAudit'   { 'DBFZ_V1_8_38_1_RUN4_POST_AUDIT.log' }
    'Diagnostic'  { 'DBFZ_V1_8_38_1_RUN5_DIAGNOSTIC.log' }
}
$logPath=Join-Path $patches $logName
$header=@(
    ('='*78),
    ('UTC='+[DateTime]::UtcNow.ToString('o')),
    ('Mode='+$Mode),
    ('Package=DBFZ External Pthread Identity/TLS V1.8.38.1'),
    ('Log='+$logPath),
    ('='*78)
)
$header | Set-Content -LiteralPath $logPath -Encoding utf8

function Write-V18381LoggedOutput {
    param([Parameter(ValueFromPipeline=$true)]$InputObject)
    process {
        $rendered=@($InputObject | Out-String -Stream)
        foreach($line in $rendered) {
            Write-Host $line
            Add-Content -LiteralPath $logPath -Value $line -Encoding utf8
        }
    }
}

$target = switch($Mode) {
    'Validate'   { Join-Path $PSScriptRoot 'validate.ps1' }
    'Precheck'   { Join-Path $PSScriptRoot 'precheck.ps1' }
    'ApplyBuild' { Join-Path $PSScriptRoot 'apply_build.ps1' }
    'PostAudit'  { Join-Path $PSScriptRoot 'post_audit.ps1' }
    'Diagnostic' { Join-Path $PSScriptRoot 'diagnostic.ps1' }
}

try {
    if($Mode -eq 'Diagnostic') {
        & $target -Seconds $Seconds -NoTranscript *>&1 | Write-V18381LoggedOutput
    } else {
        & $target -NoTranscript *>&1 | Write-V18381LoggedOutput
    }
    $done="[DBFZ-CPU-1838.1] RunLog=$logPath"
    Write-Host $done
    Add-Content -LiteralPath $logPath -Value $done -Encoding utf8
    exit 0
}
catch {
    $detail=@($_ | Format-List * -Force | Out-String -Stream)
    foreach($line in $detail) {
        Write-Host $line
        Add-Content -LiteralPath $logPath -Value $line -Encoding utf8
    }
    $failed="[DBFZ-CPU-1838.1] FAILED Mode=$Mode"
    $where="[DBFZ-CPU-1838.1] RunLog=$logPath"
    Write-Host $failed
    Write-Host $where
    Add-Content -LiteralPath $logPath -Value $failed -Encoding utf8
    Add-Content -LiteralPath $logPath -Value $where -Encoding utf8
    exit 1
}
