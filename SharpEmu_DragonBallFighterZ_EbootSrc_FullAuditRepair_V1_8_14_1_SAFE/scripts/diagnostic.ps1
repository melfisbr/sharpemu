param([int]$Seconds=360)
. (Join-Path $PSScriptRoot "common.ps1")
$repo=Find-RepoRoot
$game=Get-EbootPath
$exe=Join-Path $repo "artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe"
if(-not (Test-Path -LiteralPath $game -PathType Leaf)) { throw "DBFZ eboot missing: $game" }
if(-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "SharpEmu.exe missing: $exe" }

$result=Join-Path $repo ("DBFZ_FULL_AUDIT_REPAIR_V1_8_14_1_RESULT_"+(Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force -Path $result | Out-Null
$stdout=Join-Path $result "dragonball_stdout.log"
$stderr=Join-Path $result "dragonball_stderr.log"
Get-Process SharpEmu -ErrorAction SilentlyContinue | Stop-Process -Force

$p=Start-Process -FilePath $exe -ArgumentList @($game) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
$deadline=(Get-Date).AddSeconds($Seconds)
while(-not $p.HasExited -and (Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 1
    $p.Refresh()
}
$survived=-not $p.HasExited
if($survived) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }

$lines=if(Test-Path -LiteralPath $stderr -PathType Leaf) { @(Get-Content -LiteralPath $stderr) } else { @() }
$progress=@($lines|Select-String -Pattern 'dbfz\.import_progress')
$ngsInvalid=@($lines|Select-String -Pattern 'INVALID_ARGUMENT \(hyVLT2VlOYk\)')
$ngsOk=@($lines|Select-String -SimpleMatch '[DBFZ-NGS2-18141][PARSE_OK]')
$mkdirDenied=@($lines|Select-String -Pattern 'PERMISSION_DENIED \(1-LFLmRFxxM\)')
$openDenied=@($lines|Select-String -Pattern 'PERMISSION_DENIED \(1G3lF1Gg1k8\)')
$apr=@($lines|Select-String -Pattern '\(gEpBkcwxUjw\)')
$unresolved=@($lines|Select-String -Pattern 'unresolved:')
$fatal=@($lines|Select-String -Pattern 'Fatal|UnmanagedCallersOnly|Native exception|DeviceLost')
$video=@($lines|Select-String -Pattern 'VideoOut|swapchain|flip|PresentTaken')
$last=if($progress.Count -gt 0) { $progress[-1].Line } else { "<none>" }

$summary=@(
 "Dragon Ball FighterZ Full Audit Repair V1.8.14.1",
 "DiagnosticSeconds=$Seconds",
 "RuntimeSurvivedWindow=$survived",
 "Ngs2InvalidArgumentCount=$($ngsInvalid.Count)",
 "Ngs2CompatSuccessTraceCount=$($ngsOk.Count)",
 "MkdirPermissionDenied=$($mkdirDenied.Count)",
 "OpenPermissionDenied=$($openDenied.Count)",
 "AprResultLines=$($apr.Count)",
 "UnresolvedImportCount=$($unresolved.Count)",
 "FatalOrDeviceLost=$($fatal.Count)",
 "VideoOutFlipEvidence=$($video.Count)",
 "LastImportProgress=$last"
)
$summary|Set-Content -LiteralPath (Join-Path $result "SUMMARY.txt") -Encoding utf8
$progress.Line|Set-Content -LiteralPath (Join-Path $result "IMPORT_PROGRESS.log") -Encoding utf8
$unresolved.Line|Set-Content -LiteralPath (Join-Path $result "UNRESOLVED.log") -Encoding utf8
$ngsOk.Line|Set-Content -LiteralPath (Join-Path $result "NGS2_PARSE_SUCCESS.log") -Encoding utf8
$apr.Line|Set-Content -LiteralPath (Join-Path $result "APR_RESULTS.log") -Encoding utf8

$zip="$result.zip"
Compress-Archive -Path (Join-Path $result "*") -DestinationPath $zip -Force
Write-Host ($summary -join "`n")
Write-Host "[DBFZ-AUDIT-181411] RESULT ZIP: $zip"
