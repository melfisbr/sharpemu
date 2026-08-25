param([string]$EbootPath='F:\JOGOSPS5\PPSA01341\eboot.bin')
. (Join-Path $PSScriptRoot 'common.ps1');$s=Read-State 3;$repo=Get-RepositoryRoot;$patches=Get-PatchesRoot
Assert-V1180 (Get-Presenter) (Get-Envelope)
$dll=Join-Path $repo 'artifacts\bin\Release\net10.0\win-x64\SharpEmu.dll'
$env:SHARPEMU_GPU_RESIDENT_SHADER_V1180='1';$env:SHARPEMU_GPU_RESIDENT_SHADER_MAX_V1180='4096'
$env:SHARPEMU_DESCRIPTOR_SET_CACHE_V11716='1';$env:SHARPEMU_DESCRIPTOR_SET_CACHE_MAX_SETS_V11716='512'
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss';$out=Join-Path $patches "SharpEmu_V74_0_118_0_1_STDOUT_$stamp.log";$err=Join-Path $patches "SharpEmu_V74_0_118_0_1_STDERR_$stamp.log"
Write-Host '[V118.0] Passe pelo PS Studios; confirme ausência de stall. Na Character Creation mantenha >=60s.'
$p=Start-Process dotnet -ArgumentList @('"' + $dll + '"','"' + $EbootPath + '"') -WorkingDirectory $repo -RedirectStandardOutput $out -RedirectStandardError $err -PassThru -Wait
$fps=Read-Host 'FPS';$draws=Read-Host 'DRAWS/s';$cpu=Read-Host 'CPU %';$gpu=Read-Host 'GPU %'
$log=Join-Path $patches "SharpEmu_V74_0_118_0_1_RUNTIME_$stamp.log"
@("process_exit_code=$($p.ExitCode)","observed_fps=$fps","observed_draws=$draws","observed_cpu=$cpu","observed_gpu=$gpu")|Set-Content $log
Get-Content $out,$err|Add-Content $log
Save-State 4 'TEST_COMPLETED' @{runtime_log=$log;raw_stdout=$out;raw_stderr=$err;observed_fps=$fps;observed_draws=$draws;observed_cpu=$cpu;observed_gpu=$gpu}
Write-Tag "TEST COMPLETE $log"
