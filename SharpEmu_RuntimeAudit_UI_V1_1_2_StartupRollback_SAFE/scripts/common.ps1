Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:Tag = '[RuntimeAudit UI V1.1.2]'

$script:OriginalMainWindowHash = '7D9213109B2B316DB00D97339DC9F233A0ECB467777C96D79D50364565282EAD'
$script:PatchedMainWindowHash  = '4B3D338DF26414AD0BEA811F99DAD9A0E24C4357D93ECE9021F52307A75DA28C'
$script:RuntimeAuditPartialHash = '017F345836B53E93DD17AB7E6C88BD7899D4E34C16BEAF1DF2A6D911EC310E72'
$script:ExpectedBackupName = 'RuntimeAudit_UI_V1_1_20260817_100143'

function Get-PackageRoot {
    (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
}

function Get-RepoRoot {
    $packageRoot = Get-PackageRoot
    $repo = (Resolve-Path -LiteralPath (Join-Path $packageRoot '..')).Path
    if (-not (Test-Path -LiteralPath (Join-Path $repo 'src'))) {
        throw "$script:Tag Repository root not detected above package: $repo"
    }
    $repo
}

function Write-Step([string]$Message) {
    Write-Host "$script:Tag $Message"
}

function Get-HashSafe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()
}

function Get-LatestRuntimeAuditBackup([string]$Repo) {
    $root = Join-Path $Repo '.sharpemu-hotfix-backup'
    $exact = Join-Path $root $script:ExpectedBackupName
    if (Test-Path -LiteralPath $exact -PathType Container) { return $exact }

    $candidate = Get-ChildItem -LiteralPath $root -Directory -Filter 'RuntimeAudit_UI_V1_1_*' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($null -eq $candidate) {
        throw "$script:Tag RuntimeAudit UI V1.1 backup not found under $root"
    }
    $candidate.FullName
}

function Find-FileByHash([string]$Root, [string]$Hash, [string]$Filter = '*') {
    $matches = New-Object System.Collections.Generic.List[string]
    Get-ChildItem -LiteralPath $Root -Recurse -File -Filter $Filter -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            if ((Get-HashSafe $_.FullName) -eq $Hash) { $matches.Add($_.FullName) }
        } catch {}
    }
    @($matches)
}

function Find-CurrentMainWindow([string]$Repo) {
    $src = Join-Path $Repo 'src'
    $all = @(Get-ChildItem -LiteralPath $src -Recurse -File -Filter 'MainWindow.cs' -ErrorAction SilentlyContinue)
    if ($all.Count -eq 0) {
        throw "$script:Tag MainWindow.cs not found under $src"
    }

    $hashMatch = @($all | Where-Object { (Get-HashSafe $_.FullName) -eq $script:PatchedMainWindowHash })
    if ($hashMatch.Count -eq 1) { return $hashMatch[0].FullName }

    $markerMatch = @($all | Where-Object {
        $t = Get-Content -LiteralPath $_.FullName -Raw
        $t -match 'InstallRuntimeAuditButton|Audit\s*&\s*Launch'
    })
    if ($markerMatch.Count -eq 1) { return $markerMatch[0].FullName }

    if ($all.Count -eq 1) { return $all[0].FullName }
    throw "$script:Tag Could not uniquely identify current MainWindow.cs"
}

function Get-GuiProject([string]$Repo) {
    $projects = @(Get-ChildItem -LiteralPath (Join-Path $Repo 'src') -Recurse -File -Filter 'SharpEmu.GUI.csproj' -ErrorAction SilentlyContinue)
    if ($projects.Count -eq 1) { return $projects[0].FullName }
    $projects2 = @(Get-ChildItem -LiteralPath (Join-Path $Repo 'src') -Recurse -File -Filter '*.csproj' -ErrorAction SilentlyContinue |
        Where-Object { $_.BaseName -match 'GUI' })
    if ($projects2.Count -eq 1) { return $projects2[0].FullName }
    throw "$script:Tag SharpEmu GUI project could not be uniquely identified."
}
