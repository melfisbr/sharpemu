$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$PackageRoot = Split-Path -Parent $PSScriptRoot
$PackageTag = 'V76.0.16-FINAL-VULKAN-PERFORMANCE-CONSOLIDATED'

$PresenterRel = 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$DetileRel = 'src\SharpEmu.Libs\VideoOut\VulkanDetilePass.cs'
$BinkRel = 'src\SharpEmu.Libs\Media\BinkGuestOwnedRuntimeV7600.cs'
$AvHelperRel = 'src\SharpEmu.Libs\Media\BinkGuestAvClockV7613.cs'
$AvHelperExpectedHash = '07dfdacd9c6f5855275318a161db4968f56b06e4336e62d6c594fdcc4673585f'
$YuvHelperRel = 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.BinkGuestYuvV7612.cs'
$YuvHelperExpectedHash = 'cb264d09b0bb665e1bad0cf54d0d74efab14b92205871e0c671c447c81d9b0b0'

$HelperSpecs = @(
    @{ Rel='src\SharpEmu.Libs\VideoOut\VulkanBufferCapacityPolicyV7614.cs'; Payload='payload\src\SharpEmu.Libs\VideoOut\VulkanBufferCapacityPolicyV7614.cs' },
    @{ Rel='src\SharpEmu.Libs\VideoOut\VulkanCrossQueueHazardTrackerV7615.cs'; Payload='payload\src\SharpEmu.Libs\VideoOut\VulkanCrossQueueHazardTrackerV7615.cs' },
    @{ Rel='src\SharpEmu.Libs\VideoOut\VulkanPresentPolicyV7616.cs'; Payload='payload\src\SharpEmu.Libs\VideoOut\VulkanPresentPolicyV7616.cs' },
    @{ Rel='src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.FinalPerfV7615_16.cs'; Payload='payload\src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.FinalPerfV7615_16.cs' }
)

function Get-RepoRoot([string]$Preferred) {
    if(Test-Path -LiteralPath (Join-Path $Preferred 'src\SharpEmu.CLI\SharpEmu.CLI.csproj')){
        return (Resolve-Path -LiteralPath $Preferred).Path
    }
    throw "RepositoryRoot invalido: $Preferred"
}
function Get-PatchesRoot([string]$Preferred) {
    if(-not(Test-Path -LiteralPath $Preferred)){New-Item -ItemType Directory -Path $Preferred -Force | Out-Null}
    return (Resolve-Path -LiteralPath $Preferred).Path
}
function Get-Sha256([string]$Path) {
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){ return '' }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Read-Text([string]$Path) { return [System.IO.File]::ReadAllText($Path) }
function Write-Text([string]$Path,[string]$Text) {
    $utf8=New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path,$Text,$utf8)
}
function Normalize-Lf([string]$Text) { return $Text.Replace("`r`n","`n").Replace("`r","`n") }
function Get-NewLine([string]$Text) { if($Text.Contains("`r`n")){return "`r`n"}; return "`n" }
function Restore-NewLine([string]$Text,[string]$NewLine) { if($NewLine -eq "`r`n"){return $Text.Replace("`n","`r`n")}; return $Text }
function Get-OccurrenceCount([string]$Text,[string]$Needle) {
    if([string]::IsNullOrEmpty($Needle)){return 0}
    $count=0; $start=0
    while($start -le $Text.Length-$Needle.Length){
        $idx=$Text.IndexOf($Needle,$start,[System.StringComparison]::Ordinal)
        if($idx -lt 0){break}
        $count++; $start=$idx+$Needle.Length
    }
    return $count
}
function Get-HelperState([string]$RepoRoot,[hashtable]$Spec) {
    $target=Join-Path $RepoRoot $Spec.Rel
    $payload=Join-Path $PackageRoot $Spec.Payload
    $expected=Get-Sha256 $payload
    $actual=Get-Sha256 $target
    if([string]::IsNullOrWhiteSpace($actual)){return 'ReadyCopy'}
    if($actual -eq $expected){return 'Applied'}
    throw "Helper divergente: $($Spec.Rel) expected=$expected actual=$actual"
}
function Get-PatchPairState([string]$RepoRoot,[string]$TargetRel,[string]$Prefix,[int]$Index) {
    $path=Join-Path $RepoRoot $TargetRel
    $source=Normalize-Lf (Read-Text $path)
    $base=('{0}_{1:d2}' -f $Prefix,$Index)
    $old=Normalize-Lf (Read-Text (Join-Path $PackageRoot "patchdata\$base.old.txt"))
    $new=Normalize-Lf (Read-Text (Join-Path $PackageRoot "patchdata\$base.new.txt"))
    $newCount=Get-OccurrenceCount $source $new
    if($newCount -eq 1){return 'Applied'}
    if($newCount -gt 1){throw "Patch $base new-state ambiguo count=$newCount"}
    $oldCount=Get-OccurrenceCount $source $old
    if($oldCount -eq 1){return 'Ready'}
    throw "Patch $base sem anchor old=$oldCount new=$newCount target=$TargetRel"
}
function Apply-PatchPair([string]$RepoRoot,[string]$TargetRel,[string]$Prefix,[int]$Index) {
    $path=Join-Path $RepoRoot $TargetRel
    $raw=Read-Text $path
    $nl=Get-NewLine $raw
    $source=Normalize-Lf $raw
    $base=('{0}_{1:d2}' -f $Prefix,$Index)
    $old=Normalize-Lf (Read-Text (Join-Path $PackageRoot "patchdata\$base.old.txt"))
    $new=Normalize-Lf (Read-Text (Join-Path $PackageRoot "patchdata\$base.new.txt"))
    if((Get-OccurrenceCount $source $new) -eq 1){return}
    $oldCount=Get-OccurrenceCount $source $old
    if($oldCount -ne 1){throw "Apply $base recusado old occurrences=$oldCount"}
    $source=$source.Replace($old,$new)
    Write-Text $path (Restore-NewLine $source $nl)
    Write-Host "  * $base"
}
function Assert-V7613Baseline([string]$RepoRoot) {
    foreach($rel in @($PresenterRel,$DetileRel,$BinkRel,$AvHelperRel,$YuvHelperRel)){
        if(-not(Test-Path -LiteralPath (Join-Path $RepoRoot $rel) -PathType Leaf)){throw "Prerequisite ausente: $rel"}
    }
    $av=Get-Sha256 (Join-Path $RepoRoot $AvHelperRel)
    if($av -ne $AvHelperExpectedHash){throw "V76.0.13.2 A/V helper mismatch expected=$AvHelperExpectedHash actual=$av"}
    $yuv=Get-Sha256 (Join-Path $RepoRoot $YuvHelperRel)
    if($yuv -ne $YuvHelperExpectedHash){throw "V76.0.12.3 YUV helper mismatch expected=$YuvHelperExpectedHash actual=$yuv"}
    $bink=Read-Text (Join-Path $RepoRoot $BinkRel)
    foreach($contract in @('BinkGuestAvClockV7613.BeginSession(','BinkGuestAvClockV7613.EndSession(','internal static long ActiveSessionEpoch =>')){
        if($bink.IndexOf($contract,[System.StringComparison]::Ordinal) -lt 0){throw "V76.0.13.2 Bink contract ausente: $contract"}
    }
    $presenter=Read-Text (Join-Path $RepoRoot $PresenterRel)
    foreach($contract in @('BinkGuestAvClockV7613.ShouldHoldFirstVisual(','BinkGuestAvClockV7613.NotifyPresentedFrame(','MarkGuestBinkYuvProducerV7612(texture);')){
        if($presenter.IndexOf($contract,[System.StringComparison]::Ordinal) -lt 0){throw "V76.0.13.2 presenter contract ausente: $contract"}
    }
}
function Get-FinalState([string]$RepoRoot,[switch]$Verbose) {
    Assert-V7613Baseline $RepoRoot
    foreach($spec in $HelperSpecs){
        $state=Get-HelperState $RepoRoot $spec
        if($Verbose){Write-Host "  Helper $($spec.Rel)=$state"}
    }
    for($i=1;$i -le 15;$i++){
        $state=Get-PatchPairState $RepoRoot $PresenterRel 'presenter' $i
        if($Verbose){Write-Host ("  PresenterPatch{0:d2}={1}" -f $i,$state)}
    }
    for($i=1;$i -le 14;$i++){
        $state=Get-PatchPairState $RepoRoot $DetileRel 'detile' $i
        if($Verbose){Write-Host ("  DetilePatch{0:d2}={1}" -f $i,$state)}
    }
}
function Assert-FinalInstalled([string]$RepoRoot) {
    Assert-V7613Baseline $RepoRoot
    foreach($spec in $HelperSpecs){if((Get-HelperState $RepoRoot $spec) -ne 'Applied'){throw "Helper final incompleto: $($spec.Rel)"}}
    for($i=1;$i -le 15;$i++){if((Get-PatchPairState $RepoRoot $PresenterRel 'presenter' $i) -ne 'Applied'){throw "Presenter patch final incompleto $i"}}
    for($i=1;$i -le 14;$i++){if((Get-PatchPairState $RepoRoot $DetileRel 'detile' $i) -ne 'Applied'){throw "Detile patch final incompleto $i"}}
    $presenter=Read-Text (Join-Path $RepoRoot $PresenterRel)
    foreach($marker in @(
        'VulkanPresentPolicyV7616.LatestReadyEnabled',
        'ResolveCrossQueueWaitV7615(',
        'CommitCrossQueueAccessV7615(',
        'VulkanBufferCapacityPolicyV7614.Round(',
        'resources.QueueHazardImagesV7615 = targets;')){
        if($presenter.IndexOf($marker,[System.StringComparison]::Ordinal) -lt 0){throw "Final presenter marker ausente: $marker"}
    }
    $detile=Read-Text (Join-Path $RepoRoot $DetileRel)
    foreach($marker in @('nint Mapped = 0','vkMapMemory(detile persistent v7614)','VulkanBufferCapacityPolicyV7614.Round(size)','allocation.Mapped')){
        if($detile.IndexOf($marker,[System.StringComparison]::Ordinal) -lt 0){throw "Final detile marker ausente: $marker"}
    }
}
