param()
. (Join-Path $PSScriptRoot 'common.ps1')

Ensure-Layout

Write-Host "[$Tag] launching original V21.0 diagnostic"

Push-Location $OriginalPkg
try {
    & (Join-Path $OriginalPkg 'RUN_4_DIAGNOSTIC.cmd')
    if ($LASTEXITCODE -ne 0) {
        Fail "V21.0 original RUN_4 falhou exit=$LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

Write-Host "[$Tag] DIAGNOSTIC COMPLETE via=original-V21.0"
