. "$PSScriptRoot\common.ps1"
$ime=ImeDialogSource; $presenter=PresenterSource; $exe=ExePath; $issues=0
Write-Host "$script:Tag DIAGNOSTIC START" -ForegroundColor Cyan
$it=NL([IO.File]::ReadAllText($ime));$pt=NL([IO.File]::ReadAllText($presenter));$rt=NL([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'run_test.ps1')))
$checks=[ordered]@{
    ime_v86_marker=$it.Contains('SHARPEMU_V74_0_86_IME_VISIBLE_HOST_TEXT_INPUT')
    ime_running_lifecycle=($it.Contains('_status = StatusRunning;') -and $it.Contains('PumpCompletedHostPanel(ctx);'))
    ime_visible_process=($it.Contains('CreateNoWindow = false') -and $it.Contains('WindowStyle = ProcessWindowStyle.Normal'))
    ime_noninteractive_removed=(-not $it.Contains('-NonInteractive -STA'))
    ime_result_file_ipc=$it.Contains('SHARPEMU_IME_RESULT_PATH')
    ime_spawn_trace=$it.Contains('[V74.0.86][IME_DIALOG] host_panel_spawn')
    ime_guest_buffer_commit=$it.Contains('[V74.0.86][IME_DIALOG] text_commit')
    ime_offsets_preserved=($it.Contains('ParamMaxTextLengthOffset = 0x24') -and $it.Contains('ParamInputTextBufferOffset = 0x28'))
    dcc_v86_marker=$pt.Contains('SHARPEMU_V74_0_86_DS_CHARACTER_CREATOR_TYPED_DCC')
    dcc_final_reject=$pt.Contains('[V74.0.86][DS_DCC_TYPED_REJECT]')
    dcc_exact_rescan=$pt.Contains('[V74.0.86][DS_DCC_EXACT_REPLACEMENT]')
    dcc_title_scope=$pt.Contains('SHARPEMU_DS_DCC_EXACT_FORMAT')
    dcc_v56_preserved=$pt.Contains('SHARPEMU_V74_0_56_32_DCC_METADATA_ALIAS')
    dcc_v80_preserved=$pt.Contains('[V74.0.80][DCC_PROVENANCE_RECOVERY]')
    dcc_v82_preserved=$pt.Contains('[V74.0.82][DCC_METADATA_INDEX]')
    test_reserved_error_fixed=(-not $rt.Contains('$error=@('))
    test_v86_regex=$rt.Contains('\[V74\.0\.86\]\[IME_DIALOG\]')
    build_artifact_exists=(Test-Path -LiteralPath $exe -PathType Leaf)
}
foreach($kv in $checks.GetEnumerator()){Write-Host ($kv.Key+'='+$kv.Value);if(-not$kv.Value){$issues++}}
Write-Host "ImeDialogSHA256=$(Sha $ime)";Write-Host "PresenterSHA256=$(Sha $presenter)"
if($issues -gt 0){Write-Host "$script:Tag DIAGNOSTIC FAILED issues=$issues" -ForegroundColor Red;exit 1}
Write-Host "$script:Tag DIAGNOSTIC PASSED." -ForegroundColor Green
