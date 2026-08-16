param(
 [string]$Game='F:\JOGOSPS5\[DLPSGAME.COM]-PPSA09790\[DLPSGAME.COM]-PPSA09790\PPSA09790-app\eboot.bin'
)
. (Join-Path $PSScriptRoot "common.ps1")
$repo=Find-RepoRoot
$target=Join-Path $repo "src\SharpEmu.Libs\Kernel\KernelPthreadExtendedCompatExports.cs"
$t=Get-Content -LiteralPath $target -Raw

if(-not(Test-Path -LiteralPath $Game -PathType Leaf)){throw "DBFZ eboot missing: $Game"}
$sha=(Get-FileHash -Algorithm SHA256 -LiteralPath $Game).Hash.ToLowerInvariant()
if($sha -ne '106b594c4e84401b096ec8b41a088fbf4e3862aee2faf030e4e6767df5cd1018'){
    throw "Unexpected DBFZ eboot SHA256: $sha"
}

foreach($sig in @(
 'public static int PosixPthreadSetspecific(CpuContext ctx)',
 'public static int PosixPthreadGetspecific(CpuContext ctx)',
 'public static void RunThreadLocalDestructors(CpuContext ctx)'
)){
    if($null -eq (Find-MethodBlock -Text $t -Signature $sig)){throw "Required method missing: $sig"}
}
if(-not $t.Contains('Nid = "eoht7mQOCmo"')){throw "scePthreadGetspecific NID missing."}
if(-not $t.Contains('Nid = "+BzXYkqYeLE"')){throw "scePthreadSetspecific NID missing."}

$already=$t.Contains('SHARPEMU_DBFZ_PTHREAD_TLS_HOTPATH_V1_8_20')
$state=if($already){'AlreadyApplied'}else{'ReadyToApply'}

Write-Host "[DBFZ-TLS-1820] EBOOT SHA256=$sha"
Write-Host "[DBFZ-TLS-1820] Source SHA256=$((Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash.ToLowerInvariant())"
Write-Host "[DBFZ-TLS-1820] State=$state"
Write-Host "[DBFZ-TLS-1820] PRECHECK PASSED."
