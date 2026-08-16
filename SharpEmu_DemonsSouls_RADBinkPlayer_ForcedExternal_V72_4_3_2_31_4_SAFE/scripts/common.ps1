Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-RepoRoot {
    param([string]$RepositoryRoot)

    if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
        $RepositoryRoot = (Get-Location).Path
    }

    $candidate = $RepositoryRoot.Trim().Trim('"').TrimEnd('\','/')
    $root = (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).Path

    if (-not (Test-Path -LiteralPath (Join-Path $root "src") -PathType Container)) {
        throw "[V72.4.3.2.31.4] Invalid repository root: $root"
    }

    return $root
}

function Read-Normalized {
    param([string]$Path)
    return [IO.File]::ReadAllText($Path).Replace("`r`n","`n").Replace("`r","`n")
}

function Get-TextFormat {
    param([string]$Path)

    $bytes = [IO.File]::ReadAllBytes($Path)
    $bom = $false

    if ($bytes.Length -ge 3) {
        $bom =
            $bytes[0] -eq 0xEF -and
            $bytes[1] -eq 0xBB -and
            $bytes[2] -eq 0xBF
    }

    $raw = [IO.File]::ReadAllText($Path)
    $nl = if ($raw.Contains("`r`n")) { "`r`n" } else { "`n" }

    return [pscustomobject]@{
        HasBom = $bom
        NewLine = $nl
    }
}

function Write-Normalized {
    param([string]$Path,[string]$Text,$Format)

    $enc = New-Object Text.UTF8Encoding([bool]$Format.HasBom)
    [IO.File]::WriteAllText(
        $Path,
        $Text.Replace("`n",$Format.NewLine),
        $enc)
}

function Replace-ExactOnce {
    param([string]$Text,[string]$Old,[string]$New,[string]$Label)

    $first = $Text.IndexOf($Old,[StringComparison]::Ordinal)

    if ($first -lt 0) {
        throw "[V72.4.3.2.31.4] Anchor missing: $Label"
    }

    $second = $Text.IndexOf(
        $Old,
        $first + $Old.Length,
        [StringComparison]::Ordinal)

    if ($second -ge 0) {
        throw "[V72.4.3.2.31.4] Anchor ambiguous: $Label"
    }

    return $Text.Substring(0,$first) +
        $New +
        $Text.Substring($first + $Old.Length)
}

function Replace-ExactLastBefore {
    param(
        [string]$Text,
        [string]$Old,
        [string]$Before,
        [string]$New,
        [string]$Label)

    $beforeIndex = $Text.IndexOf($Before,[StringComparison]::Ordinal)
    if ($beforeIndex -lt 0) {
        throw "[V72.4.3.2.31.4] Structural marker missing before: $Label"
    }

    $prefix = $Text.Substring(0,$beforeIndex)
    $index = $prefix.LastIndexOf($Old,[StringComparison]::Ordinal)
    if ($index -lt 0) {
        throw "[V72.4.3.2.31.4] Anchor missing before structural marker: $Label"
    }

    return $Text.Substring(0,$index) +
        $New +
        $Text.Substring($index + $Old.Length)
}

function Replace-AllExact {
    param(
        [string]$Text,
        [string]$Old,
        [string]$New,
        [string]$Label,
        [int]$MinimumCount=1)

    $count = 0
    $cursor = 0
    while (($index = $Text.IndexOf($Old,$cursor,[StringComparison]::Ordinal)) -ge 0) {
        $Text = $Text.Substring(0,$index) +
            $New +
            $Text.Substring($index + $Old.Length)
        $cursor = $index + $New.Length
        $count++
    }

    if ($count -lt $MinimumCount) {
        throw "[V72.4.3.2.31.4] Anchor missing: $Label"
    }

    return [pscustomobject]@{
        Text = $Text
        Count = $count
    }
}

function Resolve-RadCandidate {
    param([string]$Candidate)

    if ([string]::IsNullOrWhiteSpace($Candidate)) {
        return $null
    }

    $candidate = $Candidate.Trim().Trim('"')

    try {
        if ((Test-Path -LiteralPath $candidate -PathType Leaf) -and
            [IO.Path]::GetFileName($candidate) -ieq "radvideo64.exe")
        {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    catch {
    }

    return $null
}

function Resolve-RadFromCommandLine {
    param([string]$CommandLine)

    if ([string]::IsNullOrWhiteSpace($CommandLine)) {
        return $null
    }

    $match = [regex]::Match(
        $CommandLine,
        '(?i)(?:"(?<q>[^"\r\n]*radvideo64\.exe)"|(?<u>[^\s"\r\n]*radvideo64\.exe))')

    if (-not $match.Success) {
        return $null
    }

    $value = if ($match.Groups['q'].Success) {
        $match.Groups['q'].Value
    } else {
        $match.Groups['u'].Value
    }

    return Resolve-RadCandidate $value
}

function Find-RadVideo64 {
    param(
        [string]$RepositoryRoot="",
        [switch]$DeepSearch)

    # 1) Explicit override and SharpEmu path cache.
    $resolved = Resolve-RadCandidate $env:SHARPEMU_RADVIDEO64
    if ($null -ne $resolved) {
        return $resolved
    }

    if (-not [string]::IsNullOrWhiteSpace($RepositoryRoot)) {
        try {
            $config =
                Join-Path $RepositoryRoot `
                    "artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\radvideo64.path"

            if (Test-Path -LiteralPath $config -PathType Leaf) {
                $resolved =
                    Resolve-RadCandidate ([IO.File]::ReadAllText($config))
                if ($null -ne $resolved) {
                    return $resolved
                }
            }
        }
        catch {
        }
    }

    # 2) PATH / App Paths.
    $command = Get-Command radvideo64.exe -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        $resolved = Resolve-RadCandidate $command.Source
        if ($null -ne $resolved) {
            return $resolved
        }
    }

    foreach ($appPath in @(
        'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\App Paths\radvideo64.exe',
        'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\radvideo64.exe',
        'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\radvideo64.exe'
    )) {
        try {
            if (Test-Path -LiteralPath $appPath) {
                $value = (Get-Item -LiteralPath $appPath -ErrorAction Stop).GetValue('')
                $resolved = Resolve-RadCandidate $value
                if ($null -ne $resolved) {
                    return $resolved
                }
            }
        }
        catch {
        }
    }

    # 3) Running process.
    try {
        $running =
            Get-CimInstance Win32_Process `
                -Filter "Name='radvideo64.exe'" `
                -ErrorAction SilentlyContinue |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace($_.ExecutablePath)
            } |
            Select-Object -First 1

        if ($null -ne $running) {
            $resolved = Resolve-RadCandidate $running.ExecutablePath
            if ($null -ne $resolved) {
                return $resolved
            }
        }
    }
    catch {
    }

    # 4) Registered application commands.
    foreach ($registryCommand in @(
        'Registry::HKEY_CLASSES_ROOT\Applications\radvideo64.exe\shell\open\command',
        'Registry::HKEY_CURRENT_USER\Software\Classes\Applications\radvideo64.exe\shell\open\command'
    )) {
        try {
            if (Test-Path -LiteralPath $registryCommand) {
                $commandLine = (Get-Item -LiteralPath $registryCommand -ErrorAction Stop).GetValue('')
                $resolved = Resolve-RadFromCommandLine $commandLine
                if ($null -ne $resolved) {
                    return $resolved
                }
            }
        }
        catch {
        }
    }

    # 5) Modern .bk2 association: UserChoice ProgId + classic ProgId.
    $progIds = New-Object System.Collections.Generic.List[string]

    foreach ($assocKey in @(
        'Registry::HKEY_CLASSES_ROOT\.bk2',
        'Registry::HKEY_CURRENT_USER\Software\Classes\.bk2'
    )) {
        try {
            if (Test-Path -LiteralPath $assocKey) {
                $value = (Get-Item -LiteralPath $assocKey -ErrorAction Stop).GetValue('')
                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    $progIds.Add([string]$value)
                }
            }
        }
        catch {
        }
    }

    try {
        $userChoice =
            'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.bk2\UserChoice'
        if (Test-Path -LiteralPath $userChoice) {
            $value =
                (Get-ItemProperty -LiteralPath $userChoice -Name ProgId -ErrorAction Stop).ProgId
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                $progIds.Add([string]$value)
            }
        }
    }
    catch {
    }

    foreach ($progId in ($progIds | Select-Object -Unique)) {
        foreach ($classesRoot in @(
            'Registry::HKEY_CLASSES_ROOT',
            'Registry::HKEY_CURRENT_USER\Software\Classes'
        )) {
            try {
                $openKey =
                    Join-Path $classesRoot ($progId + '\shell\open\command')
                if (Test-Path -LiteralPath $openKey) {
                    $commandLine =
                        (Get-Item -LiteralPath $openKey -ErrorAction Stop).GetValue('')
                    $resolved = Resolve-RadFromCommandLine $commandLine
                    if ($null -ne $resolved) {
                        return $resolved
                    }
                }
            }
            catch {
            }
        }
    }

    # 6) Installed-program records. Use InstallLocation/DisplayIcon if available.
    foreach ($uninstallRoot in @(
        'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )) {
        try {
            if (-not (Test-Path -LiteralPath $uninstallRoot)) {
                continue
            }

            foreach ($entry in Get-ChildItem -LiteralPath $uninstallRoot -ErrorAction SilentlyContinue) {
                $props = Get-ItemProperty -LiteralPath $entry.PSPath -ErrorAction SilentlyContinue
                if ($null -eq $props) {
                    continue
                }

                $displayName = [string]$props.DisplayName
                if ($displayName -notmatch '(?i)\bRAD\b|Bink') {
                    continue
                }

                $resolved = Resolve-RadFromCommandLine ([string]$props.DisplayIcon)
                if ($null -ne $resolved) {
                    return $resolved
                }

                $installLocation = [string]$props.InstallLocation
                if (-not [string]::IsNullOrWhiteSpace($installLocation) -and
                    (Test-Path -LiteralPath $installLocation -PathType Container))
                {
                    $direct = Resolve-RadCandidate (Join-Path $installLocation 'radvideo64.exe')
                    if ($null -ne $direct) {
                        return $direct
                    }

                    $found =
                        Get-ChildItem -LiteralPath $installLocation `
                            -Filter radvideo64.exe -File -Recurse `
                            -ErrorAction SilentlyContinue |
                        Select-Object -First 1
                    if ($null -ne $found) {
                        return $found.FullName
                    }
                }
            }
        }
        catch {
        }
    }

    # 7) Known direct locations.
    $bases = @(
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $env:LOCALAPPDATA
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($base in $bases) {
        foreach ($relative in @(
            'RAD Video Tools\radvideo64.exe',
            'RADGameTools\radvideo64.exe',
            'RADTools\radvideo64.exe',
            'Programs\RAD Video Tools\radvideo64.exe',
            'Programs\RADGameTools\radvideo64.exe',
            'radvideo64.exe'
        )) {
            $resolved = Resolve-RadCandidate (Join-Path $base $relative)
            if ($null -ne $resolved) {
                return $resolved
            }
        }
    }

    if (-not $DeepSearch) {
        return $null
    }

    # 8) Start-menu shortcuts.
    try {
        $shell = New-Object -ComObject WScript.Shell
        $startRoots = @(
            [Environment]::GetFolderPath('StartMenu'),
            [Environment]::GetFolderPath('CommonStartMenu')
        ) | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_) -and
            (Test-Path -LiteralPath $_ -PathType Container)
        }

        foreach ($startRoot in $startRoots) {
            foreach ($lnk in Get-ChildItem -LiteralPath $startRoot -Filter *.lnk -File -Recurse -ErrorAction SilentlyContinue) {
                try {
                    $shortcut = $shell.CreateShortcut($lnk.FullName)
                    $resolved = Resolve-RadCandidate $shortcut.TargetPath
                    if ($null -ne $resolved) {
                        return $resolved
                    }
                }
                catch {
                }
            }
        }
    }
    catch {
    }

    # 9) Recursive user/tool locations. V31/V31.1/V31.2 only searched one
    # directory level, which misses the usual extracted RADTools.7z layout.
    $searchRoots = New-Object System.Collections.Generic.List[string]

    if (-not [string]::IsNullOrWhiteSpace($RepositoryRoot)) {
        $searchRoots.Add($RepositoryRoot)
        $toolRoot = Join-Path $RepositoryRoot '.sharpemu-tools'
        if (Test-Path -LiteralPath $toolRoot -PathType Container) {
            $searchRoots.Add($toolRoot)
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        foreach ($name in @('Downloads','Desktop','Documents')) {
            $candidate = Join-Path $env:USERPROFILE $name
            if (Test-Path -LiteralPath $candidate -PathType Container) {
                $searchRoots.Add($candidate)
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $candidate = Join-Path $env:LOCALAPPDATA 'Programs'
        if (Test-Path -LiteralPath $candidate -PathType Container) {
            $searchRoots.Add($candidate)
        }
    }

    foreach ($searchRoot in ($searchRoots | Select-Object -Unique)) {
        try {
            $found =
                Get-ChildItem -LiteralPath $searchRoot `
                    -Filter radvideo64.exe `
                    -File `
                    -Recurse `
                    -ErrorAction SilentlyContinue |
                Select-Object -First 1

            if ($null -ne $found) {
                return $found.FullName
            }
        }
        catch {
        }
    }

    return $null
}

function Write-RadDiscoveryReport {
    param(
        [string]$RepositoryRoot,
        [string]$RadPath)

    $path =
        Join-Path $RepositoryRoot 'RAD_DISCOVERY_V72_4_3_2_31_4.txt'

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('SharpEmu V72.4.3.2.31.4 RAD discovery')
    $lines.Add('==========================================')
    $lines.Add(('Timestamp=' + (Get-Date -Format 'o')))
    $lines.Add(('SHARPEMU_RADVIDEO64=' + [string]$env:SHARPEMU_RADVIDEO64))
    $lines.Add(('RAD_FOUND=' + (-not [string]::IsNullOrWhiteSpace($RadPath))))
    $lines.Add(('RAD_PATH=' + $(if ([string]::IsNullOrWhiteSpace($RadPath)) { '<not found>' } else { $RadPath })))
    if (-not [string]::IsNullOrWhiteSpace($RadPath)) {
        try {
            $item = Get-Item -LiteralPath $RadPath -ErrorAction Stop
            $lines.Add(('RAD_LENGTH=' + $item.Length))
            $lines.Add(('RAD_VERSION=' + $item.VersionInfo.FileVersion))
            $lines.Add(('RAD_SHA256=' + (Get-FileHash -LiteralPath $RadPath -Algorithm SHA256).Hash))
        }
        catch {
        }
    }
    $lines.Add('')
    $lines.Add('Discovery checked: env/config/PATH/App Paths/running process/.bk2 association/uninstall records/Start Menu and recursive user/tool folders.')
    $lines.Add('Official command expected by this package: radvideo64.exe binkplay <movie.bk2> /#.')
    $lines.Add('This package intentionally DOES NOT fall back to NIHAV when RAD-required mode is selected.')

    [IO.File]::WriteAllLines(
        $path,
        [string[]]$lines,
        (New-Object Text.UTF8Encoding($true)))

    return $path
}
