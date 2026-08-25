param([string]$EbootPath='F:\JOGOSPS5\PPSA01341\eboot.bin')
. (Join-Path $PSScriptRoot 'common.ps1')
$state=Read-State 3
$repo=Get-RepositoryRoot
$patches=Get-PatchesRoot
$presenter=Get-PresenterSource
if((Get-Sha $presenter)-ne[string]$state.presenter_sha256){
    throw "$script:Tag source changed after build"
}
Assert-V120Markers $presenter
if(-not(Test-Path -LiteralPath $EbootPath -PathType Leaf)){
    throw "$script:Tag eboot missing: $EbootPath"
}
$dll=Join-Path $repo 'artifacts\bin\Release\net10.0\win-x64\SharpEmu.dll'
if(-not(Test-Path -LiteralPath $dll -PathType Leaf)){throw "$script:Tag Release DLL missing"}

$profile=[ordered]@{
    'SHARPEMU_TRACE_DRAW_RESOURCE_PHASES'='1'
    'SHARPEMU_TRACE_COMPUTE_PHASES'='1'
    'SHARPEMU_RENDER_PHASE_PROFILE'='1'
    'SHARPEMU_RENDER_PHASE_PROFILE_SECONDS'='5'
}
$old=@{}
foreach($name in $profile.Keys){
    $old[$name]=[Environment]::GetEnvironmentVariable($name,'Process')
    [Environment]::SetEnvironmentVariable($name,$profile[$name],'Process')
}

Get-Process SharpEmu -ErrorAction SilentlyContinue|Stop-Process -Force
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$stdout=Join-Path $patches "SharpEmu_V74_0_120_0_STDOUT_$stamp.log"
$stderr=Join-Path $patches "SharpEmu_V74_0_120_0_STDERR_$stamp.log"
$log=Join-Path $patches "SharpEmu_V74_0_120_0_RUNTIME_$stamp.log"

Write-Host ''
Write-Host '[V120.0] TESTE DRAW HOTPATH:'
Write-Host '1. Passe normalmente pelo PS Studios.'
Write-Host '2. Se houver DeviceLost/stall anormal, feche e envie o log.'
Write-Host '3. Chegue na MESMA Character Creation.'
Write-Host '4. Deixe a cena estabilizada por pelo menos 60 segundos.'
Write-Host '5. Anote FPS, DRAWS/s, CPU do SharpEmu e GPU.'
Write-Host ''

$stopwatch=[Diagnostics.Stopwatch]::StartNew()
try{
    Push-Location $repo
    try{
        $process=Start-Process `
            -FilePath 'dotnet' `
            -ArgumentList @(('"' + $dll + '"'),('"' + $EbootPath + '"')) `
            -WorkingDirectory $repo `
            -RedirectStandardOutput $stdout `
            -RedirectStandardError $stderr `
            -PassThru -Wait
    }finally{
        Pop-Location
    }
}finally{
    $stopwatch.Stop()
    foreach($name in $profile.Keys){
        [Environment]::SetEnvironmentVariable($name,$old[$name],'Process')
    }
}

$fps=Read-Host 'FPS observado na Character Creation'
$draws=Read-Host 'DRAWS/s observado'
$cpu=Read-Host 'CPU do SharpEmu em %'
$gpu=Read-Host 'GPU em %'

@(
    "process_exit_code=$($process.ExitCode)",
    ("runtime_elapsed_s={0:F3}" -f $stopwatch.Elapsed.TotalSeconds),
    "observed_fps=$fps",
    "observed_draws=$draws",
    "observed_cpu=$cpu",
    "observed_gpu=$gpu",
    'draw_resource_phase_profile=1',
    'compute_resource_phase_profile=1',
    'vkimage_change=0',
    'texture_lifetime_change=0',
    'buffer_content_change=0',
    'queue_change=0',
    'submit_change=0',
    'barrier_change=0'
)|Set-Content -LiteralPath $log -Encoding UTF8
foreach($raw in @($stdout,$stderr)){
    if(Test-Path -LiteralPath $raw){
        Get-Content -LiteralPath $raw|Add-Content -LiteralPath $log -Encoding UTF8
    }
}
Save-State 4 'TEST_COMPLETED' @{
    runtime_log=$log
    raw_stdout=$stdout
    raw_stderr=$stderr
    observed_fps=$fps
    observed_draws=$draws
    observed_cpu=$cpu
    observed_gpu=$gpu
}
Write-Tag "TEST COMPLETE log=$log"
