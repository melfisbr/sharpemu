Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$PackageTag = '[V76.2.4.5-BINK-GUEST-YUV-INTEGER-SAMPLER-SPLITPATH-NULL-BUILDFIX]'
$PackageRoot = [System.IO.Directory]::GetParent($PSScriptRoot).FullName
$PatchesRoot = [System.IO.Directory]::GetParent($PackageRoot).FullName
$RepositoryRoot = [System.IO.Directory]::GetParent($PatchesRoot).FullName

$TargetName = 'SharpEmu_V76_2_4_1_BinkGuestYuvIntegerSamplerFix_ValidatorPathFix_SAFE'
$TargetRoot = Join-Path $PatchesRoot $TargetName
$TargetScript = Join-Path $TargetRoot 'scripts\patch_target.ps1'
$TargetManifest = Join-Path $TargetRoot 'manifest.sha256'
$TargetRunner = Join-Path $TargetRoot 'RUN_2_PATCH_AND_REVALIDATE_V76_2_4.cmd'
$MarkerV76245 = '# SHARPEMU_V76_2_4_5_PATCHES_PATH_SPLITPATH_NULL_FIX'

function Get-Sha256V76245([string]$PathValue) {
    return (Get-FileHash -LiteralPath $PathValue -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Read-TextV76245([string]$PathValue) {
    return [System.IO.File]::ReadAllText($PathValue)
}

function Write-TextV76245([string]$PathValue, [string]$TextValue) {
    $utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
    [System.IO.File]::WriteAllText($PathValue, $TextValue, $utf8NoBom)
}

function Assert-PowerShellParsesV76245([string]$PathValue) {
    $parseTokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $PathValue,
        [ref]$parseTokens,
        [ref]$parseErrors)
    if (@($parseErrors).Count -ne 0) {
        $messages = @($parseErrors | ForEach-Object { $_.Message }) -join ' | '
        throw "PowerShell parse failed: $PathValue :: $messages"
    }
}

function Get-TargetStateV76245 {
    if (-not (Test-Path -LiteralPath $TargetRoot -PathType Container)) { return 'MissingTarget' }
    if (-not (Test-Path -LiteralPath $TargetScript -PathType Leaf)) { return 'MissingScript' }
    if (-not (Test-Path -LiteralPath $TargetRunner -PathType Leaf)) { return 'MissingRunner' }
    $targetText = Read-TextV76245 $TargetScript
    if ($targetText.Contains($MarkerV76245)) { return 'Applied' }
    return 'Ready'
}

function Get-SuspiciousSplitPathCountV76245([string]$TextValue) {
    $scanTokens = $null
    $scanErrors = $null
    $scanAst = [System.Management.Automation.Language.Parser]::ParseInput(
        $TextValue,
        [ref]$scanTokens,
        [ref]$scanErrors)
    if (@($scanErrors).Count -ne 0) { return 0 }

    $countValue = 0
    $commands = @($scanAst.FindAll({
        param($node)
        return ($node -is [System.Management.Automation.Language.CommandAst]) -and
               ($node.GetCommandName() -ieq 'Split-Path')
    }, $true))
    foreach ($commandNode in $commands) {
        foreach ($elementNode in @($commandNode.CommandElements | Select-Object -Skip 1)) {
            if ($elementNode -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $elementNode.VariablePath.UserPath -ieq 'null') {
                $countValue++
                continue
            }
            if ($elementNode -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                $elementNode.Value -eq '$null') {
                $countValue++
            }
        }
    }
    return $countValue
}

function Update-TargetManifestV76245 {
    if (-not (Test-Path -LiteralPath $TargetManifest -PathType Leaf)) { return $false }
    $manifestText = Read-TextV76245 $TargetManifest
    $newHash = Get-Sha256V76245 $TargetScript
    $pattern = '(?im)^[0-9a-f]{64}\s+\*?scripts[\\/]patch_target\.ps1\s*$'
    if (-not [regex]::IsMatch($manifestText, $pattern)) { return $false }
    $replacement = $newHash + '  scripts/patch_target.ps1'
    $updated = [regex]::Replace($manifestText, $pattern, $replacement, 1)
    Write-TextV76245 $TargetManifest $updated
    return $true
}

function Repair-TargetScriptV76245 {
    Assert-PowerShellParsesV76245 $TargetScript
    $sourceText = Read-TextV76245 $TargetScript
    if ($sourceText.Contains($MarkerV76245)) {
        return 'AlreadyApplied'
    }

    $astTokens = $null
    $astErrors = $null
    $scriptAst = [System.Management.Automation.Language.Parser]::ParseInput(
        $sourceText,
        [ref]$astTokens,
        [ref]$astErrors)
    if (@($astErrors).Count -ne 0) {
        throw 'Target patch_target.ps1 has parse errors before V76.2.4.5.'
    }

    $patchAssignments = @($scriptAst.FindAll({
        param($node)
        if ($node -isnot [System.Management.Automation.Language.AssignmentStatementAst]) { return $false }
        if ($node.Left -isnot [System.Management.Automation.Language.VariableExpressionAst]) { return $false }
        return $node.Left.VariablePath.UserPath -ieq 'Patches'
    }, $true))

    $safeAssignment = @'
# SHARPEMU_V76_2_4_5_PATCHES_PATH_SPLITPATH_NULL_FIX
$packageRootV76245 = [System.IO.Directory]::GetParent($PSScriptRoot).FullName
if ([string]::IsNullOrWhiteSpace($packageRootV76245)) {
    throw 'V76.2.4.5 could not resolve package root from PSScriptRoot.'
}
$Patches = [System.IO.Directory]::GetParent($packageRootV76245).FullName
if ([string]::IsNullOrWhiteSpace($Patches) -or -not (Test-Path -LiteralPath $Patches -PathType Container)) {
    throw "V76.2.4.5 resolved invalid Patches root: '$Patches'"
}
'@

    if ($patchAssignments.Count -gt 0) {
        $firstAssignment = $patchAssignments[0]
        $before = $sourceText.Substring(0, $firstAssignment.Extent.StartOffset)
        $after = $sourceText.Substring($firstAssignment.Extent.EndOffset)
        $sourceText = $before + $safeAssignment + $after
    }
    else {
        $insertOffset = 0
        if ($null -ne $scriptAst.ParamBlock) {
            $insertOffset = $scriptAst.ParamBlock.Extent.EndOffset
        }
        $before = $sourceText.Substring(0, $insertOffset)
        $after = $sourceText.Substring($insertOffset)
        $sourceText = $before + "`r`n" + $safeAssignment + "`r`n" + $after
    }

    # A trailing $null (or literal '$null') cannot be a meaningful Split-Path
    # path here. Remove only that terminal extra argument; do not rewrite other
    # Split-Path calls or their path expressions.
    $trailingNullPattern = '(?im)(\bSplit-Path\b[^\r\n;|]*?)\s+(?:["'']\$null["'']|\$null)\s*(?=$|[;|)])'
    $sourceText = [regex]::Replace($sourceText, $trailingNullPattern, '$1')

    Write-TextV76245 $TargetScript $sourceText
    Assert-PowerShellParsesV76245 $TargetScript

    $postText = Read-TextV76245 $TargetScript
    if (-not $postText.Contains($MarkerV76245)) {
        throw 'V76.2.4.5 marker missing after patch.'
    }
    $remaining = Get-SuspiciousSplitPathCountV76245 $postText
    if ($remaining -ne 0) {
        throw "V76.2.4.5 suspicious Split-Path null argument remains: $remaining"
    }
    return 'Patched'
}
