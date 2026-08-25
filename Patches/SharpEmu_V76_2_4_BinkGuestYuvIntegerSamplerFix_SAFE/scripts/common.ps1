$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$PackageRoot = Split-Path -Parent $PSScriptRoot
$PackageTag = 'V76.2.4-BINK-GUEST-YUV-INTEGER-SAMPLER-FIX'
$PresenterRel = 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$BinkRel = 'src\SharpEmu.Libs\Media\BinkGuestOwnedRuntimeV7600.cs'
$KernelRel = 'src\SharpEmu.Libs\Kernel\KernelMemoryCompatExports.cs'
$HostRel = 'src\SharpEmu.Libs\Media\HostMovieBridge.cs'
$YuvRel = 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.BinkGuestYuvV7612.cs'
$HandoffRel = 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.BinkGuestHandoffV7618.cs'
$SamplerRel = 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.BinkGuestSamplerV7624.cs'
$SamplerPayload = 'payload\src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.BinkGuestSamplerV7624.cs'

$PatchSpecs = @(
    @{ Name='presenter_01'; Rel=$PresenterRel },
    @{ Name='presenter_02'; Rel=$PresenterRel },
    @{ Name='presenter_03'; Rel=$PresenterRel }
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
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return ''}
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
function Assert-Contains([string]$Text,[string[]]$Contracts,[string]$Label) {
    foreach($contract in $Contracts){
        if($Text.IndexOf($contract,[System.StringComparison]::Ordinal) -lt 0){throw "$Label contract ausente: $contract"}
    }
}
function Assert-V7618GuestOnlyBaseline([string]$RepoRoot) {
    foreach($rel in @($PresenterRel,$BinkRel,$KernelRel,$HostRel,$YuvRel,$HandoffRel)){
        if(-not(Test-Path -LiteralPath (Join-Path $RepoRoot $rel) -PathType Leaf)){throw "Prerequisite ausente: $rel"}
    }
    $bink=Read-Text (Join-Path $RepoRoot $BinkRel)
    Assert-Contains $bink @(
        'V76.0.18_BINK2_HARD_GUEST_ONLY_EBOOT_HANDOFF',
        'internal static bool Enabled => true;',
        'Set("SHARPEMU_BINK_ALLOW_HOST_DECODER", "0");'
    ) 'Bink guest-only baseline'
    $kernel=Read-Text (Join-Path $RepoRoot $KernelRel)
    Assert-Contains $kernel @(
        '[BINK-GUEST][V76.0.18][KERNEL-OPEN]',
        'route=guest-file-fd host_takeover=False completion_shim=False'
    ) 'Kernel guest-fd baseline'
    $hostText=Read-Text (Join-Path $RepoRoot $HostRel)
    Assert-Contains $hostText @(
        '[BINK-GUEST][V76.0.18][HOST-ATTACH-BLOCK]',
        '[BINK-GUEST][V76.0.18][HOST-TAKEOVER-BLOCK]'
    ) 'Host takeover block baseline'
    $yuv=Read-Text (Join-Path $RepoRoot $YuvRel)
    Assert-Contains $yuv @(
        'IsCurrentGuestBinkYuvProducerV7612(',
        'MarkGuestBinkYuvProducerV7612(',
        '[BINK-GUEST][V76.0.12][YUV-PRODUCER]',
        '[BINK-GUEST][V76.0.12][YUV-STORAGE-CPU-UPLOAD]'
    ) 'Bink YUV baseline'
    $handoff=Read-Text (Join-Path $RepoRoot $HandoffRel)
    Assert-Contains $handoff @(
        '[BINK-GUEST][V76.0.18][EBOOT-HANDOFF]',
        'no_black=True no_host_wait=True'
    ) 'Eboot handoff baseline'
    $presenter=Read-Text (Join-Path $RepoRoot $PresenterRel)
    Assert-Contains $presenter @(
        'IsFinalGuestBinkYuvPlaneV7602(',
        'TryResolveExactGuestBinkYuvProducerV7602(',
        '[BINK-GUEST][V76.0.2][YUV-BIND]',
        'private Sampler CreateSampler(GuestSampler sampler)'
    ) 'Presenter YUV baseline'
}
function Get-SamplerHelperState([string]$RepoRoot) {
    $target=Join-Path $RepoRoot $SamplerRel
    $payload=Join-Path $PackageRoot $SamplerPayload
    $expected=Get-Sha256 $payload
    $actual=Get-Sha256 $target
    if([string]::IsNullOrWhiteSpace($actual)){return 'ReadyCopy'}
    if($actual -eq $expected){return 'Applied'}
    throw "V76.2.4 sampler helper divergente expected=$expected actual=$actual"
}
function Assert-V7624Installed([string]$RepoRoot) {
    Assert-V7618GuestOnlyBaseline $RepoRoot
    if((Get-SamplerHelperState $RepoRoot) -ne 'Applied'){throw 'V76.2.4 sampler helper ausente'}
    foreach($spec in $PatchSpecs){
        if((Get-PatchState $RepoRoot $spec) -ne 'Applied'){throw "V76.2.4 patch incompleto: $($spec.Name)"}
    }
    $helper=Read-Text (Join-Path $RepoRoot $SamplerRel)
    Assert-Contains $helper @(
        'NormalizeGuestBinkIntegerSamplerV7624(',
        'SHARPEMU_BINK_INTEGER_NEAREST',
        '[BINK-GUEST][V76.2.4][YUV-SAMPLER]',
        'reason=integer-yuv-sampling'
    ) 'V76.2.4 sampler helper'
}
