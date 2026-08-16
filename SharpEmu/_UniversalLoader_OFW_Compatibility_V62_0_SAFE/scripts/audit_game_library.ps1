param([string]$RepositoryRoot,[string]$GamesRoot='F:\JOGOSPS5')
. (Join-Path $PSScriptRoot 'common.ps1')
$r=Resolve-Repo $RepositoryRoot
$self=Join-Path $r 'src\SharpEmu.Core\Loader\SelfLoader.cs'
if([IO.File]::ReadAllText($self).IndexOf('V62.0 UNIVERSAL_LOADER_OFW',[StringComparison]::Ordinal)-lt 0){throw 'AUDIT ERROR: apply V62.0 first.'}
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'; $out=Join-Path $r "SharpEmu_V62_0_LOADER_MATRIX_$stamp"; New-Item -ItemType Directory -Force -Path $out|Out-Null
$rows=@()
if(Test-Path -LiteralPath $GamesRoot -PathType Container){
 foreach($f in Get-ChildItem -LiteralPath $GamesRoot -Recurse -File -Filter eboot.bin -ErrorAction SilentlyContinue){
  $b=[IO.File]::ReadAllBytes($f.FullName); $kind='unknown/encrypted';$off=-1;$m=-1;$abi=-1;$av=-1;$pe=-1;$pn=-1
  if($b.Length-ge64){
   if($b[0]-eq0x7F-and$b[1]-eq0x45-and$b[2]-eq0x4C-and$b[3]-eq0x46){$kind='bare-elf';$off=0}
   else{$lim=[Math]::Min($b.Length-64,4*1024*1024);for($i=4;$i-le$lim;$i+=4){if($b[$i]-eq0x7F-and$b[$i+1]-eq0x45-and$b[$i+2]-eq0x4C-and$b[$i+3]-eq0x46){$kind='wrapped-elf-candidate';$off=$i;break}}}
  }
  if($off-ge0){$m=[BitConverter]::ToUInt16($b,$off+18);$abi=$b[$off+7];$av=$b[$off+8];$pe=[BitConverter]::ToUInt16($b,$off+54);$pn=[BitConverter]::ToUInt16($b,$off+56)}
  $rows+=[pscustomobject]@{Path=$f.FullName;Kind=$kind;ElfOffset=if($off-ge0){'0x{0:X}'-f$off}else{''};Machine=$m;Abi=$abi;AbiVersion=$av;PhEntSize=$pe;PhNum=$pn;Bytes=$b.Length}
 }
}
$rows|Export-Csv (Join-Path $out 'EBOOT_MATRIX.csv') -NoTypeInformation -Encoding UTF8
@('version=62.0',"games_root=$GamesRoot","eboot_count=$($rows.Count)","bare_elf=$(($rows|Where-Object Kind -eq 'bare-elf').Count)","wrapped_candidates=$(($rows|Where-Object Kind -eq 'wrapped-elf-candidate').Count)","unknown_or_encrypted=$(($rows|Where-Object Kind -eq 'unknown/encrypted').Count)",'game_started=0')|Set-Content (Join-Path $out 'SUMMARY.txt') -Encoding UTF8
Copy-Item $self (Join-Path $out 'SelfLoader.cs.snapshot')
Copy-Item (Join-Path $r 'src\SharpEmu.Core\Loader\ProgramHeader.cs') (Join-Path $out 'ProgramHeader.cs.snapshot')
$zip="$out.zip";Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zip -Force
Write-Host "[V62.0] RESULT: $zip"
