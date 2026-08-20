param(
    [string]$RepositoryRoot = (Get-Location).Path,
    [string]$Eboot = 'F:\JOGOSPS5\PPSA01341\eboot.bin'
)

. "$PSScriptRoot\common.ps1"

$repo = Resolve-RepoV74056362 $RepositoryRoot
[void](Assert-EbootV74056362 $Eboot)
Assert-CumulativeV74056362 $repo

$agcPath = Join-Path $repo $script:AgcRelative
$presenterPath = Join-Path $repo $script:PresenterRelative

$agcState = Get-AgcStateV74056362 $repo
$presenterState = Get-PresenterStateV74056362 $repo

if ($agcState.State -eq 'Divergent') {
    throw ('{0} APPLY REFUSED AGC: {1}' -f $script:Tag, $agcState.Problems)
}

if ($presenterState.State -eq 'Divergent') {
    throw ('{0} APPLY REFUSED Presenter: {1}' -f $script:Tag, $presenterState.Problems)
}

$patches = Join-Path $repo 'Patches'
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupDir = Join-Path $repo (
    '.sharpemu-hotfix-backup\GBufferLightingV74056362_' + $stamp
)

$buildLog = Join-Path $patches (
    'SharpEmu_V74_0_56_36_2_GBUFFER_LIGHTING_BUILD_' + $stamp + '.log'
)

$changed = @()

try {
    if ($agcState.State -eq 'Ready') {
        New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
        $agcBackup = Join-Path $backupDir 'AgcExports.cs'

        Copy-Item -LiteralPath $agcPath -Destination $agcBackup -Force
        Apply-AgcV74056362 $agcPath

        if ((Get-AgcStateV74056362 $repo).State -ne 'Applied') {
            throw ('{0} AGC patch did not reach Applied state.' -f $script:Tag)
        }

        $changed += [pscustomobject]@{
            Source = $agcPath
            Backup = $agcBackup
        }
    }

    if ($presenterState.State -eq 'Ready') {
        New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
        $presenterBackup = Join-Path $backupDir 'VulkanVideoPresenter.cs'

        Copy-Item -LiteralPath $presenterPath -Destination $presenterBackup -Force

        $didPatch = Apply-PresenterGuardV74056362 $presenterPath

        if (-not $didPatch) {
            throw ('{0} Presenter unexpectedly reported already satisfied during apply.' -f $script:Tag)
        }

        $presenterAfter = Get-PresenterStateV74056362 $repo

        if ($presenterAfter.State -ne 'Satisfied') {
            throw ('{0} Presenter guard did not reach Satisfied state.' -f $script:Tag)
        }

        $changed += [pscustomobject]@{
            Source = $presenterPath
            Backup = $presenterBackup
        }
    }

    $pushed = $false

    try {
        Push-Location $repo
        $pushed = $true

        $output = & dotnet build `
            'src\SharpEmu.CLI\SharpEmu.CLI.csproj' `
            -c Debug `
            -r win-x64 `
            --nologo 2>&1

        $exitCode = $LASTEXITCODE
        $output | Tee-Object -FilePath $buildLog

        if ($exitCode -ne 0) {
            throw ('{0} build failed code={1}' -f $script:Tag, $exitCode)
        }
    }
    finally {
        if ($pushed) {
            Pop-Location
        }
    }
}
catch {
    foreach ($item in $changed) {
        if (Test-Path -LiteralPath $item.Backup -PathType Leaf) {
            Copy-Item -LiteralPath $item.Backup -Destination $item.Source -Force
        }
    }

    if ($changed.Count -gt 0) {
        Write-Host (
            '{0} APPLY/BUILD FAILED; restored {1} source file(s).' -f `
            $script:Tag, `
            $changed.Count
        ) -ForegroundColor Yellow
    }

    throw
}

Write-Host ('{0} APPLY/BUILD PASSED.' -f $script:Tag) -ForegroundColor Green
Write-Host ('{0} ChangedFiles={1}' -f $script:Tag, $changed.Count)
Write-Host ('{0} Backup={1}' -f $script:Tag, $backupDir)
Write-Host ('{0} BuildLog={1}' -f $script:Tag, $buildLog)
