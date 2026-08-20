Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:Tag = '[RuntimeAudit UI V1.1.3]'

$script:OriginalFrontendHash = '7D9213109B2B316DB00D97339DC9F233A0ECB467777C96D79D50364565282EAD'
$script:PatchedFrontendHash  = '4B3D338DF26414AD0BEA811F99DAD9A0E24C4357D93ECE9021F52307A75DA28C'
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

function Find-PatchedFrontendSource([string]$Repo) {
    $src = Join-Path $Repo 'src'

    # Strongest signal: exact SHA recorded by V1.1 after patch.
    $hashMatches = @(Find-FileByHash $src $script:PatchedFrontendHash '*.cs')
    if ($hashMatches.Count -eq 1) { return $hashMatches[0] }
    if ($hashMatches.Count -gt 1) {
        throw "$script:Tag Multiple frontend files match patched SHA256; refusing ambiguous rollback."
    }

    # Next: exact RuntimeAudit hook marker inside a C# source file.
    $hookMatches = New-Object System.Collections.Generic.List[string]
    Get-ChildItem -LiteralPath $src -Recurse -File -Filter '*.cs' -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $t = Get-Content -LiteralPath $_.FullName -Raw
            if ($t -match 'InstallRuntimeAuditButton' -or $t -match 'Audit\s*&\s*Launch') {
                $hookMatches.Add($_.FullName)
            }
        } catch {}
    }
    if ($hookMatches.Count -eq 1) { return $hookMatches[0] }

    # If the patch was already partially rolled back, accept the exact pre-patch SHA.
    $origMatches = @(Find-FileByHash $src $script:OriginalFrontendHash '*.cs')
    if ($origMatches.Count -eq 1) { return $origMatches[0] }

    # Last structural fallback: a unique GUI source declaring MainWindow.
    $classMatches = New-Object System.Collections.Generic.List[string]
    Get-ChildItem -LiteralPath $src -Recurse -File -Filter '*.cs' -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $t = Get-Content -LiteralPath $_.FullName -Raw
            if ($t -match '(?m)^\s*(public|internal)?\s*(partial\s+)?class\s+MainWindow\b') {
                $classMatches.Add($_.FullName)
            }
        } catch {}
    }
    if ($classMatches.Count -eq 1) { return $classMatches[0] }

    throw "$script:Tag Unable to uniquely identify frontend source. patchedHashMatches=$($hashMatches.Count) hookMatches=$($hookMatches.Count) originalHashMatches=$($origMatches.Count) MainWindowClassMatches=$($classMatches.Count)"
}

function Find-OriginalFrontendBackup([string]$Backup) {
    $matches = @(Find-FileByHash $Backup $script:OriginalFrontendHash '*')
    if ($matches.Count -eq 1) { return $matches[0] }
    if ($matches.Count -gt 1) {
        # Prefer source-looking files if backup contains duplicate metadata copies.
        $cs = @($matches | Where-Object { $_ -like '*.cs' })
        if ($cs.Count -eq 1) { return $cs[0] }
    }
    throw "$script:Tag Expected one original frontend file with SHA256 $($script:OriginalFrontendHash) in backup; found $($matches.Count)."
}

function Get-GuiProject([string]$Repo) {
    $projects = @(Get-ChildItem -LiteralPath (Join-Path $Repo 'src') -Recurse -File -Filter 'SharpEmu.GUI.csproj' -ErrorAction SilentlyContinue)
    if ($projects.Count -eq 1) { return $projects[0].FullName }

    $projects2 = @(Get-ChildItem -LiteralPath (Join-Path $Repo 'src') -Recurse -File -Filter '*.csproj' -ErrorAction SilentlyContinue |
        Where-Object {
            try {
                $t = Get-Content -LiteralPath $_.FullName -Raw
                $_.BaseName -match 'GUI' -or $t -match '<AssemblyName>\s*SharpEmu\.GUI\s*</AssemblyName>'
            } catch { $false }
        })
    if ($projects2.Count -eq 1) { return $projects2[0].FullName }

    throw "$script:Tag SharpEmu GUI project could not be uniquely identified. candidates=$($projects2.Count)"
}
