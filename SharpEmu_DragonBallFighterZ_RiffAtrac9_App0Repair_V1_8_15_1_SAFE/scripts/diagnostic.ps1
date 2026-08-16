param([int]$Seconds=360,[string]$Game='F:\JOGOSPS5\[DLPSGAME.COM]-PPSA09790\[DLPSGAME.COM]-PPSA09790\PPSA09790-app\eboot.bin')
. (Join-Path $PSScriptRoot "common.ps1")
& (Join-Path $PSScriptRoot "post_audit.ps1")
$repo=Find-RepoRoot
$exe=Join-Path $repo "artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe"
if(-not(Test-Path -LiteralPath $exe -PathType Leaf)){throw "SharpEmu.exe missing: $exe"}
if(-not(Test-Path -LiteralPath $Game -PathType Leaf)){throw "DBFZ eboot missing: $Game"}
$out=Join-Path $repo ("DBFZ_RIFF_ATRAC9_APP0_V1_8_15_1_1_RESULT_"+(Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force -Path $out|Out-Null
$stdout=Join-Path $out "dragonball_stdout.log";$stderr=Join-Path $out "dragonball_stderr.log"
Get-Process SharpEmu -ErrorAction SilentlyContinue|Stop-Process -Force
$p=Start-Process -FilePath $exe -ArgumentList @($Game) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
$deadline=(Get-Date).AddSeconds($Seconds)
while(-not $p.HasExited -and (Get-Date) -lt $deadline){Start-Sleep 1;$p.Refresh()}
$survived=-not $p.HasExited
if($survived){Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue}
$l=if(Test-Path -LiteralPath $stderr){@(Get-Content -LiteralPath $stderr)}else{@()}
$progress=@($l|Select-String 'dbfz\.import_progress')
$riff=@($l|Select-String -SimpleMatch '[DBFZ-NGS2-18151][RIFF]')
$atrac=@($riff|Where-Object {$_.Line -match 'atrac9=True'})
$mkdir=@($l|Select-String -Pattern 'PERMISSION_DENIED \(1-LFLmRFxxM\)')
$open=@($l|Select-String -Pattern 'PERMISSION_DENIED \(1G3lF1Gg1k8\)')
$apr=@($l|Select-String -Pattern 'result: -1 \(gEpBkcwxUjw\)')
$unresolved=@($l|Select-String -Pattern 'unresolved:')
$fatal=@($l|Select-String -Pattern 'Fatal|UnmanagedCallersOnly|Native exception|DeviceLost')
$video=@($l|Select-String -Pattern 'VideoOut|flip|PresentTaken|swapchain')
$last=if($progress.Count){$progress[-1].Line}else{'<none>'}
$s=@(
 "Dragon Ball FighterZ RIFF/ATRAC9 + App0 Repair V1.8.15.1",
 "RuntimeSurvivedWindow=$survived",
 "RiffParseLines=$($riff.Count)",
 "Atrac9ConfirmedLines=$($atrac.Count)",
 "MkdirPermissionDenied=$($mkdir.Count)",
 "OpenPermissionDenied=$($open.Count)",
 "AprResolveMiss=$($apr.Count)",
 "UnresolvedImportCount=$($unresolved.Count)",
 "FatalOrDeviceLost=$($fatal.Count)",
 "VideoOutFlipEvidence=$($video.Count)",
 "LastImportProgress=$last"
)
$s|Set-Content -LiteralPath (Join-Path $out "SUMMARY.txt") -Encoding utf8
$riff.Line|Set-Content -LiteralPath (Join-Path $out "RIFF_ATRAC9.log") -Encoding utf8
$progress.Line|Set-Content -LiteralPath (Join-Path $out "IMPORT_PROGRESS.log") -Encoding utf8
$unresolved.Line|Set-Content -LiteralPath (Join-Path $out "UNRESOLVED.log") -Encoding utf8
$zip="$out.zip";Compress-Archive -Path (Join-Path $out "*") -DestinationPath $zip -Force
Write-Host ($s -join "`n")
Write-Host "[DBFZ-RIFF-181511] RESULT ZIP: $zip"
