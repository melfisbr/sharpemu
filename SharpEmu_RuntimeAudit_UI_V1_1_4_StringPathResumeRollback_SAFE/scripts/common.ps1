Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:Tag = '[RuntimeAudit UI V1.1.4]'

$script:OriginalFrontendHash = '7D9213109B2B316DB00D97339DC9F233A0ECB467777C96D79D50364565282EAD'
$script:PatchedFrontendHash  = '4B3D338DF26414AD0BEA811F99DAD9A0E24C4357D93ECE9021F52307A75DA28C'
$script:RuntimeAuditPartialHash = '017F345836B53E93DD17AB7E6C88BD7899D4E34C16BEAF1DF2A6D911EC310E72'
$script:FrontendRelativePath = 'src\SharpEmu.GUI\MainWindow.axaml.cs'
$script:GuiProjectRelativePath = 'src\SharpEmu.GUI\SharpEmu.GUI.csproj'

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

function Get-FrontendPath([string]$Repo) {
    $p = Join-Path $Repo $script:FrontendRelativePath
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw "$script:Tag Confirmed frontend source missing: $p"
    }
    $p
}

function Get-GuiProject([string]$Repo) {
    $p = Join-Path $Repo $script:GuiProjectRelativePath
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw "$script:Tag Confirmed GUI project missing: $p"
    }
    $p
}

function Find-FilePathsByHash([string]$Root, [string]$Hash, [string]$Filter = '*') {
    $matches = New-Object System.Collections.Generic.List[string]
    Get-ChildItem -LiteralPath $Root -Recurse -File -Filter $Filter -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $full = [string]$_.FullName
            if ((Get-HashSafe $full) -eq $Hash) {
                $matches.Add($full)
            }
        } catch {}
    }
    return @($matches)
}

function Find-RuntimeAuditPartialPaths([string]$Repo, [string]$Frontend) {
    $src = Join-Path $Repo 'src'
    $paths = @(Find-FilePathsByHash $src $script:RuntimeAuditPartialHash '*.cs')
    if ($paths.Count -gt 0) {
        return @($paths | Where-Object { [string]$_ -ne $Frontend })
    }

    $fallback = New-Object System.Collections.Generic.List[string]
    Get-ChildItem -LiteralPath $src -Recurse -File -Filter '*.cs' -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $full = [string]$_.FullName
            if ($full -eq $Frontend) { return }
            $t = Get-Content -LiteralPath $full -Raw
            if ($t -match 'InstallRuntimeAuditButton' -or $t -match 'Audit\s*&\s*Launch') {
                $fallback.Add($full)
            }
        } catch {}
    }
    return @($fallback)
}
