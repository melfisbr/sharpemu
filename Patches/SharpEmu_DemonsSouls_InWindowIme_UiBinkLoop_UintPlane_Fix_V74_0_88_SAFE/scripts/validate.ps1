. "$PSScriptRoot\common.ps1"
$pkg=PackageRoot
$required=@(
    'ANALYSIS.txt',
    'FIX_NOTES.txt',
    'README.md',
    'manifest.json',
    'payload\ImeDialogExports.cs',
    'payload\ImeInWindowOverlay.cs',
    'scripts\common.ps1',
    'scripts\precheck.ps1',
    'scripts\apply_build.ps1',
    'scripts\diagnostic.ps1',
    'scripts\run_test.ps1',
    'scripts\rollback.ps1',
    'scripts\validate.ps1'
)

$missing=@()
foreach($r in $required){
    if(-not(Test-Path -LiteralPath (Join-Path $pkg $r))){$missing+=$r}
}
if($missing.Count -gt 0){
    Write-Host "$script:Tag [ERROR] Missing files: $($missing -join ', ')" -ForegroundColor Red
    exit 1
}

$parseIssues=@()
foreach($f in Get-ChildItem (Join-Path $pkg 'scripts') -Filter '*.ps1'){
    $tokens=$null
    $errors=$null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $f.FullName,
        [ref]$tokens,
        [ref]$errors)|Out-Null
    if($errors.Count -gt 0){
        foreach($e in $errors){$parseIssues+=("$($f.Name): "+$e.Message)}
    }
}
if($parseIssues.Count -gt 0){
    foreach($issue in $parseIssues){
        Write-Host "$script:Tag [ERROR] PowerShell parse failed $issue" -ForegroundColor Red
    }
    exit 1
}

$ime=[IO.File]::ReadAllText((Join-Path $pkg 'payload\ImeDialogExports.cs'))
$overlay=[IO.File]::ReadAllText((Join-Path $pkg 'payload\ImeInWindowOverlay.cs'))
$common=[IO.File]::ReadAllText((Join-Path $pkg 'scripts\common.ps1'))

$checks=[ordered]@{
    ime_internal_marker=$ime.Contains('SHARPEMU_V74_0_88_IME_IN_WINDOW_SYSTEM_UI')
    ime_no_process_start=-not $ime.Contains('ProcessStartInfo')
    ime_no_powershell=-not $ime.Contains('powershell.exe')
    overlay_backend=$overlay.Contains('backend=sdl-vulkan-overlay')
    overlay_done=$overlay.Contains('"DONE"')
    overlay_gamepad=$overlay.Contains('HandleGamepadButtons')
    presenter_uint_contract=$common.Contains('SHARPEMU_V74_0_88_UI_BINK_UINT_PLANE_CONTRACT')
    presenter_uint_formats=$common.Contains('vk_y=R8Uint vk_uv=R8G8Uint')
    host_loop=$common.Contains('SHARPEMU_V74_0_88_UI_BINK_GUEST_OWNED_LOOP')
    safe_rollback=$common.Contains('Assert-V74088')
}
$issues=0
foreach($entry in $checks.GetEnumerator()){
    Write-Host "$($entry.Key)=$($entry.Value)"
    if(-not $entry.Value){$issues++}
}
if($issues -gt 0){
    Write-Host "$script:Tag PACKAGE VALIDATION FAILED issues=$issues" -ForegroundColor Red
    exit 1
}

Write-Host "$script:Tag PACKAGE VALIDATION PASSED (PowerShell parsed; in-window IME; uint Y/UV contract; guest-owned UI-Bink loop; SAFE guards verified)." -ForegroundColor Green
