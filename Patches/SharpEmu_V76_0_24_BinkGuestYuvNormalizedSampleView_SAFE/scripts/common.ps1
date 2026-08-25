$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$PackageRoot = Split-Path -Parent $PSScriptRoot
$PackageTag = 'V76.0.24-BINK-GUEST-YUV-NORMALIZED-SAMPLE-VIEW'

$PresenterRel = 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$YuvRel = 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.BinkGuestYuvV7612.cs'
$RuntimeRel = 'src\SharpEmu.Libs\Media\BinkGuestOwnedRuntimeV7600.cs'
$HandoffRel = 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.BinkGuestHandoffV7618.cs'
$HelperRel = 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.BinkGuestSampleViewV7624.cs'
$HelperPayload = 'payload\src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.BinkGuestSampleViewV7624.cs'

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
function Assert-V7624Baseline([string]$RepoRoot) {
    foreach($rel in @($PresenterRel,$YuvRel,$RuntimeRel,$HandoffRel)){
        $path=Join-Path $RepoRoot $rel
        if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Prerequisite ausente: $rel"}
    }
    $runtime=Read-Text (Join-Path $RepoRoot $RuntimeRel)
    foreach($c in @(
        '[BINK-GUEST][V76.0.18]',
        'hard_guest_only=True',
        'internal static bool Enabled => true',
        'SHARPEMU_BINK_ALLOW_HOST_DECODER'
    )){
        if($runtime.IndexOf($c,[System.StringComparison]::Ordinal) -lt 0){
            throw "Hard guest-only prerequisite ausente: $c"
        }
    }
    $handoff=Read-Text (Join-Path $RepoRoot $HandoffRel)
    foreach($c in @('CompleteGuestBinkHandoffV7618','no_black=True no_host_wait=True')){
        if($handoff.IndexOf($c,[System.StringComparison]::Ordinal) -lt 0){
            throw "V76.0.18 handoff prerequisite ausente: $c"
        }
    }
    $yuv=Read-Text (Join-Path $RepoRoot $YuvRel)
    foreach($c in @(
        'IsCurrentGuestBinkYuvProducerV7612',
        'MarkGuestBinkYuvProducerV7612',
        'ShouldSuppressGuestBinkStorageCpuUploadV7612',
        '[BINK-GUEST][V76.0.12][YUV-PRODUCER]',
        '[BINK-GUEST][V76.0.12][YUV-STORAGE-CPU-UPLOAD]'
    )){
        if($yuv.IndexOf($c,[System.StringComparison]::Ordinal) -lt 0){
            throw "V76 YUV producer prerequisite ausente: $c"
        }
    }
    $presenter=Read-Text (Join-Path $RepoRoot $PresenterRel)
    foreach($c in @(
        'CreateMutableFormatBit |',
        'ImageCreateFlags.CreateExtendedUsageBit',
        'private static bool IsFinalGuestBinkYuvPlaneV7602(',
        'TryResolveExactGuestBinkYuvProducerV7602(',
        'TryGetOrCreateGuestImageView(',
        'Format.R8Uint or',
        'Format.R8G8Uint or'
    )){
        if($presenter.IndexOf($c,[System.StringComparison]::Ordinal) -lt 0){
            throw "Presenter mutable-view prerequisite ausente: $c"
        }
    }
}
function Assert-V7624Installed([string]$RepoRoot) {
    Assert-V7624Baseline $RepoRoot
    foreach($spec in $PatchSpecs){
        $state=Get-PatchState $RepoRoot $spec
        if($state -ne 'Applied'){throw "Patch nao aplicado: $($spec.Name) state=$state"}
    }
    $helperPath=Join-Path $RepoRoot $HelperRel
    if(-not(Test-Path -LiteralPath $helperPath -PathType Leaf)){throw "Helper V76.0.24 ausente"}
    $helper=Read-Text $helperPath
    foreach($c in @(
        'GetGuestBinkNormalizedSampleViewFormatV7624',
        'Format.R8Uint => Format.R8Unorm',
        'Format.R8G8Uint => Format.R8G8Unorm',
        'SHARPEMU_BINK_YUV_NORMALIZED_SAMPLE_VIEW',
        '[BINK-GUEST][V76.0.24][YUV-SAMPLE-VIEW]',
        'cpu_copy=False host_decoder=False'
    )){
        if($helper.IndexOf($c,[System.StringComparison]::Ordinal) -lt 0){
            throw "V76.0.24 helper contract ausente: $c"
        }
    }
}
