param([Parameter(Mandatory=$true)][string]$PackageRoot)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$script:Tag='[V74.0.85]'
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
function Get-DeclarationSegment([string]$Text,[string]$Name){
  $needle='private static readonly bool '+$Name+' ='
  $s=$Text.IndexOf($needle,[System.StringComparison]::Ordinal)
  if($s -lt 0){return $null}
  $e=$Text.IndexOf(';',$s,[System.StringComparison]::Ordinal)
  if($e -lt 0){return $null}
  return [pscustomobject]@{Start=$s;Length=($e-$s+1);Text=$Text.Substring($s,$e-$s+1)}
}
function Get-MethodSegment([string]$Text,[string]$Name){
  $pattern='(?m)^\s*private\s+static[^\r\n]*\b'+[regex]::Escape($Name)+'\s*\('
  $m=[regex]::Match($Text,$pattern)
  if(-not $m.Success){return $null}
  $brace=$Text.IndexOf('{',$m.Index)
  if($brace -lt 0){return $null}
  $depth=0
  for($i=$brace;$i -lt $Text.Length;$i++){
    $ch=$Text[$i]
    if($ch -eq '{'){$depth++}
    elseif($ch -eq '}'){$depth--;if($depth -eq 0){return [pscustomobject]@{Start=$m.Index;Length=($i-$m.Index+1);Text=$Text.Substring($m.Index,$i-$m.Index+1)}}}
  }
  return $null
}
function Assert-Repo{
 if(-not(Test-Path -LiteralPath $script:AgcPath -PathType Leaf)){throw "$script:Tag AgcExports.cs ausente: $script:AgcPath"}
 if(-not(Test-Path -LiteralPath $script:PresenterPath -PathType Leaf)){throw "$script:Tag Presenter ausente: $script:PresenterPath"}
}
function Assert-StructuralContracts{
 Assert-Repo
 $a=Read-Utf8 $script:AgcPath;$p=Read-Utf8 $script:PresenterPath
 $pm4=Get-DeclarationSegment $a '_kytyPm4BlockedSchedulerV74030'
 $inline=Get-DeclarationSegment $a '_kytyInlineWriteDataV74030'
 $tex=Get-MethodSegment $a 'CreateGuestDrawTextures'
 $std=Get-MethodSegment $a 'ApplySubmittedStandardReleaseMem'
 $rel=Get-MethodSegment $a 'ApplySubmittedReleaseMem'
 $side=Get-MethodSegment $a 'SubmitOrderedGpuSideEffect'
 $checks=[ordered]@{
   V812=(Get-Count $p 'SHARPEMU_V74_0_81_2_SEMANTIC_BOUNDARY_REPAIR')
   V82=(Get-Count $p 'SHARPEMU_V74_0_82_NONBLOCKING_VISIBILITY_DCC_INDEX')
   V84=(Get-Count $p 'SHARPEMU_V74_0_84_SUBMISSION_HEADROOM_ADAPTIVE')
   Pm4Definitions=(Get-Count $a '(?m)^\s*private\s+static\s+readonly\s+bool\s+_kytyPm4BlockedSchedulerV74030\s*=')
   InlineDefinitions=(Get-Count $a '(?m)^\s*private\s+static\s+readonly\s+bool\s+_kytyInlineWriteDataV74030\s*=')
   TextureFactoryDefinitions=(Get-Count $a '(?m)^\s*private\s+static\s+IReadOnlyList<GuestDrawTexture>\s+CreateGuestDrawTextures\s*\(')
   StandardReleaseDefinitions=(Get-Count $a '(?m)^\s*private\s+static\s+void\s+ApplySubmittedStandardReleaseMem\s*\(')
   ReleaseDefinitions=(Get-Count $a '(?m)^\s*private\s+static\s+void\s+ApplySubmittedReleaseMem\s*\(')
   SideEffectDefinitions=(Get-Count $a '(?m)^\s*private\s+static\s+void\s+SubmitOrderedGpuSideEffect\s*\(')
   V85=(Get-Count $a 'SHARPEMU_V74_0_85_AGGRESSIVE_PM4_LOCAL_PAYLOAD_RELEASE_QUEUE')
 }
 foreach($e in $checks.GetEnumerator()){Write-Host "$script:Tag $($e.Key)=$($e.Value)"}
 if($checks.V812 -lt 1 -or $checks.V82 -lt 1 -or $checks.V84 -lt 1){throw "$script:Tag Base V81.2/V82/V84 incompleta."}
 if($checks.Pm4Definitions -ne 1 -or $null -eq $pm4){throw "$script:Tag PM4 blocked scheduler field ambiguo/ausente."}
 if($checks.InlineDefinitions -ne 1 -or $null -eq $inline){throw "$script:Tag inline WRITE_DATA field ambiguo/ausente."}
 if($checks.TextureFactoryDefinitions -ne 1 -or $null -eq $tex){throw "$script:Tag CreateGuestDrawTextures ambiguo/ausente."}
 if($checks.StandardReleaseDefinitions -ne 1 -or $null -eq $std){throw "$script:Tag standard RELEASE_MEM ambiguo/ausente."}
 if($checks.ReleaseDefinitions -ne 1 -or $null -eq $rel){throw "$script:Tag AGC RELEASE_MEM ambiguo/ausente."}
 if($checks.SideEffectDefinitions -ne 1 -or $null -eq $side){throw "$script:Tag SubmitOrderedGpuSideEffect ambiguo/ausente."}
 if(-not $tex.Text.Contains('TryCreateGuestDrawTexture(')){throw "$script:Tag texture factory contract divergiu."}
 if(-not $side.Text.Contains('requiresGpuBufferReadback')){throw "$script:Tag ordered side-effect readback contract ausente."}
 return [pscustomobject]@{Agc=$a;Presenter=$p;Pm4=$pm4;Inline=$inline;Tex=$tex;Std=$std;Rel=$rel;Side=$side}
}
function New-Backup{
 if(-not(Test-Path -LiteralPath $script:BackupRoot)){New-Item -ItemType Directory -Path $script:BackupRoot|Out-Null}
 $dir=Join-Path $script:BackupRoot ("AggressivePm4PayloadReleaseV74085_"+(Get-Date -Format 'yyyyMMdd_HHmmss'))
 New-Item -ItemType Directory -Path $dir|Out-Null
 Copy-Item -LiteralPath $script:AgcPath -Destination (Join-Path $dir 'AgcExports.cs') -Force
 Write-Utf8NoBom $script:StateFile $dir
 return $dir
}
function Restore-Backup([string]$Dir){$x=Join-Path $Dir 'AgcExports.cs';if(-not(Test-Path -LiteralPath $x)){throw "$script:Tag backup AgcExports ausente: $x"};Copy-Item -LiteralPath $x -Destination $script:AgcPath -Force}
function Quote-ProcessArgument([string]$Value){if($null -eq $Value){return '""'};return '"'+($Value -replace '(\\*)"','$1$1\"' -replace '(\\+)$','$1$1')+'"'}
function Find-SharpEmuExe{$c=@((Join-Path $script:RepoRoot 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'),(Join-Path $script:RepoRoot 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.CLI.exe'));foreach($x in $c){if(Test-Path -LiteralPath $x -PathType Leaf){return $x}};return $null}
