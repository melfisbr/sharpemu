Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'..'))

$scriptFiles=@(
    Get-ChildItem -LiteralPath ([IO.Path]::Combine($root,'scripts')) `
        -File `
        -Filter '*.ps1'
)

foreach($scriptFile in $scriptFiles){
    $tokens=$null
    $errors=$null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $scriptFile.FullName,
        [ref]$tokens,
        [ref]$errors
    ) | Out-Null

    if($errors.Count -gt 0){
        $detail=@(
            $errors | ForEach-Object {
                "line=$($_.Extent.StartLineNumber) col=$($_.Extent.StartColumnNumber) $($_.Message)"
            }
        ) -join ' | '
        throw "PowerShell parse failed: $($scriptFile.Name): $detail"
    }
}

Write-Host "[V73.0.20.4] PACKAGE VALIDATION PASSED ($($scriptFiles.Count) PowerShell scripts parsed)." -ForegroundColor Green
Write-Host '[V73.0.20.4] READ-ONLY SOURCE CAPTURE: this package does not modify SharpEmu.' -ForegroundColor Cyan
