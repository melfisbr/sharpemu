Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'..'))

$scriptFiles=@(
    Get-ChildItem -LiteralPath ([IO.Path]::Combine($root,'scripts')) `
        -File -Filter '*.ps1'
)
foreach($scriptFile in $scriptFiles){
    $tokens=$null
    $parseErrors=$null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $scriptFile.FullName,
        [ref]$tokens,
        [ref]$parseErrors
    ) | Out-Null
    if($parseErrors.Count -gt 0){
        $messages=@(
            $parseErrors | ForEach-Object {
                "line=$($_.Extent.StartLineNumber) col=$($_.Extent.StartColumnNumber) $($_.Message)"
            }
        ) -join ' | '
        throw "PowerShell parse failed for $($scriptFile.Name): $messages"
    }
}

$patcher=[IO.File]::ReadAllText(
    [IO.Path]::Combine($root,'scripts\patch_ui_textures.ps1')
)
foreach($marker in @(
    'SHARPEMU_DEMONSSOULS_UI_TEXTURE_CACHE_COHERENCY_V73_0_19',
    '[V73.0.19.1][TEXTURE_CACHE_STALE]',
    '[V73.0.19.1][TEXTURE_CACHE_REFRESH]',
    'SHARPEMU_DEMONSSOULS_UI_TEXTURE_CACHE_REFRESH_STRUCTURAL_V73_0_19_1',
    'SHARPEMU_DEMONSSOULS_UI_GUEST_IMAGE_PROBE_SEED_V73_0_19_1',
    'SHARPEMU_DEMONSSOULS_UI_RT_ALIAS_READ_V73_0_19',
    'TryReadGuestTextureBacking'
)){
    if(-not $patcher.Contains($marker)){throw "Package marker missing: $marker"}
}

Write-Host "[V73.0.19.1] PACKAGE VALIDATION PASSED ($($scriptFiles.Count) PowerShell scripts parsed)." -ForegroundColor Green
