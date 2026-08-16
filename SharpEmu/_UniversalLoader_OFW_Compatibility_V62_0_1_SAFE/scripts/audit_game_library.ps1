param(
    [string]$RepositoryRoot,
    [string]$GamesRoot='F:\JOGOSPS5'
)
. (Join-Path $PSScriptRoot 'common.ps1')
$r=Resolve-Repo $RepositoryRoot
& (Join-Path $PSScriptRoot 'precheck.ps1') -RepositoryRoot $r

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$out=Join-Path $r "SharpEmu_V62_0_1_UNIVERSAL_LOADER_AUDIT_$stamp"
New-Item -ItemType Directory -Force -Path $out | Out-Null

$self=Join-Path $r 'src\SharpEmu.Core\Loader\SelfLoader.cs'
$ph=Join-Path $r 'src\SharpEmu.Core\Loader\ProgramHeader.cs'
$eh=Join-Path $r 'src\SharpEmu.Core\Loader\ElfHeader.cs'

Copy-Item -LiteralPath $self -Destination (Join-Path $out 'SelfLoader.cs.snapshot')
Copy-Item -LiteralPath $ph -Destination (Join-Path $out 'ProgramHeader.cs.snapshot')
Copy-Item -LiteralPath $eh -Destination (Join-Path $out 'ElfHeader.cs.snapshot')

$source=[IO.File]::ReadAllText($self)
$sourceInfo=@(
    "SelfLoader_SHA256=$((Get-FileHash -LiteralPath $self -Algorithm SHA256).Hash)",
    "ProgramHeader_SHA256=$((Get-FileHash -LiteralPath $ph -Algorithm SHA256).Hash)",
    "ElfHeader_SHA256=$((Get-FileHash -LiteralPath $eh -Algorithm SHA256).Hash)",
    "strict_ph_equality=$([int](Test-ContainsOrdinal $source 'header.ProgramHeaderEntrySize != ProgramHeaderSize'))",
    "minimum_ph_validation=$([int]((Test-ContainsOrdinal $source 'header.ProgramHeaderEntrySize < ProgramHeaderSize') -or (Test-ContainsOrdinal $source 'ProgramHeaderEntrySize < ProgramHeaderSize')))",
    "parse_layout=$([int](Test-ContainsOrdinal $source 'private static LoadContext ParseLayout(ReadOnlySpan<byte> imageData)'))",
    "section_fallback=$([int](Test-ContainsOrdinal $source 'AppendSectionRelocationDescriptors('))",
    "dynamic_lookup=$([int](Test-ContainsOrdinal $source 'ProgramHeaderType.Dynamic'))"
)
$sourceInfo | Set-Content -LiteralPath (Join-Path $out 'LOADER_SOURCE_STATE.txt') -Encoding UTF8

$rows=[Collections.Generic.List[object]]::new()
if (Test-Path -LiteralPath $GamesRoot -PathType Container) {
    $eboots=Get-ChildItem -LiteralPath $GamesRoot -Recurse -File -Filter 'eboot.bin' -ErrorAction SilentlyContinue
    foreach($f in $eboots) {
        $bytes=[IO.File]::ReadAllBytes($f.FullName)
        $kind='unknown-or-encrypted'
        $offset=-1
        $candidateValid=$false
        $machine=-1
        $class=-1
        $endian=-1
        $abi=-1
        $abiVer=-1
        $phoff=[uint64]0
        $phent=-1
        $phnum=-1
        $loadCount=0

        $limit=[Math]::Min([Math]::Max(0,$bytes.Length-64),4*1024*1024)
        $start=0
        if ($bytes.Length -ge 4 -and
            $bytes[0]-eq 0x7F -and $bytes[1]-eq 0x45 -and
            $bytes[2]-eq 0x4C -and $bytes[3]-eq 0x46) {
            $offset=0
            $kind='bare-elf'
        } elseif ($bytes.Length -ge 64) {
            for($i=4;$i-le$limit;$i+=4) {
                if($bytes[$i]-eq 0x7F -and $bytes[$i+1]-eq 0x45 -and
                   $bytes[$i+2]-eq 0x4C -and $bytes[$i+3]-eq 0x46) {
                    $offset=$i
                    $kind='wrapped-elf-candidate'
                    break
                }
            }
        }

        if($offset-ge 0 -and ($offset+64)-le$bytes.Length) {
            $class=$bytes[$offset+4]
            $endian=$bytes[$offset+5]
            $abi=$bytes[$offset+7]
            $abiVer=$bytes[$offset+8]
            $machine=[BitConverter]::ToUInt16($bytes,$offset+18)
            $phoff=[BitConverter]::ToUInt64($bytes,$offset+32)
            $phent=[BitConverter]::ToUInt16($bytes,$offset+54)
            $phnum=[BitConverter]::ToUInt16($bytes,$offset+56)

            $candidateValid=($class-eq2 -and $endian-eq1 -and $machine-eq62 -and $phent-ge56 -and $phnum-gt0 -and $phnum-le512)
            if($candidateValid) {
                try {
                    $table=[uint64]$offset+$phoff
                    $end=$table+([uint64]$phent*[uint64]$phnum)
                    if($end-gt[uint64]$bytes.Length){$candidateValid=$false}
                    else {
                        for($n=0;$n-lt$phnum;$n++) {
                            $po=[int]($table+([uint64]$n*[uint64]$phent))
                            $type=[BitConverter]::ToUInt32($bytes,$po)
                            if($type-eq1){$loadCount++}
                        }
                        if($loadCount-eq0){$candidateValid=$false}
                    }
                } catch {$candidateValid=$false}
            }
        }

        if($kind-eq'wrapped-elf-candidate' -and !$candidateValid) {
            $kind='wrapped-elf-invalid'
        }

        $rows.Add([pscustomobject]@{
            Path=$f.FullName
            Kind=$kind
            CandidateValid=$candidateValid
            ElfOffset=if($offset-ge0){('0x{0:X}' -f $offset)}else{''}
            ElfClass=$class
            Endian=$endian
            Machine=$machine
            Abi=$abi
            AbiVersion=$abiVer
            ProgramHeaderOffset=('0x{0:X}' -f $phoff)
            ProgramHeaderEntrySize=$phent
            ProgramHeaderCount=$phnum
            LoadSegments=$loadCount
            FileBytes=$bytes.Length
        })
    }
}

$rows | Export-Csv -LiteralPath (Join-Path $out 'EBOOT_MATRIX.csv') -NoTypeInformation -Encoding UTF8

@(
    'version=62.0.1',
    "games_root=$GamesRoot",
    "eboot_count=$($rows.Count)",
    "bare_elf=$(($rows | Where-Object Kind -eq 'bare-elf').Count)",
    "valid_wrapped_elf=$(($rows | Where-Object { $_.Kind -eq 'wrapped-elf-candidate' -and $_.CandidateValid }).Count)",
    "invalid_wrapped_elf=$(($rows | Where-Object Kind -eq 'wrapped-elf-invalid').Count)",
    "unknown_or_encrypted=$(($rows | Where-Object Kind -eq 'unknown-or-encrypted').Count)",
    '',
    'No game was started.',
    'Unknown/encrypted containers are intentionally not treated as executable ELF.'
) | Set-Content -LiteralPath (Join-Path $out 'SUMMARY.txt') -Encoding UTF8

# Include focused loader lines so next patch can target current methods exactly.
$lines=[IO.File]::ReadAllLines($self)
$patterns=@(
    'ProgramHeaderEntrySize',
    'ParseLayout(',
    'SelfHeader',
    'ElfMagic',
    'ProgramHeaderType.Dynamic',
    'AppendSectionRelocationDescriptors(',
    'return EmptyImportStubs',
    'TryLoadDynamicTableBytes('
)
$e=[Collections.Generic.List[string]]::new()
foreach($pattern in $patterns) {
    for($i=0;$i-lt$lines.Length;$i++) {
        if($lines[$i].IndexOf($pattern,[StringComparison]::Ordinal)-ge0) {
            $a=[Math]::Max(0,$i-18)
            $b=[Math]::Min($lines.Length-1,$i+28)
            $e.Add("===== pattern='$pattern' line=$($i+1) =====")
            for($j=$a;$j-le$b;$j++) {
                $e.Add(('{0,6}: {1}' -f ($j+1),$lines[$j]))
            }
        }
    }
}
$e | Set-Content -LiteralPath (Join-Path $out 'LOADER_SOURCE_EVIDENCE.txt') -Encoding UTF8

$zip="$out.zip"
Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zip -Force
Write-Host "[V62.0.1] RESULT: $zip"
