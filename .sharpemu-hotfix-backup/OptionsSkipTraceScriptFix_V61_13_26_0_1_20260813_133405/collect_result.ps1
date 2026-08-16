. (Join-Path $PSScriptRoot 'common.ps1')
$root=Resolve-RepoRoot $RepositoryRoot
$dir=Get-ChildItem -LiteralPath $root -Directory|Where-Object Name -like 'SharpEmu_V61_13_26_0_OptionsSkipTrace_*'|Sort-Object LastWriteTime -Descending|Select-Object -First 1
if($null-eq$dir){throw '[V61.13.26.0] No trace result directory found.'}
$files=Get-SourceFiles $root
$matches=Find-SourceMatches $files @('Keyboard controls are active','Tab','Options','scePadRead','scePadReadState','RunConfiguredBootSequence','ObserveMovie','bink2.direct_boot')
$matches|Format-Table -AutoSize|Out-String|Set-Content (Join-Path $dir.FullName 'SOURCE_FLOW_AUDIT.txt') -Encoding UTF8
$host=Join-Path $root 'src\SharpEmu.Libs\Media\HostMovieBridge.cs'
Write-Context $host @('RunConfiguredBootSequence','ObserveMovie','bink2.direct_boot') (Join-Path $dir.FullName 'HOST_MOVIE_BRIDGE_CONTEXT.txt')
$padFiles=@($matches|Where-Object{$_.Pattern -in @('Tab','Options','scePadRead','scePadReadState')}|Select-Object -ExpandProperty File -Unique)
$i=0
foreach($f in $padFiles|Select-Object -First 8){$i++;Write-Context $f @('Tab','Options','scePadRead','scePadReadState') (Join-Path $dir.FullName ("PAD_INPUT_CONTEXT_{0:D2}.txt" -f $i))}
$zip=Join-Path $root 'SharpEmu_V61_13_26_0_OptionsSkipTrace_RESULT.zip'
if(Test-Path $zip){Remove-Item $zip -Force}
Compress-Archive -LiteralPath $dir.FullName -DestinationPath $zip -CompressionLevel Optimal
Write-Host "[V61.13.26.0] RESULT ZIP: $zip"
