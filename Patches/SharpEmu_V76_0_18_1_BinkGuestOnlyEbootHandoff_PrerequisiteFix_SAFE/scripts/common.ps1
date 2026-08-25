$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$PackageRoot = Split-Path -Parent $PSScriptRoot
$PackageTag = 'V76.0.18.1-BINK-GUEST-ONLY-EBOOT-HANDOFF-PREREQFIX'

$BinkRel = 'src\SharpEmu.Libs\Media\BinkGuestOwnedRuntimeV7600.cs'
$KernelRel = 'src\SharpEmu.Libs\Kernel\KernelMemoryCompatExports.cs'
$HostRel = 'src\SharpEmu.Libs\Media\HostMovieBridge.cs'
$FfmpegRel = 'src\SharpEmu.Libs\Media\FfmpegVideoDecoder.cs'
$NihavRel = 'src\SharpEmu.Libs\Media\NihavBink2Decoder.cs'
$RadNativeRel = 'src\SharpEmu.Libs\Media\RadBinkNativeSdkDecoderV7500.cs'
$RadExternalRel = 'src\SharpEmu.Libs\Media\RadBinkExternalPlaybackV7243231.cs'
$PresenterRel = 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$HandoffRel = 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.BinkGuestHandoffV7618.cs'
$HandoffPayload = 'payload\src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.BinkGuestHandoffV7618.cs'

$BinkAvRel = 'src\SharpEmu.Libs\Media\BinkGuestAvClockV7613.cs'
$BinkAvKnownHashes = @(
    '07dfdacd9c6f5855275318a161db4968f56b06e4336e62d6c594fdcc4673585f',
    '4688da66dcaf14cf85d1646cd8a8ebf086b7f3563c405bdcdace7a7dade697ee'
)

$BaselineHelpers = @(
    @{ Rel='src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.BinkGuestYuvV7612.cs'; Hash='cb264d09b0bb665e1bad0cf54d0d74efab14b92205871e0c671c447c81d9b0b0' },
    @{ Rel='src\SharpEmu.Libs\VideoOut\VulkanBufferCapacityPolicyV7614.cs'; Hash='e55f698ac80ea854b7e1069ed373497f1cfd422f925c267a8709b4885c7d68c3' },
    @{ Rel='src\SharpEmu.Libs\VideoOut\VulkanCrossQueueHazardTrackerV7615.cs'; Hash='ae4f00c279c59ab2280bdb0e180bc8ede3ce4bc32482c76f9374d36c00868312' },
    @{ Rel='src\SharpEmu.Libs\VideoOut\VulkanPresentPolicyV7616.cs'; Hash='02721394693ef1eeef7e6ef0909919c36cca23b46ccb261f5c401ff9cc0c3c61' },
    @{ Rel='src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.FinalPerfV7615_16.cs'; Hash='01df9fd1999470267ed0e0a6fbacc92c6f09e6584d1bef1ec362535111bd0abc' }
)

$PatchSpecs = @(
    @{ Name='runtime_01'; Rel='src\SharpEmu.Libs\Media\BinkGuestOwnedRuntimeV7600.cs' },
    @{ Name='runtime_02'; Rel='src\SharpEmu.Libs\Media\BinkGuestOwnedRuntimeV7600.cs' },
    @{ Name='runtime_03'; Rel='src\SharpEmu.Libs\Media\BinkGuestOwnedRuntimeV7600.cs' },
    @{ Name='runtime_04'; Rel='src\SharpEmu.Libs\Media\BinkGuestOwnedRuntimeV7600.cs' },
    @{ Name='runtime_05'; Rel='src\SharpEmu.Libs\Media\BinkGuestOwnedRuntimeV7600.cs' },
    @{ Name='kernel_01'; Rel='src\SharpEmu.Libs\Kernel\KernelMemoryCompatExports.cs' },
    @{ Name='kernel_02'; Rel='src\SharpEmu.Libs\Kernel\KernelMemoryCompatExports.cs' },
    @{ Name='host_01'; Rel='src\SharpEmu.Libs\Media\HostMovieBridge.cs' },
    @{ Name='host_02'; Rel='src\SharpEmu.Libs\Media\HostMovieBridge.cs' },
    @{ Name='host_03'; Rel='src\SharpEmu.Libs\Media\HostMovieBridge.cs' },
    @{ Name='host_04'; Rel='src\SharpEmu.Libs\Media\HostMovieBridge.cs' },
    @{ Name='host_05'; Rel='src\SharpEmu.Libs\Media\HostMovieBridge.cs' },
    @{ Name='host_06'; Rel='src\SharpEmu.Libs\Media\HostMovieBridge.cs' },
    @{ Name='ffmpeg_01'; Rel='src\SharpEmu.Libs\Media\FfmpegVideoDecoder.cs' },
    @{ Name='nihav_01'; Rel='src\SharpEmu.Libs\Media\NihavBink2Decoder.cs' },
    @{ Name='radnative_01'; Rel='src\SharpEmu.Libs\Media\RadBinkNativeSdkDecoderV7500.cs' },
    @{ Name='radexternal_01'; Rel='src\SharpEmu.Libs\Media\RadBinkExternalPlaybackV7243231.cs' },
    @{ Name='presenter_01'; Rel='src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs' }
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
function Get-PatchState([string]$RepoRoot,[hashtable]$Spec) {
    $path=Join-Path $RepoRoot $Spec.Rel
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Target ausente: $($Spec.Rel)"}
    $source=Normalize-Lf (Read-Text $path)
    $old=Normalize-Lf (Read-Text (Join-Path $PackageRoot "patchdata\$($Spec.Name).old.txt"))
    $new=Normalize-Lf (Read-Text (Join-Path $PackageRoot "patchdata\$($Spec.Name).new.txt"))
    $newCount=Get-OccurrenceCount $source $new
    if($newCount -eq 1){return 'Applied'}
    if($newCount -gt 1){throw "Patch $($Spec.Name) new-state ambiguo count=$newCount"}
    $oldCount=Get-OccurrenceCount $source $old
    if($oldCount -eq 1){return 'Ready'}
    throw "Patch $($Spec.Name) sem anchor old=$oldCount new=$newCount target=$($Spec.Rel)"
}
function Apply-Patch([string]$RepoRoot,[hashtable]$Spec) {
    $path=Join-Path $RepoRoot $Spec.Rel
    $raw=Read-Text $path
    $nl=Get-NewLine $raw
    $source=Normalize-Lf $raw
    $old=Normalize-Lf (Read-Text (Join-Path $PackageRoot "patchdata\$($Spec.Name).old.txt"))
    $new=Normalize-Lf (Read-Text (Join-Path $PackageRoot "patchdata\$($Spec.Name).new.txt"))
    if((Get-OccurrenceCount $source $new) -eq 1){return}
    $oldCount=Get-OccurrenceCount $source $old
    if($oldCount -ne 1){throw "Apply $($Spec.Name) recusado old occurrences=$oldCount"}
    $source=$source.Replace($old,$new)
    Write-Text $path (Restore-NewLine $source $nl)
    Write-Host "  * $($Spec.Name)"
}
function Assert-BinkAvClockBaselineV7613([string]$RepoRoot) {
    $path=Join-Path $RepoRoot $BinkAvRel
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Prerequisite ausente: $BinkAvRel"}
    $actual=Get-Sha256 $path
    $text=Read-Text $path
    $contracts=@(
        'internal static class BinkGuestAvClockV7613',
        'internal static void BeginSession(long epoch, string? path)',
        'internal static void EndSession(long epoch, string? path)',
        'internal static bool ShouldHoldFirstVisual(long epoch)',
        'internal static void NotifyPresentedFrame(long epoch, long producerGeneration)',
        'GuestAudioClock.PlayedSeconds',
        '[BINK-GUEST][V76.0.13][AV-CLOCK]',
        '[BINK-GUEST][V76.0.13][HANDOFF]',
        '[BINK-GUEST][V76.0.13][AV-SYNC]'
    )
    foreach($contract in $contracts){
        if($text.IndexOf($contract,[System.StringComparison]::Ordinal) -lt 0){
            throw "V76.0.13 A/V helper contract ausente: $contract hash=$actual"
        }
    }
    if($BinkAvKnownHashes -contains $actual){return "AppliedKnownHash:$actual"}
    return "AppliedSemantic:$actual"
}

function Assert-V7616Baseline([string]$RepoRoot) {
    foreach($rel in @($BinkRel,$KernelRel,$HostRel,$FfmpegRel,$NihavRel,$RadNativeRel,$RadExternalRel,$PresenterRel)){
        if(-not(Test-Path -LiteralPath (Join-Path $RepoRoot $rel) -PathType Leaf)){throw "Prerequisite ausente: $rel"}
    }
    $null=Assert-BinkAvClockBaselineV7613 $RepoRoot
    foreach($spec in $BaselineHelpers){
        $actual=Get-Sha256 (Join-Path $RepoRoot $spec.Rel)
        if($actual -ne $spec.Hash){throw "V76 baseline helper mismatch: $($spec.Rel) expected=$($spec.Hash) actual=$actual"}
    }
    $bink=Read-Text (Join-Path $RepoRoot $BinkRel)
    foreach($contract in @('BinkGuestAvClockV7613.BeginSession(','BinkGuestAvClockV7613.EndSession(','internal static long ActiveSessionEpoch =>')){
        if($bink.IndexOf($contract,[System.StringComparison]::Ordinal) -lt 0){throw "Bink baseline contract ausente: $contract"}
    }
    $presenter=Read-Text (Join-Path $RepoRoot $PresenterRel)
    foreach($contract in @('VulkanPresentPolicyV7616.LatestReadyEnabled','ResolveCrossQueueWaitV7615(','MarkGuestBinkYuvProducerV7612(texture);')){
        if($presenter.IndexOf($contract,[System.StringComparison]::Ordinal) -lt 0){throw "Presenter baseline contract ausente: $contract"}
    }
}
function Get-HandoffHelperState([string]$RepoRoot) {
    $target=Join-Path $RepoRoot $HandoffRel
    $payload=Join-Path $PackageRoot $HandoffPayload
    $expected=Get-Sha256 $payload
    $actual=Get-Sha256 $target
    if([string]::IsNullOrWhiteSpace($actual)){return 'ReadyCopy'}
    if($actual -eq $expected){return 'Applied'}
    throw "V76.0.18 helper divergente expected=$expected actual=$actual"
}
function Assert-V7618Installed([string]$RepoRoot) {
    Assert-V7616Baseline $RepoRoot
    if((Get-HandoffHelperState $RepoRoot) -ne 'Applied'){throw 'V76.0.18 handoff helper ausente'}
    foreach($spec in $PatchSpecs){
        if((Get-PatchState $RepoRoot $spec) -ne 'Applied'){throw "V76.0.18 patch incompleto: $($spec.Name)"}
    }
    $bink=Read-Text (Join-Path $RepoRoot $BinkRel)
    foreach($marker in @('V76.0.18_BINK2_HARD_GUEST_ONLY_EBOOT_HANDOFF','internal static bool Enabled => true;','Set("SHARPEMU_BINK_ALLOW_HOST_DECODER", "0");','CompleteGuestBinkHandoffV7618(path, epoch);')){
        if($bink.IndexOf($marker,[System.StringComparison]::Ordinal) -lt 0){throw "V76.0.18 Bink marker ausente: $marker"}
    }
    $kernel=Read-Text (Join-Path $RepoRoot $KernelRel)
    foreach($marker in @('guestOnlyBinkV7618','route=guest-file-fd host_takeover=False completion_shim=False')){
        if($kernel.IndexOf($marker,[System.StringComparison]::Ordinal) -lt 0){throw "V76.0.18 Kernel marker ausente: $marker"}
    }
    $host=Read-Text (Join-Path $RepoRoot $HostRel)
    foreach($marker in @('[BINK-GUEST][V76.0.18][HOST-ATTACH-BLOCK]','[BINK-GUEST][V76.0.18][HOST-TAKEOVER-BLOCK]')){
        if($host.IndexOf($marker,[System.StringComparison]::Ordinal) -lt 0){throw "V76.0.18 Host marker ausente: $marker"}
    }
    $presenter=Read-Text (Join-Path $RepoRoot $PresenterRel)
    if($presenter.IndexOf('if (BinkGuestOwnedRuntimeV7600.IsGuestMovieActive)',[System.StringComparison]::Ordinal) -lt 0){throw 'V76.0.18 host-pump guard ausente'}
    $helper=Read-Text (Join-Path $RepoRoot $HandoffRel)
    foreach($marker in @('[BINK-GUEST][V76.0.18][EBOOT-HANDOFF]','no_black=True no_host_wait=True','guest_presentations_preserved=True')){
        if($helper.IndexOf($marker,[System.StringComparison]::Ordinal) -lt 0){throw "V76.0.18 handoff marker ausente: $marker"}
    }
}
