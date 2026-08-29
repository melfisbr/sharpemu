param()
. (Join-Path $PSScriptRoot 'common.ps1')

foreach($f in @('common.ps1','precheck.ps1','apply_build.ps1','diagnostic.ps1','rollback.ps1')) {
    $p=Join-Path $PSScriptRoot $f
    if(-not(Test-Path -LiteralPath $p -PathType Leaf)){Fail "script ausente: $f"}
}

$bad = Select-String `
    -Path ((Get-ChildItem $PSScriptRoot -Filter '*.ps1' -File |
        Where-Object {$_.Name -ne 'validate.ps1'}).FullName) `
    -Pattern @('Invoke-WebRequest','Invoke-RestMethod','Start-BitsTransfer','curl.exe','wget.exe') `
    -SimpleMatch -ErrorAction SilentlyContinue
if($bad){Fail 'downloader direto proibido'}

Write-Host "[$Tag] VALIDATE PASSED mode=adaptive-final-policy changed_source=CLI-only"
