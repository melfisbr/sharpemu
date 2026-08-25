param([string]$EbootPath='F:\JOGOSPS5\PPSA01341\eboot.bin')
. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepositoryRoot;$patches=Get-PatchesRoot
if(-not(Test-Path -LiteralPath $EbootPath -PathType Leaf)){throw "$script:Tag eboot missing: $EbootPath"}
$adapter=Join-Path $repo 'artifacts\bin\Release\net10.0\win-x64\plugins\bink2\SharpEmu.BinkNative.dll'
if(-not(Test-Path -LiteralPath $adapter)){throw "$script:Tag run RUN_3 first"}
$runtime=Find-Runtime ''
if([string]::IsNullOrWhiteSpace($runtime)){throw "$script:Tag native A/V test requires compatible x64 bink2w64.dll; run RUN_4 first"}
$names=@('SHARPEMU_BINK_NATIVE_DLL','SHARPEMU_BINK_RUNTIME_DLL','SHARPEMU_BINK_MODE','SHARPEMU_BINK_NATIVE_FALLBACK','SHARPEMU_BINK_NATIVE_PREFER','SHARPEMU_BINK_AUDIO_BACKEND','SHARPEMU_LOG_AUDIO_OUT2','SHARPEMU_LOG_AMPR_READS')
$old=@{};foreach($n in $names){$old[$n]=[Environment]::GetEnvironmentVariable($n,'Process')}
$env:SHARPEMU_BINK_NATIVE_DLL=$adapter
$env:SHARPEMU_BINK_RUNTIME_DLL=$runtime
$env:SHARPEMU_BINK_MODE='native-rad'
$env:SHARPEMU_BINK_NATIVE_PREFER='1'
$env:SHARPEMU_BINK_NATIVE_FALLBACK='0'
$env:SHARPEMU_LOG_AUDIO_OUT2='1';$env:SHARPEMU_LOG_AMPR_READS='1'
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss';$out=Join-Path $patches "SharpEmu_V75_0_3_1_NATIVE_AV_STDOUT_$stamp.tmp";$err=Join-Path $patches "SharpEmu_V75_0_3_1_NATIVE_AV_STDERR_$stamp.tmp";$log=Join-Path $patches "SharpEmu_V75_0_3_1_NATIVE_AV_$stamp.log"
$exe=Join-Path $repo 'artifacts\bin\Release\net10.0\win-x64\SharpEmu.exe';$dll=Join-Path $repo 'artifacts\bin\Release\net10.0\win-x64\SharpEmu.dll'
Write-Host '[V75.0.3.1] Procure no log: open_ok ... tracks=N embedded_audio_active=True para BK2 com audio embutido.'
Write-Host '[V75.0.3.1] attract_movie de Demons Souls pode continuar tracks=0 porque seu audio e sidecar AT9.'
Write-Host '[V75.0.3.1] O script aguardara o SharpEmu encerrar; isso e normal. Feche o emulador para consolidar o log em Patches.'
$exit=-1
try{
 Push-Location $repo
 if(Test-Path -LiteralPath $exe){$p=Start-Process $exe -ArgumentList @(('"'+$EbootPath+'"')) -WorkingDirectory $repo -RedirectStandardOutput $out -RedirectStandardError $err -PassThru -Wait}
 else{$dotnet=(Get-Command dotnet -CommandType Application -ErrorAction Stop).Source;$p=Start-Process $dotnet -ArgumentList @(('"'+$dll+'"'),('"'+$EbootPath+'"')) -WorkingDirectory $repo -RedirectStandardOutput $out -RedirectStandardError $err -PassThru -Wait}
 $exit=$p.ExitCode
}finally{Pop-Location;foreach($n in $names){[Environment]::SetEnvironmentVariable($n,$old[$n],'Process')}}
@("SharpEmu V75.0.3 NATIVE A/V TEST","adapter=$adapter","runtime=$runtime","exit=$exit")|Set-Content -LiteralPath $log -Encoding UTF8
foreach($f in @($out,$err)){if(Test-Path $f){Get-Content $f|Add-Content $log -Encoding UTF8;Remove-Item $f -Force}}
Write-Tag "TEST COMPLETE exit=$exit log=$log"
