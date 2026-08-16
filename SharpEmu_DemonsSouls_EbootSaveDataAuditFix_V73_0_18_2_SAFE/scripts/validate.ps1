Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'..'))

# V73.0.18.2: syntax-gate every PowerShell script before PRECHECK/APPLY.
$scriptFiles=@(
    Get-ChildItem -LiteralPath ([IO.Path]::Combine($root,'scripts')) `
        -File `
        -Filter '*.ps1'
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
            $parseErrors |
                ForEach-Object {
                    "line=$($_.Extent.StartLineNumber) col=$($_.Extent.StartColumnNumber) $($_.Message)"
                }
        ) -join ' | '
        throw "PowerShell parse failed for $($scriptFile.Name): $messages"
    }
}
Write-Host "[V73.0.18.2] PowerShell syntax validation passed ($($scriptFiles.Count) scripts)." -ForegroundColor Green


$files=@(
    'scripts\patch_savedata.ps1',
    'scripts\precheck.ps1',
    'scripts\apply_build.ps1',
    'scripts\diagnostic.ps1'
)

foreach($rel in $files){
    $p=[IO.Path]::Combine($root,$rel)
    if(-not [IO.File]::Exists($p)){throw "Arquivo do pacote ausente: $rel"}
}

$p=[IO.File]::ReadAllText([IO.Path]::Combine($root,'scripts\patch_savedata.ps1'))
foreach($m in @(
    'SHARPEMU_DEMONSSOULS_EBOOT_SAVEDATA_BLOCK_64K_V73_0_18',
    'Nid = "z1JA8-iJt3k"',
    'ExportName = "sceSaveDataBackup"',
    'SHARPEMU_DEMONSSOULS_EBOOT_SAVEDATA_PREPARE_RSI_V73_0_18',
    'prepareAddress = ctx[CpuRegister.Rsi]'
)){
    if(-not $p.Contains($m)){throw "Patch marker ausente: $m"}
}

Write-Host '[V73.0.18.2] PACKAGE VALIDATION PASSED: structural patcher intacto.' -ForegroundColor Green
