. "$PSScriptRoot\common.ps1"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'validate.ps1')
if($LASTEXITCODE -ne 0){ exit $LASTEXITCODE }

$src=ImeDialogSource
$ime=ImeExportsSource
$proj=CliProject
foreach($p in @($src,$ime,$proj)){
    if(-not(Test-Path -LiteralPath $p -PathType Leaf)){
        Write-Host "[V74.0.85.1][ERROR] missing source: $p" -ForegroundColor Red
        exit 1
    }
}

$text=[IO.File]::ReadAllText($src)
$currentSha=Sha $src
$baselineSha='DB550450C034EB7B12530F43ECEC27B9D0BCCA2AC1A41B08C3E21E6F7315B459'

if($text.Contains('SHARPEMU_V74_0_85_1_IME_DIALOG_HOST_TEXT_INPUT')){
    Write-Host '[V74.0.85.1] PRECHECK: patch already installed.' -ForegroundColor Yellow
    Write-Host "ImeDialogSHA256=$currentSha"
    exit 10
}

$issues=0

# Require the exact source snapshot observed in the failed V74.0.85 precheck.
# This prevents replacing an unrelated/newer IME implementation by accident.
if($currentSha -ne $baselineSha){
    $issues++
    Write-Host "[V74.0.85.1][ERROR] unsupported ImeDialogExports.cs baseline." -ForegroundColor Red
    Write-Host "[V74.0.85.1] ExpectedSHA256=$baselineSha"
    Write-Host "[V74.0.85.1] CurrentSHA256=$currentSha"
}

foreach($m in @(
    'public static class ImeDialogExports',
    'ExportName = "sceImeDialogInit"',
    'ExportName = "sceImeDialogGetStatus"',
    'ExportName = "sceImeDialogGetResult"',
    'ExportName = "sceImeDialogAbort"',
    'ExportName = "sceImeDialogTerm"',
    'private const ulong ParamMaxTextLengthOffset = 0x24;',
    'private const ulong ParamInputTextBufferOffset = 0x28;'
)){
    if((CountText $text $m) -ne 1){
        $issues++
        Write-Host "[V74.0.85.1][ERROR] structural declaration/export marker count != 1: $m" -ForegroundColor Red
    }
}

# The offset identifiers legitimately occur twice in the baseline: declaration + use.
# V74.0.85 incorrectly required the raw identifier to occur exactly once.
$maxOffsetRefs=CountText $text 'ParamMaxTextLengthOffset'
$bufferOffsetRefs=CountText $text 'ParamInputTextBufferOffset'
if($maxOffsetRefs -lt 2){
    $issues++
    Write-Host "[V74.0.85.1][ERROR] ParamMaxTextLengthOffset reference count too small: $maxOffsetRefs" -ForegroundColor Red
}
if($bufferOffsetRefs -lt 2){
    $issues++
    Write-Host "[V74.0.85.1][ERROR] ParamInputTextBufferOffset reference count too small: $bufferOffsetRefs" -ForegroundColor Red
}

$imeText=[IO.File]::ReadAllText($ime)
foreach($m in @('ExportName = "sceImeUpdate"','ExportName = "sceImeKeyboardOpen"')){
    if(-not $imeText.Contains($m)){
        $issues++
        Write-Host "[V74.0.85.1][ERROR] libSceIme companion export missing: $m" -ForegroundColor Red
    }
}

$legacyAuto=$text.Contains('DefaultInputText = "Sharp"') -or $text.Contains('ime.dialog_autofill')
Write-Host '[V74.0.85.1] Target: libSceImeDialog real asynchronous host text-entry lifecycle.'
Write-Host '[V74.0.85.1] V74.0.85 precheck bug fixed: offset identifiers are validated by exact declarations, not raw occurrence count.'
Write-Host "[V74.0.85.1] ParamMaxTextLengthOffsetRefs=$maxOffsetRefs"
Write-Host "[V74.0.85.1] ParamInputTextBufferOffsetRefs=$bufferOffsetRefs"
Write-Host "[V74.0.85.1] legacy_immediate_autofill=$legacyAuto"
Write-Host "[V74.0.85.1] ImeDialogSHA256=$currentSha"
Write-Host "[V74.0.85.1] ImeExportsSHA256=$(Sha $ime)"

$eboot=$env:SHARPEMU_DEMONS_EBOOT
if([string]::IsNullOrWhiteSpace($eboot)){ $eboot='F:\JOGOSPS5\PPSA01341\eboot.bin' }
if(Test-Path -LiteralPath $eboot){
    Write-Host "[V74.0.85.1] Eboot=$eboot"
    Write-Host "[V74.0.85.1] EbootSHA256=$(Sha $eboot)"
}else{
    Write-Host "[V74.0.85.1][WARN] eboot not found during precheck: $eboot" -ForegroundColor Yellow
}

if($issues -gt 0){
    Write-Host "[V74.0.85.1] PRECHECK FAILED issues=$issues" -ForegroundColor Red
    exit 1
}
Write-Host '[V74.0.85.1] PRECHECK PASSED.' -ForegroundColor Green
