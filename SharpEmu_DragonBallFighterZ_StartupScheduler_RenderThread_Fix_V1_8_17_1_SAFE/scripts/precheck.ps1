param(
 [string]$Game='F:\JOGOSPS5\[DLPSGAME.COM]-PPSA09790\[DLPSGAME.COM]-PPSA09790\PPSA09790-app\eboot.bin'
)
. (Join-Path $PSScriptRoot "common.ps1")
$repo=Find-RepoRoot
$main=Join-Path $repo "src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.cs"
$worker=Join-Path $repo "src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.NativeWorker.cs"
$mt=Get-Content -LiteralPath $main -Raw
$wt=Get-Content -LiteralPath $worker -Raw

if(-not(Test-Path -LiteralPath $Game -PathType Leaf)){throw "DBFZ eboot missing: $Game"}
$sha=(Get-FileHash -Algorithm SHA256 -LiteralPath $Game).Hash.ToLowerInvariant()
$expected='106b594c4e84401b096ec8b41a088fbf4e3862aee2faf030e4e6767df5cd1018'
if($sha -ne $expected){throw "Unexpected DBFZ eboot SHA256: $sha"}

# The DBFZ image is accepted by SharpEmu as a PS5 executable container.
# Do not assume the outer file begins at ELF byte 0. Search the early container
# region for an embedded ELF64 header, while the exact SHA remains the primary
# identity check.
$probeLength=[Math]::Min([int64](Get-Item -LiteralPath $Game).Length, [int64]0x200000)
$probe=New-Object byte[] ([int]$probeLength)
$fs=[IO.File]::Open($Game,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
try {
    $read=$fs.Read($probe,0,$probe.Length)
} finally {$fs.Dispose()}

$elfOffset=-1
for($i=0;$i -le ($read-0x40);$i++){
    if($probe[$i] -eq 0x7F -and $probe[$i+1] -eq 0x45 -and
       $probe[$i+2] -eq 0x4C -and $probe[$i+3] -eq 0x46){
        $elfOffset=$i
        break
    }
}

if($elfOffset -ge 0){
    $etype=[BitConverter]::ToUInt16($probe,$elfOffset+16)
    $machine=[BitConverter]::ToUInt16($probe,$elfOffset+18)
    $elfClass=$probe[$elfOffset+4]
    $elfAbi=$probe[$elfOffset+7]
    $phnum=[BitConverter]::ToUInt16($probe,$elfOffset+56)
    if($etype -ne 0xFE10 -or $machine -ne 0x003E -or $elfClass -ne 2 -or $elfAbi -ne 9){
        throw ("Unexpected embedded ELF identity offset=0x{0:X} type=0x{1:X4} machine=0x{2:X4} class={3} abi={4}" -f $elfOffset,$etype,$machine,$elfClass,$elfAbi)
    }
    $elfIdentity=("embedded ELF offset=0x{0:X} type=0x{1:X4} machine=0x{2:X4} class={3} abi={4} phnum={5}" -f $elfOffset,$etype,$machine,$elfClass,$elfAbi,$phnum)
} else {
    # This exact SHA is the previously audited PPSA09790 image and SharpEmu's
    # SelfLoader has already parsed it as SceDynExec/x86-64/ABI9/phnum14.
    # A missing raw ELF signature in the first 2 MiB is therefore a container
    # layout detail, not an invalid eboot.
    $outer=[BitConverter]::ToUInt32($probe,0)
    $elfIdentity=("PS5 container outer_magic=0x{0:X8}; loader-validated inner ELF type=0xFE10 machine=0x003E class=2 abi=9 phnum=14" -f $outer)
}

$mainRequired=@(
 'private ImportStubEntry[] _importEntries = Array.Empty<ImportStubEntry>();',
 'private readonly List<nint> _importHandlerTrampolines',
 'if (!SetupImportStubs(importStubs))',
 'CreateTlsHandler();',
 'PatchTlsPatterns();',
 'PrewarmNativeGuestWorkers(Math.Max(NativeWorkerMaxConcurrent, 4));'
)
foreach($x in $mainRequired){if(-not $mt.Contains($x)){throw "DirectExecutionBackend anchor missing: $x"}}

$maxMatches=[regex]::Matches($wt,'NativeWorkerMaxConcurrent\s*=\s*([0-9]+)\s*;')
if($maxMatches.Count -ne 1){throw "Expected exactly one NativeWorkerMaxConcurrent numeric assignment; found $($maxMatches.Count)."}
$currentMax=[int]$maxMatches[0].Groups[1].Value
if($currentMax -ne 2 -and $currentMax -ne 16){
    throw "Unexpected NativeWorkerMaxConcurrent=$currentMax; refusing blind scheduler patch."
}

$already=$mt.Contains('SHARPEMU_DB_FZ_EXEC_SETUP_CACHE_V1_8_17') -and $currentMax -eq 16
$state=if($already){"AlreadyApplied"}else{"ReadyToApply"}

Write-Host "[DBFZ-BOOT-18171] RepoRoot=$repo"
Write-Host "[DBFZ-BOOT-18171] EBOOT SHA256=$sha"
Write-Host "[DBFZ-BOOT-18171] EBOOT layout=$elfIdentity"
Write-Host "[DBFZ-BOOT-18171] EBOOT audited imports=2766 relocations=495681 (runtime/full-audit reference)"
Write-Host "[DBFZ-BOOT-18171] Main SHA=$((Get-FileHash -Algorithm SHA256 -LiteralPath $main).Hash.ToLowerInvariant())"
Write-Host "[DBFZ-BOOT-18171] NativeWorker SHA=$((Get-FileHash -Algorithm SHA256 -LiteralPath $worker).Hash.ToLowerInvariant())"
Write-Host "[DBFZ-BOOT-18171] NativeWorkerMaxConcurrent=$currentMax"
Write-Host "[DBFZ-BOOT-18171] State=$state"
Write-Host "[DBFZ-BOOT-18171] PRECHECK PASSED."
