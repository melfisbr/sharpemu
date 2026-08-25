Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:Tag='[V75.0.3.1-BINK-NATIVE-AV]'
$script:PackageRoot=Split-Path -Parent $PSScriptRoot

function Write-Tag([string]$m){ Write-Host "$script:Tag $m" }
function Get-PatchesRoot { Split-Path -Parent $script:PackageRoot }
function Get-RepositoryRoot {
    $r=Split-Path -Parent (Get-PatchesRoot)
    if(-not(Test-Path -LiteralPath (Join-Path $r 'src') -PathType Container)){ throw "$script:Tag repo root not found: $r" }
    $r
}
function Get-Sha([string]$p){ if(Test-Path -LiteralPath $p -PathType Leaf){ (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToUpperInvariant() } else { '' } }
function Get-Adapter { Join-Path $script:PackageRoot 'bin\SharpEmu.BinkNative.dll' }
function Get-StatePath { Join-Path (Get-PatchesRoot) 'SharpEmu_V75_0_3_1_BINK_NATIVE_AV_STATE.json' }
function Get-DeployDirs {
    $r=Get-RepositoryRoot
    @(
      (Join-Path $r 'artifacts\bin\Release\net10.0\win-x64\plugins\bink2'),
      (Join-Path $r 'artifacts\bin\Debug\net10.0\win-x64\plugins\bink2')
    )
}
function Get-PeMachine([string]$Path){
    $s=[IO.File]::OpenRead($Path)
    try{
      $br=New-Object IO.BinaryReader($s)
      if($br.ReadUInt16() -ne 0x5A4D){ return 0 }
      $s.Position=0x3C; $pe=$br.ReadInt32()
      if($pe -lt 0 -or $pe -gt ($s.Length-8)){ return 0 }
      $s.Position=$pe
      if($br.ReadUInt32() -ne 0x00004550){ return 0 }
      [int]$br.ReadUInt16()
    } finally { $s.Dispose() }
}
function Find-DumpBin {
    $vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if(-not(Test-Path -LiteralPath $vswhere)){ return $null }
    $install=& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if([string]::IsNullOrWhiteSpace($install)){ return $null }
    $tools=Get-ChildItem -LiteralPath (Join-Path $install.Trim() 'VC\Tools\MSVC') -Directory -ErrorAction SilentlyContinue|Sort-Object Name -Descending
    foreach($t in $tools){
      $d=Join-Path $t.FullName 'bin\Hostx64\x64\dumpbin.exe'
      if(Test-Path -LiteralPath $d){ return $d }
    }
    $null
}
function Test-Exports([string]$Path,[string[]]$Required,[string[]]$AnyOf=@()){
    $dump=Find-DumpBin
    if([string]::IsNullOrWhiteSpace($dump)){ return [pscustomobject]@{Known=$false;RequiredOk=$false;AnyOk=$false;Text='dumpbin unavailable'} }
    $o=@(& $dump /nologo /exports $Path 2>&1|ForEach-Object{$_.ToString()})
    $reqOk=$true
    foreach($n in $Required){ if(@($o|Select-String -SimpleMatch $n).Count -eq 0){ $reqOk=$false } }
    $anyOk=($AnyOf.Count -eq 0)
    foreach($n in $AnyOf){ if(@($o|Select-String -SimpleMatch $n).Count -gt 0){ $anyOk=$true; break } }
    [pscustomobject]@{Known=$true;RequiredOk=$reqOk;AnyOk=$anyOk;Text=($o -join "`n")}
}
function Find-Runtime([string]$Explicit=''){
    $c=New-Object System.Collections.Generic.List[string]
    if(-not[string]::IsNullOrWhiteSpace($Explicit)){ $c.Add($Explicit.Trim().Trim('"')) }
    $envp=[Environment]::GetEnvironmentVariable('SHARPEMU_BINK_RUNTIME_DLL','Process'); if($envp){$c.Add($envp)}
    foreach($d in Get-DeployDirs){$c.Add((Join-Path $d 'bink2w64.dll'))}
    $repo=Get-RepositoryRoot
    $c.Add((Join-Path $repo 'ThirdParty\BinkRuntime\bink2w64.dll'))
    $seen=@{}
    foreach($p in $c){
      try{$f=[IO.Path]::GetFullPath($p)}catch{continue}
      if($seen.ContainsKey($f)){continue};$seen[$f]=$true
      if(Test-Path -LiteralPath $f -PathType Leaf){return $f}
    }
    ''
}
