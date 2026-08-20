. "$PSScriptRoot\common.ps1"
$p=Presenter; $patches=Patches
$ps=[IO.File]::ReadAllText($p)
$o=@('[V74.0.84.2] DIAGNOSTIC START'); $bad=0
$checks=@(
    ,@('v841_color_contract_preserved',($ps.Contains('SHARPEMU_V74_0_84_1_UI_BINK_COLOR_CONTRACT')))
    ,@('frame_ownership_field',($ps.Contains('SHARPEMU_V74_0_84_2_UI_BINK_FRAME_OWNERSHIP')))
    ,@('presenter_owned_copy',($ps.Contains('pixels.AsSpan().CopyTo(_v740842OwnedUiBinkFramePixels)')))
    ,@('sticky_plane_helper',($ps.Contains('SHARPEMU_V74_0_84_2_UI_BINK_STICKY_PLANE_INTEGRITY')))
    ,@('sticky_fallback_call',($ps.Contains('return FindLearnedUiBinkTextureBindingsV740842(textures);')))
    ,@('plane_learning',($ps.Contains('_v740842LearnedUiBinkLumaAddresses.Add(') -and $ps.Contains('_v740842LearnedUiBinkChromaAddresses.Add(')))
    ,@('storage_guard_preserved',($ps.Contains('texture.IsStorage ||')))
    ,@('build_artifact_exists',(Test-Path (Join-Path (RepoRoot) 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe')))
)
foreach ($c in $checks) { $o+="$($c[0])=$($c[1])"; if (-not $c[1]) { $bad++ } }
$o+="PresenterSHA256=$(Sha $p)"
if ($bad) { $o+="[V74.0.84.2] DIAGNOSTIC FAILED issues=$bad" } else { $o+='[V74.0.84.2] DIAGNOSTIC PASSED.' }
$o | ForEach-Object { Write-Host $_ }
$stamp=Get-Date -Format yyyyMMdd_HHmmss
$stage=Join-Path $env:TEMP ("SharpEmuV740842Diag_"+$stamp)
New-Item -ItemType Directory -Force $stage | Out-Null
$o | Set-Content (Join-Path $stage 'diagnostic.log') -Encoding UTF8
$latest=Get-ChildItem $patches -Filter 'SharpEmu_V74_0_84_2_UI_BINK_INTEGRITY_BUILD_*.log' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($latest) { Copy-Item $latest.FullName (Join-Path $stage 'build.log') }
$z=Join-Path $patches ("SharpEmu_V74_0_84_2_UI_BINK_INTEGRITY_DIAGNOSTIC_RESULT_"+$stamp+'.zip')
Compress-Archive (Join-Path $stage '*') $z -Force
Remove-Item $stage -Recurse -Force
Write-Host "RESULT ZIP: $z"
if ($bad) { exit 1 }
