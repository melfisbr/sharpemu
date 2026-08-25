. (Join-Path $PSScriptRoot 'common.ps1')
$statePath=Get-StatePath
if(-not(Test-Path $statePath)){throw "$script:Tag state not found: $statePath"}
$state=Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json;$repo=Get-RepositoryRoot;Stop-SharpEmu
if($state.Backup -and (Test-Path -LiteralPath $state.Backup -PathType Leaf)){
  $tmp=Join-Path (Get-PatchesRoot) ('SharpEmu_V75_0_4_1_ROLLBACK_'+(Get-Date -Format 'yyyyMMdd_HHmmss'));Expand-Archive -LiteralPath $state.Backup -DestinationPath $tmp -Force
  Get-ChildItem -LiteralPath $tmp -Recurse -File|ForEach-Object{$rel=$_.FullName.Substring($tmp.TrimEnd('\').Length).TrimStart('\');$dst=Join-Path $repo $rel;New-Item -ItemType Directory -Path (Split-Path -Parent $dst) -Force|Out-Null;Copy-Item $_.FullName $dst -Force}
  Remove-Item $tmp -Recurse -Force;Write-Tag "RESTORED backup=$($state.Backup)"
}else{Write-Tag 'No backup archive recorded; source may have already been V75.0.4.1.'}
foreach($plugin in Get-PluginDirs){$runtime=Join-Path $plugin 'ffmpeg-runtime';if((Test-Path (Join-Path $runtime '.v75_0_4_1_ffmpeg_core_runtime')) -or (Test-Path (Join-Path $runtime '.v75_0_4_ffmpeg_core_runtime'))){Remove-Item $runtime -Recurse -Force;Write-Tag "REMOVED runtime=$runtime"}}
Remove-Item $statePath -Force -ErrorAction SilentlyContinue
Write-Tag 'ROLLBACK COMPLETE. Rebuild Release before next runtime test.'
