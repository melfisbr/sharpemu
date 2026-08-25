Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PackageRoot = Split-Path -Parent $PSScriptRoot
$PackageTag = 'V76.2.4.6-BINK-GUEST-YUV-INTEGER-SAMPLER-SPLITPATH-COMPLETE-GUARD'
$DefaultPatchesRoot = 'C:\Users\Edpo\Documents\GitHub\sharpemu\Patches'
$TargetPackageName = 'SharpEmu_V76_2_4_1_BinkGuestYuvIntegerSamplerFix_ValidatorPathFix_SAFE'
$TargetRunnerName = 'RUN_2_PATCH_AND_REVALIDATE_V76_2_4.cmd'
$GuardMarker = '# V76.2.4.6_SAFE_SPLIT_PATH_GUARD'
$GuardFunctionName = 'Invoke-SafeSplitPathV76246'

function Get-PatchesRoot([string]$PatchesRoot = $DefaultPatchesRoot) {
    if ([string]::IsNullOrWhiteSpace($PatchesRoot)) { $PatchesRoot = $DefaultPatchesRoot }
    $resolved = [System.IO.Path]::GetFullPath($PatchesRoot)
    if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
        throw "PatchesRoot ausente: $resolved"
    }
    return $resolved
}

function Get-TargetPackage([string]$PatchesRoot = $DefaultPatchesRoot) {
    $root = Get-PatchesRoot $PatchesRoot
    $target = Join-Path $root $TargetPackageName
    if (-not (Test-Path -LiteralPath $target -PathType Container)) {
        throw "Pacote-alvo ausente: $target"
    }
    return $target
}

function Get-TargetRunner([string]$TargetPackage) {
    $runner = Join-Path $TargetPackage $TargetRunnerName
    if (-not (Test-Path -LiteralPath $runner -PathType Leaf)) {
        throw "Runner alvo ausente: $runner"
    }
    return $runner
}

function Get-ScriptFiles([string]$TargetPackage) {
    return @(Get-ChildItem -LiteralPath $TargetPackage -Filter '*.ps1' -File -Recurse | Sort-Object FullName)
}

function Get-RelativeTargetPath([string]$TargetPackage, [string]$Path) {
    $targetFull = [System.IO.Path]::GetFullPath($TargetPackage).TrimEnd('\\') + '\\'
    $pathFull = [System.IO.Path]::GetFullPath($Path)
    if (-not $pathFull.StartsWith($targetFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path fora do pacote-alvo: $pathFull"
    }
    return $pathFull.Substring($targetFull.Length)
}

function Get-SplitPathCommandSpans([string]$ScriptPath) {
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $ScriptPath,
        [ref]$tokens,
        [ref]$parseErrors)
    if (@($parseErrors).Count -ne 0) {
        $messages = @($parseErrors | ForEach-Object { $_.Message }) -join '; '
        throw "PowerShell parse failed antes do patch: $ScriptPath :: $messages"
    }
    $commands = @($ast.FindAll({
        param($node)
        if ($node -isnot [System.Management.Automation.Language.CommandAst]) { return $false }
        $name = $node.GetCommandName()
        return -not [string]::IsNullOrWhiteSpace($name) -and
            $name.Equals('Split-Path', [System.StringComparison]::OrdinalIgnoreCase)
    }, $true))
    $spans = @()
    foreach ($command in $commands) {
        if ($command.CommandElements.Count -lt 1) { continue }
        $extent = $command.CommandElements[0].Extent
        $spans += [pscustomobject]@{
            Start = $extent.StartOffset
            End = $extent.EndOffset
            Text = $extent.Text
            Line = $extent.StartLineNumber
        }
    }
    return @($spans)
}

function Get-SafeSplitPathGuardText {
    return @'
# V76.2.4.6_SAFE_SPLIT_PATH_GUARD
# Package-script-only compatibility wrapper. It absorbs stray $null positional
# arguments and turns an actually-null path into $null instead of throwing.
function Invoke-SafeSplitPathV76246 {
    $rawArgumentsV76246 = @($args)
    if ($rawArgumentsV76246.Count -eq 0) {
        return $null
    }

    $filteredArgumentsV76246 = [System.Collections.Generic.List[object]]::new()
    foreach ($argumentV76246 in $rawArgumentsV76246) {
        if ($null -ne $argumentV76246) {
            [void]$filteredArgumentsV76246.Add($argumentV76246)
        }
    }

    if ($filteredArgumentsV76246.Count -eq 0) {
        return $null
    }

    # A command containing only switches (for example '-Parent' after a null
    # path was removed) has no usable path and should simply yield no parent.
    $hasPathArgumentV76246 = $false
    foreach ($argumentV76246 in $filteredArgumentsV76246) {
        if ($argumentV76246 -is [string] -and
            $argumentV76246.StartsWith('-', [System.StringComparison]::Ordinal)) {
            continue
        }
        $hasPathArgumentV76246 = $true
        break
    }
    if (-not $hasPathArgumentV76246) {
        return $null
    }

    return & Microsoft.PowerShell.Management\Split-Path @($filteredArgumentsV76246.ToArray())
}

'@
}

function Repair-SplitPathCommands([string]$ScriptPath) {
    $original = [System.IO.File]::ReadAllText($ScriptPath)
    $spans = @(Get-SplitPathCommandSpans $ScriptPath)
    $changed = $false
    $patched = $original

    if ($spans.Count -gt 0) {
        foreach ($span in @($spans | Sort-Object Start -Descending)) {
            $patched = $patched.Substring(0, $span.Start) +
                $GuardFunctionName +
                $patched.Substring($span.End)
        }
        $changed = $true
    }

    if ($changed -and $patched.IndexOf($GuardMarker, [System.StringComparison]::Ordinal) -lt 0) {
        $patched = (Get-SafeSplitPathGuardText) + $patched
    }

    if ($changed) {
        [System.IO.File]::WriteAllText(
            $ScriptPath,
            $patched,
            [System.Text.UTF8Encoding]::new($false))
    }

    # Parse the resulting script and verify no raw Split-Path command remains.
    $remaining = @(Get-SplitPathCommandSpans $ScriptPath)
    if ($remaining.Count -ne 0) {
        throw "Split-Path raw remanescente apos repair: $ScriptPath count=$($remaining.Count)"
    }

    return [pscustomobject]@{
        Changed = $changed
        Replacements = $spans.Count
    }
}

function Update-TargetManifest([string]$TargetPackage, [string[]]$ModifiedFiles) {
    $manifest = Join-Path $TargetPackage 'manifest.sha256'
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
        return [pscustomobject]@{ Exists = $false; Updated = 0; Path = $manifest }
    }

    $modifiedByRelative = @{}
    foreach ($file in $ModifiedFiles) {
        $relative = (Get-RelativeTargetPath $TargetPackage $file).Replace('/', '\\')
        $modifiedByRelative[$relative.ToLowerInvariant()] = $file
    }

    $lines = @(Get-Content -LiteralPath $manifest)
    $updated = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $match = [regex]::Match($line, '^(?<hash>[0-9A-Fa-f]{64})(?<separator>\s+\*?)(?<path>.+?)\s*$')
        if (-not $match.Success) { continue }
        $listed = $match.Groups['path'].Value.Trim().Replace('/', '\\')
        $key = $listed.ToLowerInvariant()
        if (-not $modifiedByRelative.ContainsKey($key)) { continue }
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $modifiedByRelative[$key]).Hash.ToLowerInvariant()
        $lines[$i] = $hash + $match.Groups['separator'].Value + $match.Groups['path'].Value
        $updated++
    }

    Set-Content -LiteralPath $manifest -Value $lines -Encoding UTF8
    return [pscustomobject]@{ Exists = $true; Updated = $updated; Path = $manifest }
}

function Test-TargetManifest([string]$TargetPackage) {
    $manifest = Join-Path $TargetPackage 'manifest.sha256'
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { return $true }
    $bad = @()
    foreach ($line in @(Get-Content -LiteralPath $manifest)) {
        $match = [regex]::Match($line, '^(?<hash>[0-9A-Fa-f]{64})\s+\*?(?<path>.+?)\s*$')
        if (-not $match.Success) { continue }
        $relative = $match.Groups['path'].Value.Trim().Replace('/', '\\')
        $file = Join-Path $TargetPackage $relative
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
            $bad += "missing:$relative"
            continue
        }
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $file).Hash.ToLowerInvariant()
        if ($actual -ne $match.Groups['hash'].Value.ToLowerInvariant()) {
            $bad += "hash:$relative"
        }
    }
    if ($bad.Count -ne 0) {
        throw "Target manifest mismatch: $($bad -join ', ')"
    }
    return $true
}
