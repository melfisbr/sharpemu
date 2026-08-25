. (Join-Path $PSScriptRoot 'common.ps1')
$statePath=Get-StatePath
if(-not(Test-Path -LiteralPath $statePath)){throw "$script:Tag state missing"}
$s=Get-Content $statePath -Raw|ConvertFrom-Json
$restored=0
foreach($bk in @($s.backups)){
 if(-not(Test-Path -LiteralPath $bk)){continue}
 $name=[IO.Path]::GetFileName($bk)
 $isRelease=$name -match '_Release_'
 $dir=@(Get-DeployDirs)|Where-Object{ if($isRelease){$_ -match '\\Release\\'}else{$_ -match '\\Debug\\'} }|Select-Object -First 1
 if($dir){Copy-Item $bk (Join-Path $dir 'SharpEmu.BinkNative.dll') -Force;$restored++}
}
if($restored -eq 0){foreach($d in Get-DeployDirs){$p=Join-Path $d 'SharpEmu.BinkNative.dll';if(Test-Path $p){Remove-Item $p -Force}}}
Write-Tag "ROLLBACK COMPLETE restored=$restored"
