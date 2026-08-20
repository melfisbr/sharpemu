param(
    [Parameter(Mandatory=$true)][string]$PackageRoot
)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:Tag = '[V74.0.78.3]'
$PackageRoot = $PackageRoot.Trim().Trim([char]34).Trim([char]39)
$script:PackageRoot = (Resolve-Path -LiteralPath $PackageRoot).Path.TrimEnd('\')
$script:PatchesRoot = Split-Path -Parent $script:PackageRoot
$script:RepoRoot = Split-Path -Parent $script:PatchesRoot
$script:PresenterRel = 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$script:AgcRel = 'src\SharpEmu.Libs\Agc\AgcExports.cs'
$script:PresenterPath = Join-Path $script:RepoRoot $script:PresenterRel
$script:AgcPath = Join-Path $script:RepoRoot $script:AgcRel
$script:BackupRoot = Join-Path $script:RepoRoot '.sharpemu-hotfix-backup'
$script:StateFile = Join-Path $script:PackageRoot 'LAST_BACKUP.txt'

function Get-Sha256([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Read-Utf8([string]$Path) {
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $enc)
}

function Assert-Repo {
    if (-not (Test-Path -LiteralPath $script:PresenterPath -PathType Leaf)) {
        throw "$script:Tag Presenter ausente: $script:PresenterPath"
    }
    if (-not (Test-Path -LiteralPath $script:AgcPath -PathType Leaf)) {
        throw "$script:Tag AGC ausente: $script:AgcPath"
    }
}

function Get-Count([string]$Text, [string]$Pattern) {
    return ([regex]::Matches($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)).Count
}

function Assert-StructuralContracts {
    Assert-Repo
    $presenter = Read-Utf8 $script:PresenterPath
    $agc = Read-Utf8 $script:AgcPath

    $checks = [ordered]@{
        PresenterCacheMethod = (Get-Count $presenter 'internal\s+static\s+bool\s+IsTextureContentCached\s*\(\s*in\s+TextureContentIdentity\s+identity\s*\)')
        PresenterMarkMethod = (Get-Count $presenter 'private\s+static\s+void\s+MarkTextureContentCached\s*\(')
        PresenterUnmarkMethod = (Get-Count $presenter 'private\s+static\s+void\s+UnmarkTextureContentCached\s*\(')
        PresenterClearMethod = (Get-Count $presenter 'private\s+static\s+void\s+ClearCachedTextureIdentities\s*\(')
        PresenterSamplerAlias = (Get-Count $presenter 'SAMPLER_IMAGE_ALIAS')
        AgcTextureCacheQuery = (Get-Count $agc 'GuestGpu\.Current\.IsTextureContentCached\s*\(')
        AgcLargeSnapshot = (Get-Count $agc 'physicalSourceByteCount')
        AgcSignalMethod = (Get-Count $agc 'private\s+static\s+void\s+SignalGpuWaitMonitor\s*\(\s*object\s+memory\s*\)')
        AgcWaitMonitor = (Get-Count $agc 'private\s+static\s+void\s+MonitorGpuWaits\s*\(')
        AgcDedicatedDrain = (Get-Count $agc 'EnsureDedicatedResumableDcbDrainWorkerV74071')
    }

    foreach ($entry in $checks.GetEnumerator()) {
        Write-Host "$script:Tag $($entry.Key)=$($entry.Value)"
    }

    if ($checks.PresenterCacheMethod -ne 1) { throw "$script:Tag contrato IsTextureContentCached ambiguo/ausente." }
    if ($checks.PresenterMarkMethod -ne 1) { throw "$script:Tag contrato MarkTextureContentCached ambiguo/ausente." }
    if ($checks.PresenterUnmarkMethod -ne 1) { throw "$script:Tag contrato UnmarkTextureContentCached ambiguo/ausente." }
    if ($checks.PresenterClearMethod -ne 1) { throw "$script:Tag contrato ClearCachedTextureIdentities ambiguo/ausente." }
    if ($checks.PresenterSamplerAlias -lt 1) { throw "$script:Tag V74.0.73 sampler alias ausente; nao aplicar." }
    if ($checks.AgcTextureCacheQuery -lt 1) { throw "$script:Tag consulta de cache AGC ausente." }
    if ($checks.AgcSignalMethod -ne 1) { throw "$script:Tag SignalGpuWaitMonitor ambiguo/ausente." }
    if ($checks.AgcWaitMonitor -ne 1) { throw "$script:Tag MonitorGpuWaits ambiguo/ausente." }
    if ($checks.AgcDedicatedDrain -lt 1) { throw "$script:Tag drain dedicado V74.0.71 ausente." }

    return @{
        Presenter = $presenter
        Agc = $agc
    }
}

function New-Backup {
    if (-not (Test-Path -LiteralPath $script:BackupRoot)) {
        New-Item -ItemType Directory -Path $script:BackupRoot | Out-Null
    }
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $dir = Join-Path $script:BackupRoot "DrawTextureHotPathV740783_$stamp"
    New-Item -ItemType Directory -Path $dir | Out-Null
    Copy-Item -LiteralPath $script:PresenterPath -Destination (Join-Path $dir 'VulkanVideoPresenter.cs') -Force
    Copy-Item -LiteralPath $script:AgcPath -Destination (Join-Path $dir 'AgcExports.cs') -Force
    Write-Utf8NoBom $script:StateFile $dir
    return $dir
}

function Restore-Backup([string]$Dir) {
    $p = Join-Path $Dir 'VulkanVideoPresenter.cs'
    $a = Join-Path $Dir 'AgcExports.cs'
    if (-not (Test-Path -LiteralPath $p)) { throw "$script:Tag backup presenter ausente: $p" }
    if (-not (Test-Path -LiteralPath $a)) { throw "$script:Tag backup AGC ausente: $a" }
    Copy-Item -LiteralPath $p -Destination $script:PresenterPath -Force
    Copy-Item -LiteralPath $a -Destination $script:AgcPath -Force
}

function Quote-ProcessArgument([string]$Value) {
    if ($null -eq $Value) { return '""' }
    return '"' + ($Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

function Find-SharpEmuExe {
    $candidates = @(
        (Join-Path $script:RepoRoot 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'),
        (Join-Path $script:RepoRoot 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.CLI.exe'),
        (Join-Path $script:RepoRoot 'artifacts\bin\Release\net10.0\win-x64\SharpEmu.exe'),
        (Join-Path $script:RepoRoot 'artifacts\bin\Release\net10.0\win-x64\SharpEmu.CLI.exe')
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c -PathType Leaf) { return $c }
    }
    return $null
}
