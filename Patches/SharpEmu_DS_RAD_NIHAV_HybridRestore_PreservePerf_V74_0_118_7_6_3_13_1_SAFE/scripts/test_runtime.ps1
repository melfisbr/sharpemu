param(
    [string]$EbootPath='F:\JOGOSPS5\PPSA01341\eboot.bin'
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'common.ps1')

$repo=Get-RepositoryRoot
$patches=Get-PatchesRoot

if(-not(Test-Path -LiteralPath (Get-StatePath))) {
    throw "$script:Tag install state missing; run RUN_3 first"
}
if(-not(Test-Path -LiteralPath $EbootPath)) {
    throw "$script:Tag eboot missing: $EbootPath"
}

$hostMovieBridge=
    Join-Path $repo $script:RelativeHostMovieBridge
$hostText=[IO.File]::ReadAllText($hostMovieBridge)
if(-not$hostText.Contains(
    'SHARPEMU_V74_0_118_7_6_3_13_RAD_NIHAV_HYBRID_RESTORE')) {
    throw "$script:Tag V3.13 source marker missing"
}

Assert-PerfMarkers

$names=@(
    'SHARPEMU_RADVIDEO64',
    'SHARPEMU_BINK_MODE',
    'SHARPEMU_BINK_NATIVE_PREFER',
    'SHARPEMU_DS_UI_BINK_RAD_INTERACTIVE',
    'SHARPEMU_DS_UI_BINK_INTERNAL',
    'SHARPEMU_DS_UI_BINK_DIRECT_YUV',
    'SHARPEMU_DS_RAD_MAIN_MENU_CAPTURE_COMPOSITE',
    'SHARPEMU_DS_RAD_MAIN_MENU_CAPTURE_EXPERIMENTAL',
    'SHARPEMU_LOG_AUDIO_OUT2',
    'SHARPEMU_LOG_AMPR_READS'
)
$oldEnv=@{}
foreach($name in $names) {
    $oldEnv[$name]=
        [Environment]::GetEnvironmentVariable($name,'Process')
}

Set-TestEnvironment

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$stdout=
    Join-Path $patches (
        "SharpEmu_V74_0_118_7_6_3_13_1_STDOUT_$stamp.tmp")
$stderr=
    Join-Path $patches (
        "SharpEmu_V74_0_118_7_6_3_13_1_STDERR_$stamp.tmp")
$log=
    Join-Path $patches (
        "SharpEmu_V74_0_118_7_6_3_13_1_RAD_NIHAV_HYBRID_$stamp.log")

Write-Host '[V74.0.118.7.6.3.13.1] TESTE RAD + NIHAV HISTORICAL HYBRID:'
Write-Host '1. Nao pule logo_intro.bk2: ele deve abrir pelo RAD oficial.'
Write-Host '2. Ao terminar logo_intro, logo_intro_loop deve trocar para NIHAV interno.'
Write-Host '3. PRESS ANY BUTTON deve voltar a ser compositor guest + NIHAV, sem child RAD sobre a UI.'
Write-Host '4. Entre no main_menu e permaneça 20-30 s.'
Write-Host '5. main_menu.bk2 deve ser NIHAV interno; textos/highlights/UI guest devem permanecer vivos.'
Write-Host '6. Os caminhos V74.0.68/V74.0.71/V74.0.72 e Direct-YUV/reservoir atuais permanecem no source.'
Write-Host '7. Feche o SharpEmu normalmente.'

$exe=
    Join-Path $repo (
        'artifacts\bin\Release\net10.0\win-x64\SharpEmu.exe')
$dll=
    Join-Path $repo (
        'artifacts\bin\Release\net10.0\win-x64\SharpEmu.dll')

$exitCode=-1
try {
    Push-Location $repo
    if(Test-Path -LiteralPath $exe) {
        $proc=Start-Process `
            -FilePath $exe `
            -ArgumentList @(('"'+$EbootPath+'"')) `
            -WorkingDirectory $repo `
            -RedirectStandardOutput $stdout `
            -RedirectStandardError $stderr `
            -PassThru `
            -Wait
    }
    else {
        $dotnet=
            (Get-Command dotnet -CommandType Application -ErrorAction Stop).Source
        $proc=Start-Process `
            -FilePath $dotnet `
            -ArgumentList @(('"'+$dll+'"'),('"'+$EbootPath+'"')) `
            -WorkingDirectory $repo `
            -RedirectStandardOutput $stdout `
            -RedirectStandardError $stderr `
            -PassThru `
            -Wait
    }
    $exitCode=$proc.ExitCode
}
finally {
    Pop-Location
    foreach($name in $names) {
        [Environment]::SetEnvironmentVariable(
            $name,
            $oldEnv[$name],
            'Process')
    }
}

@(
    'SharpEmu V74.0.118.7.6.3.13.1 RAD + NIHAV HYBRID TEST',
    "timestamp=$stamp",
    "process_exit_code=$exitCode",
    'historical_media_baseline=V74.0.88.6.2',
    'fullscreen_title_movies=official-rad',
    'persistent_ui_binks=internal-nihav',
    'later_performance_sources=preserved-byte-for-byte',
    'ui_rad_interactive=disabled',
    'main_menu_rad_capture=disabled',
    'visual_verification_required=True'
) | Set-Content -LiteralPath $log -Encoding UTF8

foreach($path in @($stdout,$stderr)) {
    if(Test-Path -LiteralPath $path) {
        Get-Content -LiteralPath $path |
            Add-Content -LiteralPath $log -Encoding UTF8
        Remove-Item -LiteralPath $path -Force
    }
}

Write-Tag "TEST COMPLETE exit=$exitCode log=$log"
