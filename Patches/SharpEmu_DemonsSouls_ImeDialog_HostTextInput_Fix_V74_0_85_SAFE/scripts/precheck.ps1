. "$PSScriptRoot\common.ps1"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'validate.ps1')
if($LASTEXITCODE -ne 0){ exit $LASTEXITCODE }
$src=ImeDialogSource; $ime=ImeExportsSource; $proj=CliProject
foreach($p in @($src,$ime,$proj)){ if(-not(Test-Path -LiteralPath $p -PathType Leaf)){ Write-Host "[V74.0.85][ERROR] missing source: $p" -ForegroundColor Red; exit 1 } }
$text=[IO.File]::ReadAllText($src)
if($text.Contains('SHARPEMU_V74_0_85_IME_DIALOG_HOST_TEXT_INPUT')){
    Write-Host '[V74.0.85] PRECHECK: patch already installed.' -ForegroundColor Yellow
    Write-Host "ImeDialogSHA256=$(Sha $src)"
    exit 10
}
$issues=0
foreach($m in @('public static class ImeDialogExports','ExportName = "sceImeDialogInit"','ExportName = "sceImeDialogGetStatus"','ExportName = "sceImeDialogGetResult"','ExportName = "sceImeDialogAbort"','ExportName = "sceImeDialogTerm"','ParamMaxTextLengthOffset','ParamInputTextBufferOffset')){
    if((CountText $text $m) -ne 1){ $issues++; Write-Host "[V74.0.85][ERROR] structural marker count != 1: $m" -ForegroundColor Red }
}
$imeText=[IO.File]::ReadAllText($ime)
foreach($m in @('ExportName = "sceImeUpdate"','ExportName = "sceImeKeyboardOpen"')){
    if(-not $imeText.Contains($m)){ $issues++; Write-Host "[V74.0.85][ERROR] libSceIme companion export missing: $m" -ForegroundColor Red }
}
$legacyAuto=$text.Contains('DefaultInputText = "Sharp"') -or $text.Contains('ime.dialog_autofill')
Write-Host '[V74.0.85] Target: libSceImeDialog real asynchronous host text-entry lifecycle.'
Write-Host '[V74.0.85] The current implementation exposes IME ABI entry points but no interactive text-entry panel.'
Write-Host "[V74.0.85] legacy_immediate_autofill=$legacyAuto"
Write-Host "[V74.0.85] ImeDialogSHA256=$(Sha $src)"
Write-Host "[V74.0.85] ImeExportsSHA256=$(Sha $ime)"
$eboot=$env:SHARPEMU_DEMONS_EBOOT
if([string]::IsNullOrWhiteSpace($eboot)){ $eboot='F:\JOGOSPS5\PPSA01341\eboot.bin' }
if(Test-Path -LiteralPath $eboot){ Write-Host "[V74.0.85] Eboot=$eboot"; Write-Host "[V74.0.85] EbootSHA256=$(Sha $eboot)" } else { Write-Host "[V74.0.85][WARN] eboot not found during precheck: $eboot" -ForegroundColor Yellow }
if($issues -gt 0){ Write-Host "[V74.0.85] PRECHECK FAILED issues=$issues" -ForegroundColor Red; exit 1 }
Write-Host '[V74.0.85] PRECHECK PASSED.' -ForegroundColor Green
