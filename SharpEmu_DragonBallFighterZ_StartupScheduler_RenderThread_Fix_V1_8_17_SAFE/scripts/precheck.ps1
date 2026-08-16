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

$fs=[IO.File]::Open($Game,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
try {
    $hdr=New-Object byte[] 0x40
    $read=$fs.Read($hdr,0,$hdr.Length)
} finally {$fs.Dispose()}
if($read -lt 0x40 -or $hdr[0] -ne 0x7F -or $hdr[1] -ne 0x45 -or $hdr[2] -ne 0x4C -or $hdr[3] -ne 0x46){
    throw "eboot is not ELF."
}
$etype=[BitConverter]::ToUInt16($hdr,16)
$machine=[BitConverter]::ToUInt16($hdr,18)
if($etype -ne 0xFE10 -or $machine -ne 0x003E -or $hdr[4] -ne 2 -or $hdr[7] -ne 9){
    throw ("Unexpected ELF identity type=0x{0:X4} machine=0x{1:X4} class={2} abi={3}" -f $etype,$machine,$hdr[4],$hdr[7])
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

Write-Host "[DBFZ-BOOT-1817] RepoRoot=$repo"
Write-Host "[DBFZ-BOOT-1817] EBOOT SHA256=$sha"
Write-Host ("[DBFZ-BOOT-1817] ELF type=0x{0:X4} machine=0x{1:X4} class={2} abi={3}" -f $etype,$machine,$hdr[4],$hdr[7])
Write-Host "[DBFZ-BOOT-1817] EBOOT audited imports=2766 relocations=495681 (runtime/full-audit reference)"
Write-Host "[DBFZ-BOOT-1817] Main SHA=$((Get-FileHash -Algorithm SHA256 -LiteralPath $main).Hash.ToLowerInvariant())"
Write-Host "[DBFZ-BOOT-1817] NativeWorker SHA=$((Get-FileHash -Algorithm SHA256 -LiteralPath $worker).Hash.ToLowerInvariant())"
Write-Host "[DBFZ-BOOT-1817] NativeWorkerMaxConcurrent=$currentMax"
Write-Host "[DBFZ-BOOT-1817] State=$state"
Write-Host "[DBFZ-BOOT-1817] PRECHECK PASSED."
