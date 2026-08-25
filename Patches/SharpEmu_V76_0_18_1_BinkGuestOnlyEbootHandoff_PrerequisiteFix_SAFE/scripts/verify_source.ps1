param([string]$RepoRoot='C:\Users\Edpo\Documents\GitHub\sharpemu',[string]$PatchesRoot='C:\Users\Edpo\Documents\GitHub\sharpemu\Patches')
. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot $RepoRoot
$patches=Get-PatchesRoot $PatchesRoot
Assert-V7618Installed $repo
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$out=Join-Path $patches "SharpEmu_V76_0_18_1_SOURCE_VERIFY_$stamp.txt"
@(
    "Tag=$PackageTag",'Status=SOURCE_VERIFY_PASSED',"RepositoryRoot=$repo",
    'HardGuestOnly=1','HostBinkTakeover=0','FfmpegBink2=0','NihavBink2=0','RadHostBink2=0',
    'BinkCompletionShim=0','HostBlackHandoffOnGuestClose=0','GuestEbootContinuation=1','V76.0.16Preserved=1'
) | Set-Content -LiteralPath $out -Encoding UTF8
Write-Host "[$PackageTag] SOURCE VERIFY PASSED. $out"
