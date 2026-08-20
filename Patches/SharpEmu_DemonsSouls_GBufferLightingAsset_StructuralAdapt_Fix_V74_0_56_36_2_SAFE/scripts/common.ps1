Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Tag = '[V74.0.56.36.2]'
$script:EbootSha256 = '22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E'
$script:AgcRelative = 'src\SharpEmu.Libs\Agc\AgcExports.cs'
$script:PresenterRelative = 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$script:AgcMarker = 'SHARPEMU_V74_0_56_36_DS_GBUFFER_LIGHTING_CONTRACT'
$script:PresenterMarker = 'SHARPEMU_V74_0_56_36_2_DCC_INITIALIZED_ADDRESS_GUARD'

function Resolve-RepoV74056362([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = (Get-Location).Path
    }

    $current = [IO.Path]::GetFullPath(
        ($Path.Trim().Trim('"') -replace '[\r\n]+$', '')
    )

    if (-not (Test-Path -LiteralPath $current -PathType Container)) {
        throw ('{0} path missing: {1}' -f $script:Tag, $current)
    }

    for ($depth = 0; $depth -le 6; $depth++) {
        if ((Test-Path -LiteralPath (Join-Path $current 'src') -PathType Container) -and
            (Test-Path -LiteralPath (Join-Path $current 'Patches') -PathType Container)) {
            return $current
        }

        $parent = Split-Path -Parent $current

        if ([string]::IsNullOrWhiteSpace($parent) -or
            $parent -eq $current) {
            break
        }

        $current = $parent
    }

    throw ('{0} repository root not found' -f $script:Tag)
}

function Normalize-LfV74056362([string]$Text) {
    return $Text.Replace("`r`n", "`n").Replace("`r", "`n")
}

function Count-TextV74056362([string]$Text, [string]$Needle) {
    $count = 0
    $position = 0

    while ($true) {
        $index = $Text.IndexOf(
            $Needle,
            $position,
            [StringComparison]::Ordinal
        )

        if ($index -lt 0) {
            break
        }

        $count++
        $position = $index + $Needle.Length
    }

    return $count
}

function Read-PatchV74056362([string]$Name) {
    $root = Split-Path -Parent $PSScriptRoot

    return Normalize-LfV74056362(
        [IO.File]::ReadAllText(
            (Join-Path $root ('patch\' + $Name))
        )
    )
}

function Get-ShaV74056362([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Assert-EbootV74056362([string]$Eboot) {
    if (-not (Test-Path -LiteralPath $Eboot -PathType Leaf)) {
        throw ('{0} EBOOT missing: {1}' -f $script:Tag, $Eboot)
    }

    $hash = Get-ShaV74056362 $Eboot

    if ($hash -ne $script:EbootSha256) {
        throw ('{0} EBOOT hash mismatch: {1}' -f $script:Tag, $hash)
    }

    return $hash
}

function Assert-CumulativeV74056362([string]$Repo) {
    $agcPath = Join-Path $Repo $script:AgcRelative
    $presenterPath = Join-Path $Repo $script:PresenterRelative
    $shaderPath = Join-Path $Repo 'src\SharpEmu.ShaderCompiler\Gen5ShaderTranslator.cs'

    foreach ($path in @($agcPath, $presenterPath, $shaderPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw ('{0} prerequisite source missing: {1}' -f $script:Tag, $path)
        }
    }

    $agcText = [IO.File]::ReadAllText($agcPath)

    foreach ($marker in @(
        'SHARPEMU_V74_0_56_35_DCC_FASTCLEAR_IMMEDIATE_MATERIALIZATION',
        'Rdna2DccCompressionEnableMaskV7405634',
        'SHARPEMU_V74_0_56_32_DEFER_DCC_TO_GPU_METADATA',
        'SHARPEMU_V74_0_56_30_SHADER_DRIVEN_LAYERED_UPLOAD',
        'SHARPEMU_V74_0_56_29_GBUFFER_OUTPUT_CONTRACT'
    )) {
        if ($agcText.IndexOf($marker, [StringComparison]::Ordinal) -lt 0) {
            throw ('{0} AGC prerequisite missing: {1}' -f $script:Tag, $marker)
        }
    }

    $presenterText = [IO.File]::ReadAllText($presenterPath)

    foreach ($marker in @(
        'SHARPEMU_V74_0_56_32_DCC_METADATA_ALIAS',
        'SHARPEMU_V74_0_73_SAMPLER_IMAGE_ALIAS'
    )) {
        if ($presenterText.IndexOf($marker, [StringComparison]::Ordinal) -lt 0) {
            throw ('{0} Presenter prerequisite missing: {1}' -f $script:Tag, $marker)
        }
    }

    $shaderText = [IO.File]::ReadAllText($shaderPath)

    if ($shaderText.IndexOf(
            'SHARPEMU_V74_0_56_30_MIMG_ARRAY_IDENTITY',
            [StringComparison]::Ordinal) -lt 0) {
        throw ('{0} V56.30 shader prerequisite missing.' -f $script:Tag)
    }
}

function Get-AgcStateV74056362([string]$Repo) {
    $path = Join-Path $Repo $script:AgcRelative
    $text = Normalize-LfV74056362([IO.File]::ReadAllText($path))

    foreach ($equivalent in @(
        'SHARPEMU_V74_0_56_36_DS_GBUFFER_LIGHTING_CONTRACT',
        'SHARPEMU_V74_0_76_1_DS_GBUFFER_PS_CONTRACT'
    )) {
        if ($text.IndexOf($equivalent, [StringComparison]::Ordinal) -ge 0) {
            return [pscustomobject]@{
                State = 'Applied'
                Ready = 0
                Problems = ''
            }
        }
    }

    $parts = @(
        @('AgcExports.fields.anchor.txt', 'fields'),
        @('AgcExports.gbuffer.anchor.txt', 'gbuffer')
    )

    $ready = 0
    $problems = @()

    foreach ($entry in $parts) {
        $anchor = Read-PatchV74056362 $entry[0]
        $count = Count-TextV74056362 $text $anchor

        if ($count -eq 1) {
            $ready++
        }
        else {
            $problems += ('{0}={1}' -f $entry[1], $count)
        }
    }

    if ($problems.Count -ne 0) {
        return [pscustomobject]@{
            State = 'Divergent'
            Ready = $ready
            Problems = ($problems -join ',')
        }
    }

    return [pscustomobject]@{
        State = 'Ready'
        Ready = $ready
        Problems = ''
    }
}

function Get-PresenterConsiderMatchV74056362([string]$Text) {
    $pattern =
        'void\s+Consider\s*\(\s*GuestImageResource\s+candidate\s*,\s*bool\s+isActive\s*\)\s*\{'

    $matches = [regex]::Matches(
        $Text,
        $pattern,
        [Text.RegularExpressions.RegexOptions]::Singleline
    )

    if ($matches.Count -eq 1) {
        return $matches[0]
    }

    return $null
}

function Has-EquivalentPresenterGuardV74056362([string]$Text) {
    foreach ($marker in @(
        'SHARPEMU_V74_0_56_36_2_DCC_INITIALIZED_ADDRESS_GUARD',
        'SHARPEMU_V74_0_56_36_1_DCC_INITIALIZED_ADDRESS_GUARD',
        'SHARPEMU_V74_0_56_36_DCC_INITIALIZED_ADDRESS_GUARD',
        'SHARPEMU_V74_0_76_DCC_INITIALIZED_ALIAS_GUARD',
        'SHARPEMU_V74_0_76_1_DCC_UNINITIALIZED_ADDRESS_GUARD'
    )) {
        if ($Text.IndexOf($marker, [StringComparison]::Ordinal) -ge 0) {
            return $true
        }
    }

    $match = Get-PresenterConsiderMatchV74056362 $Text

    if ($null -eq $match) {
        return $false
    }

    $start = $match.Index
    $length = [Math]::Min(3000, $Text.Length - $start)
    $window = $Text.Substring($start, $length)

    return (
        $window.IndexOf(
            'texture.GpuReferenceOnly',
            [StringComparison]::Ordinal
        ) -ge 0 -and
        $window.IndexOf(
            '!candidate.Initialized',
            [StringComparison]::Ordinal
        ) -ge 0
    )
}

function Get-PresenterStateV74056362([string]$Repo) {
    $path = Join-Path $Repo $script:PresenterRelative
    $text = Normalize-LfV74056362([IO.File]::ReadAllText($path))

    if (Has-EquivalentPresenterGuardV74056362 $text) {
        return [pscustomobject]@{
            State = 'Satisfied'
            ConsiderCount = 1
            Problems = ''
        }
    }

    $match = Get-PresenterConsiderMatchV74056362 $text

    if ($null -ne $match) {
        return [pscustomobject]@{
            State = 'Ready'
            ConsiderCount = 1
            Problems = ''
        }
    }

    $pattern =
        'void\s+Consider\s*\(\s*GuestImageResource\s+candidate\s*,\s*bool\s+isActive\s*\)\s*\{'

    $count = [regex]::Matches(
        $text,
        $pattern,
        [Text.RegularExpressions.RegexOptions]::Singleline
    ).Count

    return [pscustomobject]@{
        State = 'Divergent'
        ConsiderCount = $count
        Problems = ('structural-consider-count={0}' -f $count)
    }
}

function Apply-AgcV74056362([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)

    $hadBom =
        $bytes.Length -ge 3 -and
        $bytes[0] -eq 0xEF -and
        $bytes[1] -eq 0xBB -and
        $bytes[2] -eq 0xBF

    $raw = [IO.File]::ReadAllText($Path)

    $useCrLf =
        [regex]::Matches($raw, "`r`n").Count -gt
        ([regex]::Matches($raw, "`n").Count / 2)

    $text = Normalize-LfV74056362 $raw

    $fieldAnchor = Read-PatchV74056362 'AgcExports.fields.anchor.txt'
    $fieldReplace = Read-PatchV74056362 'AgcExports.fields.replace.txt'
    $gbufferAnchor = Read-PatchV74056362 'AgcExports.gbuffer.anchor.txt'
    $gbufferReplace = Read-PatchV74056362 'AgcExports.gbuffer.replace.txt'

    foreach ($pair in @(
        @($fieldAnchor, $fieldReplace, 'fields'),
        @($gbufferAnchor, $gbufferReplace, 'gbuffer')
    )) {
        $count = Count-TextV74056362 $text $pair[0]

        if ($count -ne 1) {
            $messageV74056362 = '{0} AGC {1} anchor count={2}' -f $script:Tag, $pair[2], $count
            throw $messageV74056362
        }

        $text = $text.Replace($pair[0], $pair[1])
    }

    $output = if ($useCrLf) {
        $text.Replace("`n", "`r`n")
    }
    else {
        $text
    }

    [IO.File]::WriteAllText(
        $Path,
        $output,
        (New-Object System.Text.UTF8Encoding($hadBom))
    )
}

function Apply-PresenterGuardV74056362([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)

    $hadBom =
        $bytes.Length -ge 3 -and
        $bytes[0] -eq 0xEF -and
        $bytes[1] -eq 0xBB -and
        $bytes[2] -eq 0xBF

    $raw = [IO.File]::ReadAllText($Path)

    if (Has-EquivalentPresenterGuardV74056362 $raw) {
        return $false
    }

    $match = Get-PresenterConsiderMatchV74056362 $raw

    if ($null -eq $match) {
        $messageV74056362 = '{0} Presenter structural Consider method not uniquely found.' -f $script:Tag
        throw $messageV74056362
    }

    $useCrLf =
        [regex]::Matches($raw, "`r`n").Count -gt
        ([regex]::Matches($raw, "`n").Count / 2)

    $newline = if ($useCrLf) { "`r`n" } else { "`n" }

    $packageRootV74056362 = Split-Path -Parent $PSScriptRoot
    $insertionPathV74056362 = Join-Path `
        -Path $packageRootV74056362 `
        -ChildPath 'patch\VulkanVideoPresenter.consider_insertion.txt'

    $insertion = [IO.File]::ReadAllText(
        $insertionPathV74056362
    )

    $insertion = Normalize-LfV74056362 $insertion

    if ($useCrLf) {
        $insertion = $insertion.Replace("`n", "`r`n")
    }

    $insertAt = $match.Index + $match.Length
    $text = $raw.Insert(
        $insertAt,
        $newline + $insertion
    )

    [IO.File]::WriteAllText(
        $Path,
        $text,
        (New-Object System.Text.UTF8Encoding($hadBom))
    )

    return $true
}
