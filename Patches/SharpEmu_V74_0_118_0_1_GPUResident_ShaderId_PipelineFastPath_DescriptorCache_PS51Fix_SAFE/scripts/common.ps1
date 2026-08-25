Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$script:Tag='[V74.0.118.0.1-GPU-RESIDENT-SHADER-ID-PIPELINE-FASTPATH-DESCRIPTOR-CACHE-PS51-FIX-SAFE]'
$script:Version='V74.0.118.0.1'
$script:StateName='SharpEmu_V74_0_118_0_1_STATE.json'
$script:LastBackupName='SharpEmu_V74_0_118_0_1_LAST_BACKUP.txt'
function Write-Tag([string]$m){Write-Host "$script:Tag $m"}
function Get-PackageRoot{Split-Path -Parent $PSScriptRoot}
function Get-PatchesRoot{Split-Path -Parent (Get-PackageRoot)}
function Get-RepositoryRoot{
 $r=Split-Path -Parent (Get-PatchesRoot)
 if(-not(Test-Path (Join-Path $r 'src') -PathType Container)){throw "$script:Tag repo not found: $r"}
 [IO.Path]::GetFullPath($r)
}
function Get-Sha([string]$p){if(Test-Path $p -PathType Leaf){(Get-FileHash $p -Algorithm SHA256).Hash.ToUpperInvariant()}else{''}}
function Write-Utf8([string]$p,[string]$t){$e=New-Object Text.UTF8Encoding($false);[IO.File]::WriteAllText($p,$t,$e)}
function Get-StatePath{Join-Path (Get-PatchesRoot) $script:StateName}
function Save-State([int]$phase,[string]$status,[hashtable]$extra){
 $o=[ordered]@{version=$script:Version;timestamp=(Get-Date).ToString('o');phase=$phase;status=$status}
 if($extra){foreach($k in $extra.Keys){$o[$k]=$extra[$k]}}
 Write-Utf8 (Get-StatePath) (($o|ConvertTo-Json -Depth 8)+"`r`n")
}
function Read-State([int]$min){
 $p=Get-StatePath;if(-not(Test-Path $p)){throw "$script:Tag state missing"}
 $s=Get-Content $p -Raw|ConvertFrom-Json;if([int]$s.phase-lt$min){throw "$script:Tag phase $($s.phase) < $min"};$s
}
function Get-Presenter{Join-Path (Get-RepositoryRoot) 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'}
function Get-Envelope{Join-Path (Get-RepositoryRoot) 'src\SharpEmu.CLI\DemonsSoulsGpuQueueEnvelopeV74011224.cs'}
function Assert-V1180([string]$p,[string]$q){
 $t=[IO.File]::ReadAllText($p)
 foreach($m in @(
  'SHARPEMU_V74_0_117_16_DESCRIPTOR_SET_BLOCK_CACHE',
  'SHARPEMU_V74_0_118_0_GPU_RESIDENT_SHADER_ID',
  'ResidentShaderProgramV1180','TryGetResidentShaderProgramV1180',
  'ResidentComputeExecutionKeyV1180','ResidentGraphicsExecutionKeyV1180',
  '[V74.0.118.0][RESIDENT_SHADER]'
 )){if(-not$t.Contains($m)){throw "$script:Tag marker missing: $m"}}
 if($t.Contains('SHARPEMU_V74_0_117_15_TEXTURE_BACKING_VIEW_ALIAS')){throw "$script:Tag V117.15 still present"}
 $e=[IO.File]::ReadAllText($q)
 foreach($m in @('SHARPEMU_V74_0_118_0_GPU_RESIDENT_SHADER_ENVELOPE','SHARPEMU_GPU_RESIDENT_SHADER_V1180')){
  if(-not$e.Contains($m)){throw "$script:Tag envelope marker missing: $m"}
 }
}
