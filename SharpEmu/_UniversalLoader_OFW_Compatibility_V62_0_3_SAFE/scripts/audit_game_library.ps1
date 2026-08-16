param(
    [string]$RepositoryRoot,
    [string]$GamesRoot = 'F:\JOGOSPS5'
)

. (Join-Path $PSScriptRoot 'common.ps1')

$root = Resolve-RepositoryRoot -RepositoryRoot $RepositoryRoot
& (Join-Path $PSScriptRoot 'precheck.ps1') -RepositoryRoot $root

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$outputDirectory = Join-Path $root ('SharpEmu_V62_0_3_UNIVERSAL_LOADER_AUDIT_{0}' -f $stamp)
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

$selfLoader = Join-Path $root 'src\SharpEmu.Core\Loader\SelfLoader.cs'
$programHeader = Join-Path $root 'src\SharpEmu.Core\Loader\ProgramHeader.cs'
$elfHeader = Join-Path $root 'src\SharpEmu.Core\Loader\ElfHeader.cs'

Copy-Item -LiteralPath $selfLoader -Destination (Join-Path $outputDirectory 'SelfLoader.cs.snapshot') -Force
Copy-Item -LiteralPath $programHeader -Destination (Join-Path $outputDirectory 'ProgramHeader.cs.snapshot') -Force
Copy-Item -LiteralPath $elfHeader -Destination (Join-Path $outputDirectory 'ElfHeader.cs.snapshot') -Force

$source = [IO.File]::ReadAllText($selfLoader)
$selfHash = (Get-FileHash -LiteralPath $selfLoader -Algorithm SHA256).Hash
$programHeaderHash = (Get-FileHash -LiteralPath $programHeader -Algorithm SHA256).Hash
$elfHeaderHash = (Get-FileHash -LiteralPath $elfHeader -Algorithm SHA256).Hash

$strictPhEquality = 0
if (Test-TextContains -Text $source -Pattern 'header.ProgramHeaderEntrySize != ProgramHeaderSize') {
    $strictPhEquality = 1
}

$minimumPhValidation = 0
if (
    (Test-TextContains -Text $source -Pattern 'header.ProgramHeaderEntrySize < ProgramHeaderSize') -or
    (Test-TextContains -Text $source -Pattern 'ProgramHeaderEntrySize < ProgramHeaderSize')
) {
    $minimumPhValidation = 1
}

$parseLayoutPresent = 0
if (Test-TextContains -Text $source -Pattern 'private static LoadContext ParseLayout(ReadOnlySpan<byte> imageData)') {
    $parseLayoutPresent = 1
}

$sectionFallbackPresent = 0
if (Test-TextContains -Text $source -Pattern 'AppendSectionRelocationDescriptors(') {
    $sectionFallbackPresent = 1
}

$dynamicLookupPresent = 0
if (Test-TextContains -Text $source -Pattern 'ProgramHeaderType.Dynamic') {
    $dynamicLookupPresent = 1
}

$sourceInfo = @()
$sourceInfo += ('SelfLoader_SHA256={0}' -f $selfHash)
$sourceInfo += ('ProgramHeader_SHA256={0}' -f $programHeaderHash)
$sourceInfo += ('ElfHeader_SHA256={0}' -f $elfHeaderHash)
$sourceInfo += ('strict_ph_equality={0}' -f $strictPhEquality)
$sourceInfo += ('minimum_ph_validation={0}' -f $minimumPhValidation)
$sourceInfo += ('parse_layout={0}' -f $parseLayoutPresent)
$sourceInfo += ('section_fallback={0}' -f $sectionFallbackPresent)
$sourceInfo += ('dynamic_lookup={0}' -f $dynamicLookupPresent)
$sourceInfo | Set-Content -LiteralPath (Join-Path $outputDirectory 'LOADER_SOURCE_STATE.txt') -Encoding UTF8

$rows = @()

if (Test-Path -LiteralPath $GamesRoot -PathType Container) {
    $eboots = Get-ChildItem -LiteralPath $GamesRoot -Recurse -File -Filter 'eboot.bin' -ErrorAction SilentlyContinue

    foreach ($file in $eboots) {
        $bytes = [IO.File]::ReadAllBytes($file.FullName)

        $kind = 'unknown-or-encrypted'
        $elfOffset = -1
        $candidateValid = $false
        $elfClass = -1
        $endian = -1
        $machine = -1
        $abi = -1
        $abiVersion = -1
        [uint64]$programHeaderOffset = 0
        $programHeaderEntrySize = -1
        $programHeaderCount = -1
        $loadSegments = 0

        if ($bytes.Length -ge 64) {
            $isBareElf =
                ($bytes[0] -eq 0x7F) -and
                ($bytes[1] -eq 0x45) -and
                ($bytes[2] -eq 0x4C) -and
                ($bytes[3] -eq 0x46)

            if ($isBareElf) {
                $elfOffset = 0
                $kind = 'bare-elf'
            }
            else {
                $maximumCandidateOffset = $bytes.Length - 64
                if ($maximumCandidateOffset -gt (4 * 1024 * 1024)) {
                    $maximumCandidateOffset = 4 * 1024 * 1024
                }

                for ($candidateOffset = 4; $candidateOffset -le $maximumCandidateOffset; $candidateOffset += 4) {
                    $isElfMagic =
                        ($bytes[$candidateOffset] -eq 0x7F) -and
                        ($bytes[$candidateOffset + 1] -eq 0x45) -and
                        ($bytes[$candidateOffset + 2] -eq 0x4C) -and
                        ($bytes[$candidateOffset + 3] -eq 0x46)

                    if ($isElfMagic) {
                        $elfOffset = $candidateOffset
                        $kind = 'wrapped-elf-candidate'
                        break
                    }
                }
            }
        }

        if (($elfOffset -ge 0) -and (($elfOffset + 64) -le $bytes.Length)) {
            $elfClass = [int]$bytes[$elfOffset + 4]
            $endian = [int]$bytes[$elfOffset + 5]
            $abi = [int]$bytes[$elfOffset + 7]
            $abiVersion = [int]$bytes[$elfOffset + 8]
            $machine = [int][BitConverter]::ToUInt16($bytes, $elfOffset + 18)
            $programHeaderOffset = [BitConverter]::ToUInt64($bytes, $elfOffset + 32)
            $programHeaderEntrySize = [int][BitConverter]::ToUInt16($bytes, $elfOffset + 54)
            $programHeaderCount = [int][BitConverter]::ToUInt16($bytes, $elfOffset + 56)

            $candidateValid =
                ($elfClass -eq 2) -and
                ($endian -eq 1) -and
                ($machine -eq 62) -and
                ($programHeaderEntrySize -ge 56) -and
                ($programHeaderCount -gt 0) -and
                ($programHeaderCount -le 512)

            if ($candidateValid) {
                try {
                    [uint64]$programHeaderTable = [uint64]$elfOffset + $programHeaderOffset
                    [uint64]$programHeaderTableSize =
                        [uint64]$programHeaderEntrySize * [uint64]$programHeaderCount
                    [uint64]$programHeaderTableEnd =
                        $programHeaderTable + $programHeaderTableSize

                    if ($programHeaderTableEnd -gt [uint64]$bytes.Length) {
                        $candidateValid = $false
                    }
                    else {
                        for ($headerIndex = 0; $headerIndex -lt $programHeaderCount; $headerIndex++) {
                            [uint64]$entryOffset64 =
                                $programHeaderTable +
                                ([uint64]$headerIndex * [uint64]$programHeaderEntrySize)

                            if ($entryOffset64 -gt [uint64][int]::MaxValue) {
                                $candidateValid = $false
                                break
                            }

                            $entryOffset = [int]$entryOffset64
                            if (($entryOffset + 56) -gt $bytes.Length) {
                                $candidateValid = $false
                                break
                            }

                            $headerType = [BitConverter]::ToUInt32($bytes, $entryOffset)
                            if ($headerType -eq 1) {
                                $loadSegments++
                            }
                        }

                        if ($loadSegments -eq 0) {
                            $candidateValid = $false
                        }
                    }
                }
                catch {
                    $candidateValid = $false
                }
            }
        }

        if (($kind -eq 'wrapped-elf-candidate') -and (-not $candidateValid)) {
            $kind = 'wrapped-elf-invalid'
        }

        $elfOffsetText = ''
        if ($elfOffset -ge 0) {
            $elfOffsetText = ('0x{0:X}' -f $elfOffset)
        }

        $programHeaderOffsetText = ('0x{0:X}' -f $programHeaderOffset)

        $row = New-Object PSObject
        Add-Member -InputObject $row -MemberType NoteProperty -Name 'Path' -Value $file.FullName
        Add-Member -InputObject $row -MemberType NoteProperty -Name 'Kind' -Value $kind
        Add-Member -InputObject $row -MemberType NoteProperty -Name 'CandidateValid' -Value $candidateValid
        Add-Member -InputObject $row -MemberType NoteProperty -Name 'ElfOffset' -Value $elfOffsetText
        Add-Member -InputObject $row -MemberType NoteProperty -Name 'ElfClass' -Value $elfClass
        Add-Member -InputObject $row -MemberType NoteProperty -Name 'Endian' -Value $endian
        Add-Member -InputObject $row -MemberType NoteProperty -Name 'Machine' -Value $machine
        Add-Member -InputObject $row -MemberType NoteProperty -Name 'Abi' -Value $abi
        Add-Member -InputObject $row -MemberType NoteProperty -Name 'AbiVersion' -Value $abiVersion
        Add-Member -InputObject $row -MemberType NoteProperty -Name 'ProgramHeaderOffset' -Value $programHeaderOffsetText
        Add-Member -InputObject $row -MemberType NoteProperty -Name 'ProgramHeaderEntrySize' -Value $programHeaderEntrySize
        Add-Member -InputObject $row -MemberType NoteProperty -Name 'ProgramHeaderCount' -Value $programHeaderCount
        Add-Member -InputObject $row -MemberType NoteProperty -Name 'LoadSegments' -Value $loadSegments
        Add-Member -InputObject $row -MemberType NoteProperty -Name 'FileBytes' -Value $bytes.Length
        $rows += $row
    }
}

$matrixPath = Join-Path $outputDirectory 'EBOOT_MATRIX.csv'
$rows | Export-Csv -LiteralPath $matrixPath -NoTypeInformation -Encoding UTF8

$bareElfCount = 0
$validWrappedElfCount = 0
$invalidWrappedElfCount = 0
$unknownOrEncryptedCount = 0

foreach ($row in $rows) {
    if ($row.Kind -eq 'bare-elf') {
        $bareElfCount++
    }
    elseif (($row.Kind -eq 'wrapped-elf-candidate') -and $row.CandidateValid) {
        $validWrappedElfCount++
    }
    elseif ($row.Kind -eq 'wrapped-elf-invalid') {
        $invalidWrappedElfCount++
    }
    elseif ($row.Kind -eq 'unknown-or-encrypted') {
        $unknownOrEncryptedCount++
    }
}

$summaryLines = @()
$summaryLines += 'version=62.0.3'
$summaryLines += ('games_root={0}' -f $GamesRoot)
$summaryLines += ('eboot_count={0}' -f $rows.Count)
$summaryLines += ('bare_elf={0}' -f $bareElfCount)
$summaryLines += ('valid_wrapped_elf={0}' -f $validWrappedElfCount)
$summaryLines += ('invalid_wrapped_elf={0}' -f $invalidWrappedElfCount)
$summaryLines += ('unknown_or_encrypted={0}' -f $unknownOrEncryptedCount)
$summaryLines += ''
$summaryLines += 'No game was started.'
$summaryLines += 'Unknown/encrypted containers are intentionally not treated as executable ELF.'
$summaryLines | Set-Content -LiteralPath (Join-Path $outputDirectory 'SUMMARY.txt') -Encoding UTF8

$sourceLines = [IO.File]::ReadAllLines($selfLoader)
$patterns = @(
    'ProgramHeaderEntrySize',
    'ParseLayout(',
    'SelfHeader',
    'ElfMagic',
    'ProgramHeaderType.Dynamic',
    'AppendSectionRelocationDescriptors(',
    'return EmptyImportStubs',
    'TryLoadDynamicTableBytes('
)

$evidenceLines = @()
foreach ($pattern in $patterns) {
    for ($lineIndex = 0; $lineIndex -lt $sourceLines.Length; $lineIndex++) {
        if ($sourceLines[$lineIndex].IndexOf($pattern, [StringComparison]::Ordinal) -ge 0) {
            $firstLine = [Math]::Max(0, $lineIndex - 18)
            $lastLine = [Math]::Min($sourceLines.Length - 1, $lineIndex + 28)

            $evidenceLines += ('===== pattern=''{0}'' line={1} =====' -f $pattern, ($lineIndex + 1))
            for ($contextLine = $firstLine; $contextLine -le $lastLine; $contextLine++) {
                $evidenceLines += ('{0,6}: {1}' -f ($contextLine + 1), $sourceLines[$contextLine])
            }
        }
    }
}
$evidenceLines | Set-Content -LiteralPath (Join-Path $outputDirectory 'LOADER_SOURCE_EVIDENCE.txt') -Encoding UTF8

$zipPath = $outputDirectory + '.zip'
Compress-Archive -Path (Join-Path $outputDirectory '*') -DestinationPath $zipPath -Force
Write-Host ('[V62.0.3] RESULT: {0}' -f $zipPath)
