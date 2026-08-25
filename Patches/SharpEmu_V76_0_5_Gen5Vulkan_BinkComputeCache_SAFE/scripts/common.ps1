$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$PackageRoot = Split-Path -Parent $PSScriptRoot
$PackageTag = 'V76.0.5-GEN5-VULKAN-BINK-COMPUTE-CACHE'

function Get-RepoRoot {
    param([string]$RequestedRoot)
    if ([string]::IsNullOrWhiteSpace($RequestedRoot)) {
        $RequestedRoot = 'C:\Users\Edpo\Documents\GitHub\sharpemu'
    }
    $resolved = [System.IO.Path]::GetFullPath($RequestedRoot)
    $probe = Join-Path $resolved 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
    if (-not (Test-Path -LiteralPath $probe -PathType Leaf)) {
        throw "Repo root invalido: $resolved (faltando $probe)"
    }
    return $resolved
}

function Get-PatchesRoot {
    param([string]$RequestedRoot)
    if ([string]::IsNullOrWhiteSpace($RequestedRoot)) {
        $RequestedRoot = 'C:\Users\Edpo\Documents\GitHub\sharpemu\Patches'
    }
    if (-not (Test-Path -LiteralPath $RequestedRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $RequestedRoot -Force | Out-Null
    }
    return [System.IO.Path]::GetFullPath($RequestedRoot)
}

function Get-Sha256 {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$ExistingTargets = @(
    'src\SharpEmu.Libs\Gpu\Vulkan\VulkanGuestGpuBackend.cs',
    'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs',
    'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.Alu.cs',
    'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs'
)

$NewTargets = @(
    'src\SharpEmu.Libs\Gpu\Vulkan\VulkanShaderBinaryCacheV7605.cs',
    'src\SharpEmu.Libs\VideoOut\VulkanPresentCadenceV7605.cs',
    'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.ValidationV7605.cs'
)

$BaselineHashes = @{
    'src\SharpEmu.Libs\Gpu\Vulkan\VulkanGuestGpuBackend.cs' = '50a5d68e62281baf59ef5d43ce50fc973be5da5e69385e17613d936ab1b9bda2'
    'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs' = '75e29c1ecfec9ce5969caa091a25926b133dfb8651eb7d815a3d237dd41a1816'
    'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.Alu.cs' = 'e55271ee14316c6339b199a1b9aff268a07098618a7370c57c4592592aff0a72'
    'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs' = '13edb9474c2b39c599b94c8195f65d0581bd3eef48033ab741030d09bd4dfab6'
}

$PayloadHashes = @{
    'src\SharpEmu.Libs\Gpu\Vulkan\VulkanGuestGpuBackend.cs' = '7dfa9c69563c068b4acaf9e48a6e714f16554b70ca141a55583e075851835fef'
    'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs' = 'a3bcf87a8819d40201383ebba2796cb56fa38fe696d9d1715c290602e3e7f81b'
    'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.Alu.cs' = 'bf00f04c16f0960692d3b654c125b1c1cc7b6d32655ed59f70382f7c82a4e511'
    'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.cs' = '4dcf32a6f174d49e42e82d6a059909c6dcb43aa299e6514752af649173b2a8a0'
    'src\SharpEmu.Libs\Gpu\Vulkan\VulkanShaderBinaryCacheV7605.cs' = 'c0befe335e1b0400ae466c6e70f6a2820603a3807c6992f0f84c9f0151e53c6f'
    'src\SharpEmu.Libs\VideoOut\VulkanPresentCadenceV7605.cs' = '1d569a968c456e04bd7eff3cc63f1ad7ef5029dc0af9fd725d75d3f85e7489a1'
    'src\SharpEmu.ShaderCompiler.Vulkan\Gen5SpirvTranslator.ValidationV7605.cs' = 'b733069d26919a08f99833af33cb64938a19e1319936e9a6ae7d0ddaeafe3b09'
}

function Get-SourceState {
    param([string]$RepoRoot)
    $details = New-Object System.Collections.Generic.List[string]
    $unknown = New-Object System.Collections.Generic.List[string]
    $payloadCount = 0
    $baselineCount = 0

    foreach ($rel in $ExistingTargets) {
        $path = Join-Path $RepoRoot $rel
        $hash = Get-Sha256 $path
        if ($hash -eq $PayloadHashes[$rel]) {
            $payloadCount++
            $details.Add("PAYLOAD $rel $hash")
        }
        elseif ($hash -eq $BaselineHashes[$rel]) {
            $baselineCount++
            $details.Add("BASELINE $rel $hash")
        }
        else {
            $unknown.Add("UNKNOWN $rel $hash")
        }
    }

    foreach ($rel in $NewTargets) {
        $path = Join-Path $RepoRoot $rel
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            $baselineCount++
            $details.Add("ABSENT $rel")
            continue
        }
        $hash = Get-Sha256 $path
        if ($hash -eq $PayloadHashes[$rel]) {
            $payloadCount++
            $details.Add("PAYLOAD $rel $hash")
        }
        else {
            $unknown.Add("UNKNOWN $rel $hash")
        }
    }

    if ($unknown.Count -gt 0) {
        return [pscustomobject]@{ State='Divergent'; Details=$details; Unknown=$unknown }
    }
    if ($payloadCount -eq ($ExistingTargets.Count + $NewTargets.Count)) {
        return [pscustomobject]@{ State='AlreadyApplied'; Details=$details; Unknown=$unknown }
    }
    if ($payloadCount -eq 0) {
        return [pscustomobject]@{ State='Ready'; Details=$details; Unknown=$unknown }
    }
    return [pscustomobject]@{ State='PartialReady'; Details=$details; Unknown=$unknown }
}

function Assert-PayloadInstalled {
    param([string]$RepoRoot)
    foreach ($rel in $PayloadHashes.Keys) {
        $actual = Get-Sha256 (Join-Path $RepoRoot $rel)
        if ($actual -ne $PayloadHashes[$rel]) {
            throw "Payload hash mismatch depois do apply: $rel expected=$($PayloadHashes[$rel]) actual=$actual"
        }
    }
}
