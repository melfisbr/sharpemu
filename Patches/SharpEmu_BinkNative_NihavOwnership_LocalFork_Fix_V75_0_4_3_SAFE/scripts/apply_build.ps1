param([switch]$SkipBuild)
. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'precheck.ps1')
$repo=Get-RepositoryRoot;$patches=Get-PatchesRoot;Stop-SharpEmu
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$stage=Join-Path $patches "SharpEmu_V75_0_4_3_BACKUP_STAGE_$stamp"
$backup=Join-Path $patches "SharpEmu_V75_0_4_3_BACKUP_$stamp.zip"
New-Item -ItemType Directory -Path $stage -Force|Out-Null
$changed=0
function Backup-One([string]$Path){
  $rel=$Path.Substring($repo.TrimEnd('\').Length).TrimStart('\')
  $back=Join-Path $stage $rel;New-Item -ItemType Directory -Path (Split-Path -Parent $back) -Force|Out-Null;Copy-Item -LiteralPath $Path -Destination $back -Force
}
try{
  foreach($b in Get-FixedBaselines){
    $dst=Join-Path $repo $b.Rel;$sha=Get-Sha $dst
    if($sha -eq $b.Patched){continue}
    Backup-One $dst
    $payload=Join-Path (Get-PackageRootV75043) ('payload\'+$b.Rel)
    if(-not(Test-Path -LiteralPath $payload)){throw "$script:Tag payload missing $($b.Rel)"}
    Copy-Item -LiteralPath $payload -Destination $dst -Force
    if((Get-Sha $dst)-ne $b.Patched){throw "$script:Tag patched sha mismatch $($b.Rel)"}
    $changed++
  }
  foreach($s in Get-StructuralTargets){
    $dst=Join-Path $repo $s.Rel
    $preview=Invoke-StructuralTransform -Path $dst -TransformRelative $s.Transform
    if($preview.Applied -gt 0){Backup-One $dst;$r=Invoke-StructuralTransform -Path $dst -TransformRelative $s.Transform -Apply;$changed++;Write-Tag "STRUCTURAL_APPLIED $($s.Rel) hunks_applied=$($r.Applied) exact_already=$($r.Already) semantic_already=$($r.SemanticAlready) optional_absent=$($r.OptionalAbsent)"}
    else{Write-Tag "STRUCTURAL_ALREADY_APPLIED $($s.Rel) hunks=$($preview.Hunks)"}
  }
  foreach($plugin in Get-PluginDirs){
    $old=Join-Path $plugin 'SharpEmu.BinkNative.dll'
    if(Test-Path -LiteralPath $old -PathType Leaf){Backup-One $old}
  }
  if((Get-ChildItem $stage -Recurse -File).Count -gt 0){Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $backup -CompressionLevel Optimal -Force}
}finally{if(Test-Path $stage){Remove-Item $stage -Recurse -Force}}
if(-not$SkipBuild){
  $project=Join-Path $repo 'src\SharpEmu.GUI\SharpEmu.GUI.csproj'
  if(-not(Test-Path $project)){throw "$script:Tag GUI project missing: $project"}
  $dotnet=(Get-Command dotnet -CommandType Application -ErrorAction Stop).Source
  $buildLog=Join-Path $patches "SharpEmu_V75_0_4_3_BUILD_$stamp.log"
  Write-Tag "BUILD Release project=$project log=$buildLog"
  & $dotnet build $project -c Release -r win-x64 2>&1 | Tee-Object -FilePath $buildLog
  if($LASTEXITCODE -ne 0){throw "$script:Tag BUILD FAILED exit=$LASTEXITCODE log=$buildLog"}
}
$adapter=Get-AdapterPath
foreach($plugin in Get-PluginDirs){New-Item -ItemType Directory -Path $plugin -Force|Out-Null;Copy-Item $adapter (Join-Path $plugin 'SharpEmu.BinkNative.dll') -Force;Write-Tag "DEPLOYED $(Join-Path $plugin 'SharpEmu.BinkNative.dll')"}
foreach($s in Get-StructuralTargets){
  $probe=Join-Path $repo $s.Rel;$text=[IO.File]::ReadAllText($probe)
  if(-not $text.Contains($s.Marker)){throw "$script:Tag ownership marker missing after apply: $probe"}
}
$backupValue=if(Test-Path -LiteralPath $backup -PathType Leaf){$backup}else{''}
$state=[ordered]@{Version='75.0.4.3';Timestamp=$stamp;RepositoryRoot=$repo;Backup=$backupValue;ChangedSourceFiles=$changed;AdapterSha=(Get-Sha $adapter);RuntimePolicy='local-only';StructuralRebase=$true;PreserveLocalFork=$true;GitUsed=$false}
$state|ConvertTo-Json|Set-Content -LiteralPath (Get-StatePath) -Encoding UTF8
Write-Tag "APPLY+BUILD PASSED nihav_owner=native-rad-exclusive changed=$changed backup=$($state.Backup)"
Write-Tag 'NEXT: RUN_4_SETUP_FFMPEGCORE_RUNTIME.cmd (LOCAL-ONLY; no git clone/fetch/checkout).'
