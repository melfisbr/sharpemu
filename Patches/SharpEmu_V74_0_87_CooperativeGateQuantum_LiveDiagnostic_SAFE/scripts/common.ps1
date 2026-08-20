param([Parameter(Mandatory=$true)][string]$PackageRoot)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$script:Tag='[V74.0.87]'
$PackageRoot=$PackageRoot.Trim().Trim([char]34).Trim([char]39)
$script:PackageRoot=(Resolve-Path -LiteralPath $PackageRoot).Path.TrimEnd('\')
$script:PatchesRoot=Split-Path -Parent $script:PackageRoot
$script:RepoRoot=Split-Path -Parent $script:PatchesRoot
$script:AgcRel='src\SharpEmu.Libs\Agc\AgcExports.cs'
$script:PresenterRel='src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$script:AgcPath=Join-Path $script:RepoRoot $script:AgcRel
$script:PresenterPath=Join-Path $script:RepoRoot $script:PresenterRel
$script:BackupRoot=Join-Path $script:RepoRoot '.sharpemu-hotfix-backup'
$script:StateFile=Join-Path $script:PackageRoot 'LAST_BACKUP.txt'
function Get-Sha256([string]$Path){return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()}
function Read-Utf8([string]$Path){return [System.IO.File]::ReadAllText($Path,[System.Text.Encoding]::UTF8)}
function Write-Utf8NoBom([string]$Path,[string]$Text){$enc=New-Object System.Text.UTF8Encoding($false);[System.IO.File]::WriteAllText($Path,$Text,$enc)}
function Get-Count([string]$Text,[string]$Pattern){return ([regex]::Matches($Text,$Pattern,[System.Text.RegularExpressions.RegexOptions]::Multiline)).Count}
function Get-ContainingPrivateStaticMethodByMarker([string]$Text,[string]$Marker){
  $mi=$Text.IndexOf($Marker,[System.StringComparison]::Ordinal)
  if($mi -lt 0){return $null}
  $rx=New-Object System.Text.RegularExpressions.Regex('(?ms)^\s*private\s+static\s+[^;{}]+?\([^;{}]*?\)\s*\{')
  $chosen=$null
  foreach($m in $rx.Matches($Text)){
    if($m.Index -gt $mi){break}
    $brace=$Text.IndexOf('{',$m.Index)
    if($brace -lt 0 -or $brace -gt $mi){continue}
    $depth=0;$close=-1
    for($i=$brace;$i -lt $Text.Length;$i++){
      $ch=$Text[$i]
      if($ch -eq '{'){$depth++}
      elseif($ch -eq '}'){$depth--;if($depth -eq 0){$close=$i;break}}
    }
    if($close -ge $mi){$chosen=[pscustomobject]@{Start=$m.Index;Brace=$brace;Close=$close;Length=($close-$m.Index+1);Text=$Text.Substring($m.Index,$close-$m.Index+1)}}
  }
  if($null -eq $chosen){return $null}
  $head=$Text.Substring($chosen.Start,$chosen.Brace-$chosen.Start)
  $nm=[regex]::Match($head,'(?s)\b([A-Za-z_][A-Za-z0-9_]*)\s*\([^()]*$')
  if(-not $nm.Success){return $null}
  $sp=[regex]::Match($head,'\bSubmittedGpuState\s+([A-Za-z_][A-Za-z0-9_]*)\b')
  $chosen | Add-Member -NotePropertyName Name -NotePropertyValue $nm.Groups[1].Value
  $chosen | Add-Member -NotePropertyName StateParam -NotePropertyValue $(if($sp.Success){$sp.Groups[1].Value}else{''})
  return $chosen
}
function Assert-Repo{
 if(-not(Test-Path -LiteralPath $script:AgcPath -PathType Leaf)){throw "$script:Tag AgcExports.cs ausente: $script:AgcPath"}
 if(-not(Test-Path -LiteralPath $script:PresenterPath -PathType Leaf)){throw "$script:Tag Presenter ausente: $script:PresenterPath"}
}
function Assert-StructuralContracts{
 Assert-Repo
 $a=Read-Utf8 $script:AgcPath;$p=Read-Utf8 $script:PresenterPath
 $gate=Get-ContainingPrivateStaticMethodByMarker $a 'GATE_OWNER_WAIT_DRAIN'
 $checks=[ordered]@{
   V812=(Get-Count $p 'SHARPEMU_V74_0_81_2_SEMANTIC_BOUNDARY_REPAIR')
   V82=(Get-Count $p 'SHARPEMU_V74_0_82_NONBLOCKING_VISIBILITY_DCC_INDEX')
   V84=(Get-Count $p 'SHARPEMU_V74_0_84_SUBMISSION_HEADROOM_ADAPTIVE')
   V85=(Get-Count $a 'SHARPEMU_V74_0_85_AGGRESSIVE_PM4_LOCAL_PAYLOAD_RELEASE_QUEUE')
   V864Agc=(Get-Count $a 'SHARPEMU_V74_0_86_4_RESIDENT_TEXTURE_RETENTION_SEMICOLON_ANCHOR')
   V864Presenter=(Get-Count $p 'SHARPEMU_V74_0_86_4_RESIDENT_TEXTURE_RETENTION_SEMICOLON_ANCHOR')
   GateOwnerMarker=(Get-Count $a 'GATE_OWNER_WAIT_DRAIN')
   V87=(Get-Count $a 'SHARPEMU_V74_0_87_COOPERATIVE_GATE_QUANTUM')
 }
 foreach($e in $checks.GetEnumerator()){Write-Host "$script:Tag $($e.Key)=$($e.Value)"}
 if($checks.V812 -lt 1 -or $checks.V82 -lt 1 -or $checks.V84 -lt 1 -or $checks.V85 -lt 1){throw "$script:Tag base V81.2/V82/V84/V85 incompleta."}
 if($checks.V864Agc -lt 1 -or $checks.V864Presenter -lt 1){throw "$script:Tag V86.4 nao detectada nos dois sources."}
 if($checks.GateOwnerMarker -lt 1 -or $null -eq $gate){throw "$script:Tag metodo que contem GATE_OWNER_WAIT_DRAIN nao foi localizado estruturalmente."}
 if([string]::IsNullOrWhiteSpace($gate.StateParam)){throw "$script:Tag metodo V72 localizado, mas parametro SubmittedGpuState nao foi classificado."}
 if(-not $gate.Text.Contains('GATE_OWNER_WAIT_DRAIN')){throw "$script:Tag classificador V72 perdeu o marker."}
 return [pscustomobject]@{Agc=$a;Presenter=$p;Gate=$gate;Checks=$checks}
}
function New-Backup{
 if(-not(Test-Path -LiteralPath $script:BackupRoot)){New-Item -ItemType Directory -Path $script:BackupRoot|Out-Null}
 $dir=Join-Path $script:BackupRoot ("CooperativeGateQuantumV74087_"+(Get-Date -Format 'yyyyMMdd_HHmmss'))
 New-Item -ItemType Directory -Path $dir|Out-Null
 Copy-Item -LiteralPath $script:AgcPath -Destination (Join-Path $dir 'AgcExports.cs') -Force
 Write-Utf8NoBom $script:StateFile $dir
 return $dir
}
function Restore-Backup([string]$Dir){$x=Join-Path $Dir 'AgcExports.cs';if(-not(Test-Path -LiteralPath $x -PathType Leaf)){throw "$script:Tag backup AgcExports ausente: $x"};Copy-Item -LiteralPath $x -Destination $script:AgcPath -Force}
function Find-SharpEmuExe{$c=@((Join-Path $script:RepoRoot 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'),(Join-Path $script:RepoRoot 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.CLI.exe'));foreach($x in $c){if(Test-Path -LiteralPath $x -PathType Leaf){return $x}};return $null}
