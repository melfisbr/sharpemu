param([string]$RepositoryRoot)

. (Join-Path $PSScriptRoot 'common.ps1')

$root = Resolve-RepoRoot -RepositoryRoot $RepositoryRoot
$packageRoot = Get-PackageRoot
& (Join-Path $PSScriptRoot 'precheck.ps1') -RepositoryRoot $root

$selfLoader = Join-Path $root 'src\SharpEmu.Core\Loader\SelfLoader.cs'
$decoder = Join-Path $root 'src\SharpEmu.Core\Loader\Ps5SceDynamicImportMetadata.cs'
$packageDecoder = Join-Path $packageRoot 'src\SharpEmu.Core\Loader\Ps5SceDynamicImportMetadata.cs'

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupDirectory = Join-Path $root ('.sharpemu-hotfix-backup\Gen5ImportMetadata_V73_1_{0}' -f $stamp)
New-Item -ItemType Directory -Force -Path $backupDirectory | Out-Null

$selfBackup = Join-Path $backupDirectory 'SelfLoader.cs'
Copy-Item -LiteralPath $selfLoader -Destination $selfBackup -Force

$decoderExisted = Test-Path -LiteralPath $decoder -PathType Leaf
$decoderBackup = Join-Path $backupDirectory 'Ps5SceDynamicImportMetadata.cs'
if ($decoderExisted) {
    Copy-Item -LiteralPath $decoder -Destination $decoderBackup -Force
}

$source = [IO.File]::ReadAllText($selfLoader)
$changed = $false

try {
    if (-not (Test-ContainsOrdinal -Text $source -Pattern 'DtSceNeededModuleGen5 = 0x61000045')) {
        $anchor = 'private const long DtSceImportLib = 0x61000015;'
        if (-not (Test-ContainsOrdinal -Text $source -Pattern $anchor)) {
            throw '[V73.1] Cannot insert Gen5 dynamic-tag constants: legacy import-lib anchor missing.'
        }

        $lineBreak = if ($source.IndexOf("`r`n", [StringComparison]::Ordinal) -ge 0) { "`r`n" } else { "`n" }
        $insert =
            $anchor + $lineBreak +
            '    // V73.1: Gen5 PS5 module/library identity tags observed in SceDynExec/SceDynamic PT_DYNAMIC.' + $lineBreak +
            '    private const long DtSceNeededModuleGen5 = 0x61000045;' + $lineBreak +
            '    private const long DtSceImportLibGen5 = 0x61000049;'
        $source = $source.Replace($anchor, $insert)
        $changed = $true
    }

    if (-not (Test-ContainsOrdinal -Text $source -Pattern 'DtSceNeededModule || tag == DtSceNeededModuleGen5')) {
        $old = 'else if (tag == DtSceNeededModule)'
        $new = 'else if (tag == DtSceNeededModule || tag == DtSceNeededModuleGen5)'
        if (-not (Test-ContainsOrdinal -Text $source -Pattern $old)) {
            throw '[V73.1] Cannot extend CollectNeededModuleNames: exact legacy branch missing.'
        }
        $source = $source.Replace($old, $new)
        $changed = $true
    }

    if (-not (Test-ContainsOrdinal -Text $source -Pattern 'case DtSceNeededModuleGen5:')) {
        $source = Insert-LineAfterFirstMatch `
            -Text $source `
            -RegexPattern '^[ \t]*case DtSceNeededModule:[ \t]*$' `
            -NewLineText 'case DtSceNeededModuleGen5:'
        $changed = $true
    }

    if (-not (Test-ContainsOrdinal -Text $source -Pattern 'case DtSceImportLibGen5:')) {
        if ([regex]::IsMatch(
            $source,
            '^[ \t]*case DtSceImportLib:[ \t]*$',
            [Text.RegularExpressions.RegexOptions]::Multiline)) {

            $source = Insert-LineAfterFirstMatch `
                -Text $source `
                -RegexPattern '^[ \t]*case DtSceImportLib:[ \t]*$' `
                -NewLineText 'case DtSceImportLibGen5:'
        }
        elseif (Test-ContainsOrdinal -Text $source -Pattern 'tag == DtSceImportLib') {
            # Conservative fallback for an if/else implementation.
            $source = $source.Replace(
                'tag == DtSceImportLib',
                '(tag == DtSceImportLib || tag == DtSceImportLibGen5)')
        }
        else {
            throw '[V73.1] Cannot extend ParseSceImportMetadata: legacy import-library branch missing.'
        }
        $changed = $true
    }

    $requiredPostPatch = @(
        'DtSceNeededModuleGen5 = 0x61000045',
        'DtSceImportLibGen5 = 0x61000049',
        'DtSceNeededModule || tag == DtSceNeededModuleGen5',
        'case DtSceNeededModuleGen5:',
        'DtSceImportLibGen5'
    )
    foreach ($marker in $requiredPostPatch) {
        if (-not (Test-ContainsOrdinal -Text $source -Pattern $marker)) {
            throw ('[V73.1] Post-patch validation failed: missing {0}' -f $marker)
        }
    }

    if ($changed) {
        [IO.File]::WriteAllText($selfLoader, $source, [Text.UTF8Encoding]::new($false))
        Write-Host '[V73.1] SelfLoader Gen5 metadata tags integrated.'
    }
    else {
        Write-Host '[V73.1] SelfLoader Gen5 metadata integration already present.'
    }

    $packageDecoderText = [IO.File]::ReadAllText($packageDecoder)
    $installDecoder = $true
    if (Test-Path -LiteralPath $decoder -PathType Leaf) {
        $currentDecoderText = [IO.File]::ReadAllText($decoder)
        if (
            (Test-ContainsOrdinal -Text $currentDecoderText -Pattern 'NeededModuleTag = 0x61000045UL') -and
            (Test-ContainsOrdinal -Text $currentDecoderText -Pattern 'ImportLibraryTag = 0x61000049UL') -and
            (Test-ContainsOrdinal -Text $currentDecoderText -Pattern 'TryDecodeSymbolIdentity')
        ) {
            $installDecoder = $false
            Write-Host '[V73.1] Existing Ps5SceDynamicImportMetadata.cs is compatible; preserving it.'
        }
    }

    if ($installDecoder) {
        [IO.File]::WriteAllText($decoder, $packageDecoderText, [Text.UTF8Encoding]::new($false))
        Write-Host '[V73.1] Installed Ps5SceDynamicImportMetadata.cs.'
    }

    Push-Location $root
    try {
        Write-Host '[V73.1] Building SharpEmu.Core...'
        & dotnet build '.\src\SharpEmu.Core\SharpEmu.Core.csproj' -c Debug --nologo
        $coreExit = $LASTEXITCODE
        if ($coreExit -ne 0) {
            throw ('SharpEmu.Core build failed with exit code {0}.' -f $coreExit)
        }

        Write-Host '[V73.1] Building SharpEmu.CLI Debug win-x64...'
        & dotnet build '.\src\SharpEmu.CLI\SharpEmu.CLI.csproj' -c Debug -r win-x64 --nologo
        $cliExit = $LASTEXITCODE
        if ($cliExit -ne 0) {
            throw ('SharpEmu.CLI build failed with exit code {0}.' -f $cliExit)
        }
    }
    finally {
        Pop-Location
    }

    $finalSource = [IO.File]::ReadAllText($selfLoader)
    $integrationChecks = @(
        'DtSceNeededModuleGen5 = 0x61000045',
        'DtSceImportLibGen5 = 0x61000049',
        'DtSceNeededModule || tag == DtSceNeededModuleGen5',
        'case DtSceNeededModuleGen5:',
        'case DtSceImportLibGen5:'
    )
    foreach ($check in $integrationChecks) {
        if (-not (Test-ContainsOrdinal -Text $finalSource -Pattern $check)) {
            throw ('[V73.1] Build passed but source integration marker is missing: {0}' -f $check)
        }
    }

    Write-Host '[V73.1] SUCCESS'
    Write-Host ('[V73.1] Backup: {0}' -f $backupDirectory)
    Write-Host '[V73.1] Gen5 module/library metadata is now connected to the existing parser.'
    Write-Host '[V73.1] No blind HLE stubs were generated.'
    Write-Host '[V73.1] Next: RUN_DEMONS_METADATA_IMPORT_TRACE_V73_1.cmd'
}
catch {
    Write-Host ('[V73.1] FAILURE: {0}' -f $_.Exception.Message) -ForegroundColor Red

    if (Test-Path -LiteralPath $selfBackup -PathType Leaf) {
        Copy-Item -LiteralPath $selfBackup -Destination $selfLoader -Force
        Write-Host '[V73.1] SelfLoader.cs restored.'
    }

    if ($decoderExisted) {
        if (Test-Path -LiteralPath $decoderBackup -PathType Leaf) {
            Copy-Item -LiteralPath $decoderBackup -Destination $decoder -Force
            Write-Host '[V73.1] Ps5SceDynamicImportMetadata.cs restored.'
        }
    }
    else {
        Remove-Item -LiteralPath $decoder -Force -ErrorAction SilentlyContinue
    }

    throw
}
