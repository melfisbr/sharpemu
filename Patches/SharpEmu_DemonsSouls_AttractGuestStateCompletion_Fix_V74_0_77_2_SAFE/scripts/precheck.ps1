. "$PSScriptRoot\common.ps1"
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'validate.ps1');if($LASTEXITCODE){exit $LASTEXITCODE}
$h=Host;$s=NL([IO.File]::ReadAllText($h))
if($s.Contains('SHARPEMU_V74_0_77_2_DEMONS_ATTRACT_GUEST_COMPLETION')){
 Write-Host '[V74.0.77.2] State=AlreadyApplied' -ForegroundColor Yellow;exit 10
}
$required=@(
 'ShouldUseRadGuestCompletionHandoffV7405610',
 'IsOneShotStartupBinkV74013',
 'TryReadGuestCompletionShim',
 'TryReadGuestCompletionShimHeaderFallbackV74013',
 'internal static bool TryTakeOverGuestMovie(',
 'WaitForHostPlaybackToFinish'
)
foreach($m in $required){if(-not$s.Contains($m)){Write-Host "[V74.0.77.2][ERROR] prerequisite missing: $m" -ForegroundColor Red;exit 1}}
try{
 $span=FindMethodSpan $s '(?m)^[ \t]*internal static bool TryTakeOverGuestMovie\(' 'TryTakeOverGuestMovie'
 $b=Body $s $span
 if((CountExact $b 'var v7405610RadGuestCompletionHandoff')-ne 1){throw 'v7405610 var changed'}
 if((CountExact $b 'var v7405610LegacyStartupCompletionShim')-ne 1){throw 'legacy shim var changed'}
 if((CountExact $b 'if (v7405610RadGuestCompletionHandoff)')-ne 1){throw 'completion logging branch changed'}
}catch{Write-Host "[V74.0.77.2][ERROR] $($_.Exception.Message)" -ForegroundColor Red;exit 1}

$eboot=$env:SHARPEMU_DEMONS_EBOOT
if([string]::IsNullOrWhiteSpace($eboot)){$eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'}
try{$a=AuditEboot $eboot}catch{Write-Host "[V74.0.77.2][ERROR] $($_.Exception.Message)" -ForegroundColor Red;exit 1}
$out=@()
$out+="Eboot=$($a.Path)";$out+="EbootSHA256=$($a.Sha256)";$out+="EbootBytes=$($a.Length)"
foreach($k in $a.Found.Keys|Sort-Object){$v=$a.Found[$k];$out+=("$k="+$(if($v-ge 0){"0x{0:X}"-f$v}else{'NOT_FOUND'}))}
$stamp=Get-Date -Format yyyyMMdd_HHmmss;$audit=Join-Path (Patches) ("SharpEmu_V74_0_77_2_EBOOT_AUDIT_"+$stamp+'.log');$out|Set-Content $audit -Encoding UTF8;$out|ForEach-Object{Write-Host "[V74.0.77.2][EBOOT] $_"}
if($a.Found['BinkMovieTextureDataSource']-lt 0 -or $a.Found['sce::Agc::submitGraphics']-lt 0 -or ($a.Found['MusicSkipIntro']-lt 0 -and$a.Found['StartIntro']-lt 0)){
 Write-Host '[V74.0.77.2][ERROR] EBOOT does not match expected Demons Souls Bink/AGC state-machine contract.' -ForegroundColor Red;exit 1
}
Write-Host "[V74.0.77.2] HostSHA256=$(Sha $h)"
Write-Host '[V74.0.77.2] Root cause target: RAD attract has no guest one-frame completion handoff; guest Bink state remains unfinished after host TAB skip.'
Write-Host '[V74.0.77.2] PRECHECK PASSED.' -ForegroundColor Green
