param([Parameter(Mandatory=$true)][string]$PackageRoot)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$script:Tag='[V74.0.86.4]'
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
function Get-StaticFieldSegment([string]$Text,[string]$Name){
  $pattern='(?m)^\s*private\s+static\s+readonly\s+[^\r\n=]+\s+'+[regex]::Escape($Name)+'\s*='
  $m=[regex]::Match($Text,$pattern)
  if(-not $m.Success){return $null}
  $e=$Text.IndexOf(';',$m.Index,[System.StringComparison]::Ordinal)
  if($e -lt 0){return $null}
  return [pscustomobject]@{Start=$m.Index;Length=($e-$m.Index+1);Text=$Text.Substring($m.Index,$e-$m.Index+1)}
}
function Get-MethodSegment([string]$Text,[string]$Name){
  $pattern='(?m)^\s*(?:private|internal|public)\s+static[^\r\n]*\b'+[regex]::Escape($Name)+'\s*\('
  $m=[regex]::Match($Text,$pattern)
  if(-not $m.Success){return $null}
  $brace=$Text.IndexOf('{',$m.Index,[System.StringComparison]::Ordinal)
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
 $ttl=Get-StaticFieldSegment $a '_v74016LargeSnapshotReuseTtlMs'
 $budget=Get-StaticFieldSegment $p 'V7408StandaloneTextureCacheBudgetBytes'
 $mark=Get-MethodSegment $p 'MarkTextureContentCached'
 $checks=[ordered]@{
   V812=(Get-Count $p 'SHARPEMU_V74_0_81_2_SEMANTIC_BOUNDARY_REPAIR')
   V82=(Get-Count $p 'SHARPEMU_V74_0_82_NONBLOCKING_VISIBILITY_DCC_INDEX')
   V84=(Get-Count $p 'SHARPEMU_V74_0_84_SUBMISSION_HEADROOM_ADAPTIVE')
   V85=(Get-Count $a 'SHARPEMU_V74_0_85_AGGRESSIVE_PM4_LOCAL_PAYLOAD_RELEASE_QUEUE')
   V864Agc=(Get-Count $a 'SHARPEMU_V74_0_86_4_RESIDENT_TEXTURE_RETENTION_SEMICOLON_ANCHOR')
   V864Presenter=(Get-Count $p 'SHARPEMU_V74_0_86_4_RESIDENT_TEXTURE_RETENTION_SEMICOLON_ANCHOR')
   TtlDefinitions=(Get-Count $a '(?m)^\s*private\s+static\s+readonly\s+long\s+_v74016LargeSnapshotReuseTtlMs\s*=')
   BudgetDefinitions=(Get-Count $p '(?m)^\s*private\s+static\s+readonly\s+ulong\s+V7408StandaloneTextureCacheBudgetBytes\s*=')
   MarkDefinitions=(Get-Count $p '(?m)^\s*private\s+static\s+void\s+MarkTextureContentCached\s*\(')
   ArrayCache=(Get-Count $a '_v74064LargeArraySnapshotCache')
   LargeTextureCache=(Get-Count $a '_v7405LargeTextureSnapshotCache')
 }
 foreach($e in $checks.GetEnumerator()){Write-Host "$script:Tag $($e.Key)=$($e.Value)"}
 if($checks.V812 -lt 1 -or $checks.V82 -lt 1 -or $checks.V84 -lt 1 -or $checks.V85 -lt 1){throw "$script:Tag Base V81.2/V82/V84/V85 incompleta."}
 if($checks.TtlDefinitions -ne 1 -or $null -eq $ttl){throw "$script:Tag large snapshot TTL ambiguo/ausente."}
 if($checks.BudgetDefinitions -ne 1 -or $null -eq $budget){throw "$script:Tag standalone texture budget ambiguo/ausente."}
 if($checks.MarkDefinitions -ne 1 -or $null -eq $mark){throw "$script:Tag MarkTextureContentCached ambiguo/ausente."}
 if($checks.ArrayCache -lt 3 -or $checks.LargeTextureCache -lt 3){throw "$script:Tag CPU snapshot cache contracts ausentes."}
 if(-not $mark.Text.Contains('_cachedTextureIdentities.TryAdd(identity, 0);')){throw "$script:Tag presenter cache-mark insertion contract ausente."}
 return [pscustomobject]@{Agc=$a;Presenter=$p;Ttl=$ttl;Budget=$budget;Mark=$mark}
}
function New-Backup{
 if(-not(Test-Path -LiteralPath $script:BackupRoot)){New-Item -ItemType Directory -Path $script:BackupRoot|Out-Null}
 $dir=Join-Path $script:BackupRoot ("ResidentTextureRetentionV740864_"+(Get-Date -Format 'yyyyMMdd_HHmmss'))
 New-Item -ItemType Directory -Path $dir|Out-Null
 Copy-Item -LiteralPath $script:AgcPath -Destination (Join-Path $dir 'AgcExports.cs') -Force
 Copy-Item -LiteralPath $script:PresenterPath -Destination (Join-Path $dir 'VulkanVideoPresenter.cs') -Force
 Write-Utf8NoBom $script:StateFile $dir
 return $dir
}
function Restore-Backup([string]$Dir){
 $a=Join-Path $Dir 'AgcExports.cs';$p=Join-Path $Dir 'VulkanVideoPresenter.cs'
 if(-not(Test-Path -LiteralPath $a)){throw "$script:Tag backup AgcExports ausente: $a"}
 if(-not(Test-Path -LiteralPath $p)){throw "$script:Tag backup Presenter ausente: $p"}
 Copy-Item -LiteralPath $a -Destination $script:AgcPath -Force
 Copy-Item -LiteralPath $p -Destination $script:PresenterPath -Force
}
function Find-SharpEmuExe{$c=@((Join-Path $script:RepoRoot 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'),(Join-Path $script:RepoRoot 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.CLI.exe'));foreach($x in $c){if(Test-Path -LiteralPath $x -PathType Leaf){return $x}};return $null}
