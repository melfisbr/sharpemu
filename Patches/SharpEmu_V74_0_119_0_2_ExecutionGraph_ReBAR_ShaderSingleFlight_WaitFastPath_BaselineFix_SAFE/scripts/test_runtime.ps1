param([string]$EbootPath='F:\JOGOSPS5\PPSA01341\eboot.bin')
. (Join-Path $PSScriptRoot 'common.ps1')
$s=Read-State 3
$repo=Get-RepositoryRoot
$patches=Get-PatchesRoot
Assert-V1190Markers (Get-AgcSource) (Get-PresenterSource) (Get-HostPoolSource) (Get-EnvelopeSource)

$dll=Join-Path $repo 'artifacts\bin\Release\net10.0\win-x64\SharpEmu.dll'
if(-not(Test-Path $dll)){throw "$script:Tag Release DLL missing"}
if(-not(Test-Path $EbootPath)){throw "$script:Tag eboot missing: $EbootPath"}

Get-Process SharpEmu -ErrorAction SilentlyContinue|Stop-Process -Force
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$out=Join-Path $patches "SharpEmu_V74_0_119_0_2_STDOUT_$stamp.log"
$err=Join-Path $patches "SharpEmu_V74_0_119_0_2_STDERR_$stamp.log"
$log=Join-Path $patches "SharpEmu_V74_0_119_0_2_RUNTIME_$stamp.log"

Write-Host ''
Write-Host '[V119.0] EXECUTION GRAPH TEST'
Write-Host '1. Passe normalmente pelo PS Studios.'
Write-Host '2. Se houver DeviceLost/stall anormal, feche e execute o rollback.'
Write-Host '3. Na MESMA Character Creation, deixe >=60 s.'
Write-Host '4. Anote FPS, DRAWS/s, CPU do SharpEmu e GPU.'
Write-Host ''

$sw=[Diagnostics.Stopwatch]::StartNew()
Push-Location $repo
try{
    $proc=Start-Process dotnet `
        -ArgumentList @(('"' + $dll + '"'),('"' + $EbootPath + '"')) `
        -WorkingDirectory $repo `
        -RedirectStandardOutput $out `
        -RedirectStandardError $err `
        -PassThru -Wait
    $ec=$proc.ExitCode
}finally{
    Pop-Location
    $sw.Stop()
}

$fps=Read-Host 'FPS observado'
$draws=Read-Host 'DRAWS/s observado'
$cpu=Read-Host 'CPU SharpEmu %'
$gpu=Read-Host 'GPU %'

@(
    "process_exit_code=$ec",
    ("runtime_elapsed_s={0:F3}" -f $sw.Elapsed.TotalSeconds),
    "observed_fps=$fps",
    "observed_draws=$draws",
    "observed_cpu=$cpu",
    "observed_gpu=$gpu",
    'baseline=V118.0.1',
    'execution_graph=1',
    'shader_singleflight=1',
    'waiter_latched_fastpath=1',
    'resident_reference_fastpath=1',
    'rebar_direct_auto=1',
    'shader_resident_max=1024',
    'v11713_global_residency=0',
    'queue_order_change=0',
    'submit_change=0',
    'barrier_change=0',
    'image_lifetime_change=0'
)|Set-Content $log -Encoding UTF8
foreach($raw in @($out,$err)){if(Test-Path $raw){Get-Content $raw|Add-Content $log -Encoding UTF8}}

Save-State 4 'TEST_COMPLETED' @{
    runtime_log=$log;raw_stdout=$out;raw_stderr=$err
    process_exit_code=$ec;observed_fps=$fps;observed_draws=$draws
    observed_cpu=$cpu;observed_gpu=$gpu
}
Write-Tag "TEST COMPLETE exit=$ec log=$log"
