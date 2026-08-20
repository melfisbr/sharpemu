. "$PSScriptRoot\common.ps1"
$src=ImeDialogSource; $exe=ExePath; $issues=0
Write-Host '[V74.0.85] DIAGNOSTIC START' -ForegroundColor Cyan
if(-not(Test-Path -LiteralPath $src)){ Write-Host 'ime_source_exists=False'; exit 1 }
$t=[IO.File]::ReadAllText($src)
$checks=[ordered]@{
    ime_host_text_marker=$t.Contains('SHARPEMU_V74_0_85_IME_DIALOG_HOST_TEXT_INPUT')
    init_enters_running=($t.Contains('_status = StatusRunning;') -and $t.Contains('StartHostPanel(generation'))
    host_panel_backend=($t.Contains('windows-powershell-winforms') -and $t.Contains('System.Windows.Forms.Form'))
    guest_buffer_commit=$t.Contains('[V74.0.85][IME_DIALOG] text_commit')
    completion_pumped_by_guest=$t.Contains('PumpCompletedHostPanel(ctx);')
    utf16le_write=$t.Contains('Encoding.Unicode.GetBytes(text)')
    max_length_preserved=$t.Contains('ParamMaxTextLengthOffset = 0x24')
    input_buffer_preserved=$t.Contains('ParamInputTextBufferOffset = 0x28')
    old_immediate_autofill_removed=(-not $t.Contains('DefaultInputText = "Sharp"'))
    five_dialog_exports=((@('sceImeDialogInit','sceImeDialogGetStatus','sceImeDialogGetResult','sceImeDialogAbort','sceImeDialogTerm') | Where-Object { $t.Contains('ExportName = "'+$_+'"') }).Count -eq 5)
    build_artifact_exists=(Test-Path -LiteralPath $exe -PathType Leaf)
}
foreach($kv in $checks.GetEnumerator()){ Write-Host ($kv.Key+'='+$kv.Value); if(-not $kv.Value){$issues++} }
Write-Host "ImeDialogSHA256=$(Sha $src)"
if($issues -gt 0){ Write-Host "[V74.0.85] DIAGNOSTIC FAILED issues=$issues" -ForegroundColor Red; exit 1 }
Write-Host '[V74.0.85] DIAGNOSTIC PASSED.' -ForegroundColor Green
