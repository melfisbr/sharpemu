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
        throw "[V72.4.3.2.31.2] Invalid repository root: $root"
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
        throw "[V72.4.3.2.31.2] Anchor missing: $Label"
    }

    $second = $Text.IndexOf(
        $Old,
        $first + $Old.Length,
        [StringComparison]::Ordinal)

    if ($second -ge 0) {
        throw "[V72.4.3.2.31.2] Anchor ambiguous: $Label"
    }

    return $Text.Substring(0,$first) +
        $New +
        $Text.Substring($first + $Old.Length)
}

function Find-RadVideo64 {
    param([string]$RepositoryRoot="")

    function Resolve-RadCandidate {
        param([string]$Candidate)

        if ([string]::IsNullOrWhiteSpace($Candidate)) {
            return $null
        }

        $candidate = $Candidate.Trim().Trim('"')

        if ((Test-Path -LiteralPath $candidate -PathType Leaf) -and
            [IO.Path]::GetFileName($candidate) -ieq "radvideo64.exe")
        {
            return (Resolve-Path -LiteralPath $candidate).Path
        }

        return $null
    }

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

    $command = Get-Command radvideo64.exe -ErrorAction SilentlyContinue

    if ($null -ne $command) {
        $resolved = Resolve-RadCandidate $command.Source
        if ($null -ne $resolved) {
            return $resolved
        }
    }

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

    # If RAD Video Tools registered itself as an application or as the .bk2
    # file handler, use that command line instead of walking the disk.
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

    foreach ($registryCommand in @(
        'Registry::HKEY_CLASSES_ROOT\Applications\radvideo64.exe\shell\open\command',
        'Registry::HKEY_CURRENT_USER\Software\Classes\Applications\radvideo64.exe\shell\open\command'
    )) {
        try {
            $commandLine = (Get-Item -LiteralPath $registryCommand -ErrorAction Stop).GetValue('')
            $resolved = Resolve-RadFromCommandLine $commandLine
            if ($null -ne $resolved) {
                return $resolved
            }
        }
        catch {
        }
    }

    foreach ($classesRoot in @(
        'Registry::HKEY_CLASSES_ROOT',
        'Registry::HKEY_CURRENT_USER\Software\Classes'
    )) {
        try {
            $extensionKey = Join-Path $classesRoot '.bk2'
            if (-not (Test-Path -LiteralPath $extensionKey)) {
                continue
            }

            $progId = (Get-Item -LiteralPath $extensionKey -ErrorAction Stop).GetValue('')
            if ([string]::IsNullOrWhiteSpace($progId)) {
                continue
            }

            $openKey = Join-Path $classesRoot ($progId + '\shell\open\command')
            if (-not (Test-Path -LiteralPath $openKey)) {
                continue
            }

            $commandLine = (Get-Item -LiteralPath $openKey -ErrorAction Stop).GetValue('')
            $resolved = Resolve-RadFromCommandLine $commandLine
            if ($null -ne $resolved) {
                return $resolved
            }
        }
        catch {
        }
    }

    $candidates = New-Object System.Collections.Generic.List[string]
    $baseCandidates = New-Object System.Collections.Generic.List[string]

    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) {
        if (-not [string]::IsNullOrWhiteSpace($base)) {
            $baseCandidates.Add($base)
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $baseCandidates.Add((Join-Path $env:LOCALAPPDATA 'Programs'))
    }

    foreach ($base in $baseCandidates) {
        foreach ($relative in @(
            "RAD Video Tools\radvideo64.exe",
            "RADGameTools\radvideo64.exe",
            "RADTools\radvideo64.exe",
            "radvideo64.exe"
        )) {
            $candidates.Add((Join-Path $base $relative))
        }
    }

    foreach ($candidate in $candidates) {
        $resolved = Resolve-RadCandidate $candidate
        if ($null -ne $resolved) {
            return $resolved
        }
    }

    # Keep discovery cheap: only inspect the root and one directory level
    # under the common portable-tool locations. Do not recursively walk the
    # whole Downloads/Desktop trees during emulator startup/build.
    $portableRoots = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        $portableRoots.Add((Join-Path $env:USERPROFILE "Downloads"))
        $portableRoots.Add((Join-Path $env:USERPROFILE "Desktop"))
    }

    foreach ($searchRoot in $portableRoots) {
        if (-not (Test-Path -LiteralPath $searchRoot -PathType Container)) {
            continue
        }

        $direct = Resolve-RadCandidate (Join-Path $searchRoot "radvideo64.exe")
        if ($null -ne $direct) {
            return $direct
        }

        try {
            $found =
                Get-ChildItem `
                    -LiteralPath $searchRoot `
                    -Directory `
                    -ErrorAction SilentlyContinue |
                ForEach-Object {
                    $candidate = Join-Path $_.FullName "radvideo64.exe"
                    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                        Get-Item -LiteralPath $candidate
                    }
                } |
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
