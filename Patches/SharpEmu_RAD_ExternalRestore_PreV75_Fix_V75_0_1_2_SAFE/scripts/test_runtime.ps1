param(
    [string]$EbootPath='F:\JOGOSPS5\PPSA01341\eboot.bin'
)
. (Join-Path $PSScriptRoot 'common.ps1')

$repo=Get-RepositoryRoot
$patches=Get-PatchesRoot
$statePath=Get-StatePath

if(-not(Test-Path -LiteralPath $statePath -PathType Leaf)){
    throw "$script:Tag restore state missing; run RUN_3 first"
}
if(-not(Test-Path -LiteralPath $EbootPath -PathType Leaf)){
    throw "$script:Tag eboot missing: $EbootPath"
}

$current=Get-CurrentSourceState
if($current.NativeHostMarker -or $current.NativePlaybackMarker){
    throw "$script:Tag V75 native source marker is still active; restore is incomplete"
}
$adapterCount=@(
    Get-NativeAdapterPaths |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
).Count
if($adapterCount -ne 0){
    throw "$script:Tag native adapter still deployed count=$adapterCount"
}

$names=@(
    'SHARPEMU_RADVIDEO64',
    'SHARPEMU_BINK_MODE',
    'SHARPEMU_BINK_NATIVE_PREFER',
    'SHARPEMU_BINK_NATIVE_FALLBACK',
    'SHARPEMU_BINK_NATIVE_DLL',
    'SHARPEMU_BINK_RUNTIME_DLL',
    'SHARPEMU_DS_UI_BINK_RAD_INTERACTIVE',
    'SHARPEMU_DS_UI_BINK_INTERNAL',
    'SHARPEMU_LOG_AUDIO_OUT2',
    'SHARPEMU_LOG_AMPR_READS'
)
$old=@{}
foreach($name in $names){
    $old[$name]=[Environment]::GetEnvironmentVariable($name,'Process')
}

Set-ExternalRadTestEnvironment

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$stdout=Join-Path $patches "SharpEmu_V75_0_1_2_RAD_STDOUT_$stamp.tmp"
$stderr=Join-Path $patches "SharpEmu_V75_0_1_2_RAD_STDERR_$stamp.tmp"
$log=Join-Path $patches "SharpEmu_V75_0_1_2_EXTERNAL_RAD_$stamp.log"

Write-Host '[V75.0.1.2] TESTE EXTERNAL RAD RESTORED:'
Write-Host '1. Confirme PS Studios pelo RAD.'
Write-Host '2. Confirme attract_movie pelo RAD.'
Write-Host '3. Confirme logo_intro e logo_intro_loop pelo RAD.'
Write-Host '4. Confirme main_menu pelo RAD.'
Write-Host '5. Nao deve aparecer [BINK-NATIVE] auto_selected/open_failed/attach_failed.'
Write-Host '6. Feche o SharpEmu normalmente depois do main_menu.'

$exe=Join-Path $repo 'artifacts\bin\Release\net10.0\win-x64\SharpEmu.exe'
$dll=Join-Path $repo 'artifacts\bin\Release\net10.0\win-x64\SharpEmu.dll'
$processExit=-1

try{
    Push-Location $repo
    if(Test-Path -LiteralPath $exe -PathType Leaf){
        $proc=Start-Process -FilePath $exe `
            -ArgumentList @(('"'+$EbootPath+'"')) `
            -WorkingDirectory $repo `
            -RedirectStandardOutput $stdout `
            -RedirectStandardError $stderr `
            -PassThru -Wait
    }else{
        if(-not(Test-Path -LiteralPath $dll -PathType Leaf)){
            throw "$script:Tag release SharpEmu exe/dll missing"
        }
        $dotnet=(Get-Command dotnet -CommandType Application -ErrorAction Stop).Source
        $proc=Start-Process -FilePath $dotnet `
            -ArgumentList @(('"'+$dll+'"'),('"'+$EbootPath+'"')) `
            -WorkingDirectory $repo `
            -RedirectStandardOutput $stdout `
            -RedirectStandardError $stderr `
            -PassThru -Wait
    }
    $processExit=$proc.ExitCode
}finally{
    Pop-Location
    foreach($name in $names){
        [Environment]::SetEnvironmentVariable(
            $name,
            $old[$name],
            'Process')
    }
}

@(
    'SharpEmu V75.0.1.2 EXTERNAL RAD PRE-V75 RESTORE TEST',
    "timestamp=$stamp",
    "process_exit_code=$processExit",
    'target_mode=official-external-rad-pre-v75',
    'native_adapter=removed',
    'native_source=restored-pre-v75'
)|Set-Content -LiteralPath $log -Encoding UTF8

foreach($path in @($stdout,$stderr)){
    if(Test-Path -LiteralPath $path -PathType Leaf){
        Get-Content -LiteralPath $path |
            Add-Content -LiteralPath $log -Encoding UTF8
        Remove-Item -LiteralPath $path -Force
    }
}

Write-Tag "TEST COMPLETE exit=$processExit log=$log"
