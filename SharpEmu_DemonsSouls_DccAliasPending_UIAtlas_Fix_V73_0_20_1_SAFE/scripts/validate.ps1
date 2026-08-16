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

$patch=[IO.File]::ReadAllText(
    [IO.Path]::Combine($root,'scripts\patch_v73020.ps1'))

foreach($marker in @(
    'SHARPEMU_DEMONSSOULS_LARGE_SPARSE_PROBE_V73_0_20_1',
    'SHARPEMU_DEMONSSOULS_DCC_PENDING_ALIAS_V73_0_20_1',
    '[V73.0.20.1][LARGE_PROBE_SEEDED]',
    '[V73.0.20.1][DCC_ALIAS_PENDING]',
    'foundResident',
    'resolvedDccAlias'
)){
    if(-not $patch.Contains($marker)){
        throw "Patch payload marker missing: $marker"
    }
}

Write-Host "[V73.0.20.1] PACKAGE VALIDATION PASSED ($($scriptFiles.Count) PowerShell scripts parsed)." -ForegroundColor Green
