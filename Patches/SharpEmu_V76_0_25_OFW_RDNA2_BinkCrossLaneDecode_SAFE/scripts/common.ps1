$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$PackageRoot = Split-Path -Parent $PSScriptRoot
$PackageTag = 'V76.0.25-OFW-RDNA2-BINK-CROSSLANE-DECODE'
$HelperRel = 'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.DsPermuteV7625.cs'
$HelperPayload = 'payload\src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.DsPermuteV7625.cs'
$HelperSha256 = 'b2aa9735c3c9cfeb812f02f038c4654e15f8092121e9ad52bacd23357cbb64ca'

$PatchSpecs = @(
    @{ Name='translator_01'; Rel='src\SharpEmu.ShaderCompiler\Gen5ShaderTranslator.cs'; Optional=$false },
    @{ Name='translator_02'; Rel='src\SharpEmu.ShaderCompiler\Gen5ShaderTranslator.cs'; Optional=$false },
    @{ Name='translator_03'; Rel='src\SharpEmu.ShaderCompiler\Gen5ShaderTranslator.cs'; Optional=$false },
    @{ Name='spirv_01'; Rel='src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs'; Optional=$false },
    @{ Name='spirv_02'; Rel='src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs'; Optional=$false },
    @{ Name='dpp_01'; Rel='src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.IsaExpandV7617.cs'; Optional=$false },
    @{ Name='policy_01'; Rel='src\SharpEmu.Libs\Media\BinkDecodePolicyV7623.cs'; Optional=$false },
    @{ Name='presenter_v24_revert'; Rel='src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'; Optional=$true },
    @{ Name='cache_01'; Rel='src\SharpEmu.Libs\Gpu\Vulkan\VulkanShaderBinaryCacheV7605.cs'; Optional=$false }
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
    if($Spec.Optional){return 'NotNeeded'}
    throw "Patch $($Spec.Name) sem anchor old=$oldCount new=$newCount target=$($Spec.Rel)"
}
function Apply-Patch([string]$RepoRoot,[hashtable]$Spec) {
    $state=Get-PatchState $RepoRoot $Spec
    if($state -eq 'Applied' -or $state -eq 'NotNeeded'){return}
    $path=Join-Path $RepoRoot $Spec.Rel
    $raw=Read-Text $path; $nl=Get-NewLine $raw; $source=Normalize-Lf $raw
    $old=Normalize-Lf (Read-Text (Join-Path $PackageRoot "patchdata\$($Spec.Name).old.txt"))
    $new=Normalize-Lf (Read-Text (Join-Path $PackageRoot "patchdata\$($Spec.Name).new.txt"))
    $oldCount=Get-OccurrenceCount $source $old
    if($oldCount -ne 1){throw "Apply $($Spec.Name) recusado old occurrences=$oldCount"}
    $source=$source.Replace($old,$new)
    Write-Text $path (Restore-NewLine $source $nl)
    Write-Host "  * $($Spec.Name)"
}

function Assert-V7625Baseline([string]$RepoRoot) {
    $required=@(
      'src\SharpEmu.ShaderCompiler\Gen5ShaderTranslator.cs',
      'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs',
      'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.Alu.cs',
      'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.IsaExpandV7617.cs',
      'src\SharpEmu.Libs\Media\BinkDecodePolicyV7623.cs',
      'src\SharpEmu.Libs\Gpu\Vulkan\VulkanShaderBinaryCacheV7605.cs',
      'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs',
      'src\SharpEmu.Libs\Media\BinkGuestOwnedRuntimeV7600.cs',
      'src\SharpEmu.Libs\Kernel\KernelMemoryCompatExports.cs',
      'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.BinkGuestHandoffV7618.cs'
    )
    foreach($rel in $required){
      if(-not(Test-Path -LiteralPath (Join-Path $RepoRoot $rel) -PathType Leaf)){throw "Prerequisite ausente: $rel"}
    }
    $runtimeText=Read-Text (Join-Path $RepoRoot 'src\SharpEmu.Libs\Media\BinkGuestOwnedRuntimeV7600.cs')
    $kernelText=Read-Text (Join-Path $RepoRoot 'src\SharpEmu.Libs\Kernel\KernelMemoryCompatExports.cs')
    $handoffText=Read-Text (Join-Path $RepoRoot 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.BinkGuestHandoffV7618.cs')
    foreach($contract in @(
      '[BINK-GUEST][V76.0.18] hard_guest_only=True host_decoder=False',
      'CompleteGuestBinkHandoffV7618')){
      if($runtimeText.IndexOf($contract,[System.StringComparison]::Ordinal) -lt 0){throw "V76.0.18 runtime contract ausente: $contract"}
    }
    if($kernelText.IndexOf('[BINK-GUEST][V76.0.18][KERNEL-OPEN]',[System.StringComparison]::Ordinal) -lt 0){throw 'V76.0.18 KERNEL-OPEN contract ausente'}
    if($handoffText.IndexOf('no_black=True no_host_wait=True',[System.StringComparison]::Ordinal) -lt 0){throw 'V76.0.18 EBOOT handoff contract ausente'}

    # Require the existing guest YUV producer path; V25 fixes the ISA feeding it.
    $presenterText=Read-Text (Join-Path $RepoRoot 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs')
    $yuvHelperPath=Join-Path $RepoRoot 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.BinkGuestYuvV7612.cs'
    if(-not(Test-Path -LiteralPath $yuvHelperPath -PathType Leaf)){throw 'Bink guest YUV helper ausente'}
    $yuvHelperText=Read-Text $yuvHelperPath
    foreach($contract in @('IsCurrentGuestBinkYuvProducerV7612','YUV-BIND')){
      if($presenterText.IndexOf($contract,[System.StringComparison]::Ordinal) -lt 0){throw "Bink guest YUV presenter contract ausente: $contract"}
    }
    foreach($contract in @('gpu-authoritative-producer','YUV-PRODUCER','YUV-STORAGE-CPU-UPLOAD')){
      if($yuvHelperText.IndexOf($contract,[System.StringComparison]::Ordinal) -lt 0){throw "Bink guest YUV helper contract ausente: $contract"}
    }
}

function Assert-V7625Installed([string]$RepoRoot) {
    $helper=Join-Path $RepoRoot $HelperRel
    if((Get-Sha256 $helper) -ne $HelperSha256){throw "V76.0.25 helper mismatch: $HelperRel"}
    foreach($spec in $PatchSpecs){
        $state=Get-PatchState $RepoRoot $spec
        if($state -eq 'Ready'){throw "V76.0.25 patch nao aplicado: $($spec.Name)"}
    }
    $translator=Read-Text (Join-Path $RepoRoot 'src\SharpEmu.ShaderCompiler\Gen5ShaderTranslator.cs')
    $spirv=Read-Text (Join-Path $RepoRoot 'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs')
    $helperText=Read-Text $helper
    $policy=Read-Text (Join-Path $RepoRoot 'src\SharpEmu.Libs\Media\BinkDecodePolicyV7623.cs')
    $cache=Read-Text (Join-Path $RepoRoot 'src\SharpEmu.Libs\Gpu\Vulkan\VulkanShaderBinaryCacheV7605.cs')
    foreach($contract in @('0xB2 => "DsPermuteB32"','0xB3 => "DsBpermuteB32"','"DsPermuteB32" or "DsBpermuteB32"')){if($translator.IndexOf($contract,[System.StringComparison]::Ordinal)-lt 0){throw "Translator contract ausente: $contract"}}
    foreach($contract in @('TryEmitDsPermuteB32V7625','instruction.Opcode != "DsPermuteB32"','"DsBpermuteB32"')){if($spirv.IndexOf($contract,[System.StringComparison]::Ordinal)-lt 0){throw "SPIR-V contract ausente: $contract"}}
    foreach($contract in @('GroupNonUniformShuffle','UInt(31)','Load(_boolType, _exec)','[V76.0.25][RDNA2-DS-PERMUTE]')){if($helperText.IndexOf($contract,[System.StringComparison]::Ordinal)-lt 0){throw "DS permute helper contract ausente: $contract"}}
    if($policy.IndexOf('internal static bool AllowHostDecoder => false;',[System.StringComparison]::Ordinal)-lt 0){throw 'V76.2.3 hybrid host policy ainda ativa'}
    if($cache.IndexOf('V76.0.25-rdna2-crosslane-r1',[System.StringComparison]::Ordinal)-lt 0){throw 'SPIR-V cache generation V76.0.25 ausente'}
    $presenter=Read-Text (Join-Path $RepoRoot 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs')
    if($presenter.IndexOf('GetGuestBinkNormalizedSampleViewFormatV7624(texture, vkFormat)',[System.StringComparison]::Ordinal) -ge 0){throw 'V76.0.24 UNORM Bink sample-view hook ainda ativo'}
}
