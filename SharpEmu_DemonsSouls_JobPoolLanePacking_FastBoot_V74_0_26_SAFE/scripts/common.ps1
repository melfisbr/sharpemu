Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-RepoRootV74026 {
    param([string]$RepositoryRoot = "")
    if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Get-Location).Path }
    $repoRoot = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $markerPath = [System.IO.Path]::Combine($repoRoot, "src", "SharpEmu.CLI", "SharpEmu.CLI.csproj")
    if (-not [System.IO.File]::Exists($markerPath)) { throw "[V74.0.26] Repository root invalid: $repoRoot" }
    return $repoRoot
}

function Get-AgcPathV74026 { param([string]$Root) return [System.IO.Path]::Combine($Root,"src","SharpEmu.Libs","Agc","AgcExports.cs") }
function Get-PresenterPathV74026 { param([string]$Root) return [System.IO.Path]::Combine($Root,"src","SharpEmu.Libs","VideoOut","VulkanVideoPresenter.cs") }
function Get-CpuPathV74026 { param([string]$Root) return [System.IO.Path]::Combine($Root,"src","SharpEmu.Core","Cpu","CpuDispatcher.cs") }
function Get-DirectPathV74026 { param([string]$Root) return [System.IO.Path]::Combine($Root,"src","SharpEmu.Core","Cpu","Native","DirectExecutionBackend.cs") }
function Get-KernelPathV74026 { param([string]$Root) return [System.IO.Path]::Combine($Root,"src","SharpEmu.Libs","Kernel","KernelExports.cs") }
function Get-HostMoviePathV74026 { param([string]$Root) return [System.IO.Path]::Combine($Root,"src","SharpEmu.Libs","Media","HostMovieBridge.cs") }

function Test-V21AbiAppliedV74026 {
    param([string]$Root)
    $cpuPath=Get-CpuPathV74026 -Root $Root
    $directPath=Get-DirectPathV74026 -Root $Root
    $kernelPath=Get-KernelPathV74026 -Root $Root
    foreach ($requiredPath in @($cpuPath,$directPath,$kernelPath)) { if (-not [System.IO.File]::Exists($requiredPath)) { return $false } }
    $cpuText=[System.IO.File]::ReadAllText($cpuPath)
    $directText=[System.IO.File]::ReadAllText($directPath)
    $kernelText=[System.IO.File]::ReadAllText($kernelPath)
    return $cpuText.Contains("SHARPEMU_V74_0_21_EBOOT_ENTRY_ABI") -and
        $cpuText.Contains("const ulong entryParamsSize = 0x118;") -and
        $cpuText.Contains("const int maxArguments = 33;") -and
        $directText.Contains("SHARPEMU_V74_0_21_LLE_INIT_ENV_GATE") -and
        $kernelText.Contains("SHARPEMU_V74_0_21_INIT_ENV_FALLBACK_DIAGNOSTIC")
}

function Test-PresenterRollupV74026 {
    param([string]$Root)
    $path=Get-PresenterPathV74026 -Root $Root
    if (-not [System.IO.File]::Exists($path)) { return $false }
    $text=[System.IO.File]::ReadAllText($path)
    return $text.Contains("SHARPEMU_V74_0_23_1_LARGE_ARRAY_SPARSE_BASELINE") -and
        $text.Contains("SHARPEMU_V74_0_24_FRESH_STALE_SOURCE") -and
        $text.Contains("TryRefreshStaleTextureSourceV74024")
}

function Test-V25AppliedV74026 {
    param([string]$Root)
    $path=Get-AgcPathV74026 -Root $Root
    if (-not [System.IO.File]::Exists($path)) { return $false }
    $text=[System.IO.File]::ReadAllText($path)
    return $text.Contains("SHARPEMU_V74_0_25_WRITE_DATA_PACKET_POSITION") -and
        $text.Contains("SHARPEMU_WRITE_DATA_PACKET_POSITION") -and
        $text.Contains("packetPositionWriteV74025") -and
        $text.Contains("[V74.0.25][WAIT_RESUME]")
}

function Test-HostLaneSupportV74026 {
    param([string]$Root)
    $path=Get-DirectPathV74026 -Root $Root
    if (-not [System.IO.File]::Exists($path)) { return $false }
    $text=[System.IO.File]::ReadAllText($path)
    return $text.Contains("SHARPEMU_RESERVED_HOST_LANES") -and
        $text.Contains("MapGuestCpuAcrossSmtLanes") -and
        $text.Contains("Environment.ProcessorCount * 3 / 8") -and
        $text.Contains("Demon's Souls' job pool runs ~90% busy")
}

function Invoke-DotNetCheckedV74026 {
    param([string]$Root,[string[]]$Arguments)
    Push-Location $Root
    try {
        & dotnet @Arguments
        if ($LASTEXITCODE -ne 0) { throw "[V74.0.26] dotnet failed with exit code $LASTEXITCODE" }
    } finally { Pop-Location }
}

function Sync-ReleaseRuntimeAssetsV74026 {
    param([string]$Root)
    $debugRoot=[System.IO.Path]::Combine($Root,"artifacts","bin","Debug","net10.0","win-x64")
    $releaseRoot=[System.IO.Path]::Combine($Root,"artifacts","bin","Release","net10.0","win-x64")
    if (-not [System.IO.Directory]::Exists($releaseRoot)) { return }
    foreach ($assetName in @("plugins","pipeline_cache")) {
        $sourcePath=[System.IO.Path]::Combine($debugRoot,$assetName)
        $destinationPath=[System.IO.Path]::Combine($releaseRoot,$assetName)
        if ([System.IO.Directory]::Exists($sourcePath)) {
            if (-not [System.IO.Directory]::Exists($destinationPath)) { [System.IO.Directory]::CreateDirectory($destinationPath) | Out-Null }
            Copy-Item -Path ([System.IO.Path]::Combine($sourcePath,"*")) -Destination $destinationPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Read-TextSharedV74026 {
    param([string]$Path)
    if (-not [System.IO.File]::Exists($Path)) { return "" }
    for ($attemptIndex=0;$attemptIndex -lt 5;$attemptIndex++) {
        try {
            $stream=[System.IO.File]::Open($Path,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
            try {
                $reader=[System.IO.StreamReader]::new($stream,[System.Text.Encoding]::UTF8,$true,65536,$false)
                try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
            } finally { $stream.Dispose() }
        } catch { Start-Sleep -Milliseconds 100 }
    }
    return ""
}

function Get-DescendantProcessIdsV74026 {
    param([int]$ParentId)
    $result=New-Object 'System.Collections.Generic.List[int]'
    $queue=New-Object 'System.Collections.Generic.Queue[int]'
    $queue.Enqueue($ParentId)
    while ($queue.Count -gt 0) {
        $currentId=$queue.Dequeue()
        $children=@(Get-CimInstance Win32_Process -Filter "ParentProcessId=$currentId" -ErrorAction SilentlyContinue)
        foreach ($childProcess in $children) {
            $childId=[int]$childProcess.ProcessId
            if (-not $result.Contains($childId)) { $result.Add($childId); $queue.Enqueue($childId) }
        }
    }
    return @($result)
}

function Get-MaxCounterV74026 {
    param([string]$Text,[string]$Pattern)
    $maxValue=0
    foreach($counterMatch in [regex]::Matches($Text,$Pattern)) {
        [int]$parsedValue=0
        if([int]::TryParse($counterMatch.Groups[1].Value,[ref]$parsedValue) -and $parsedValue -gt $maxValue) { $maxValue=$parsedValue }
    }
    return $maxValue
}

function Convert-InvariantDoubleV74026 {
    param([string]$Value)
    [double]$parsed=0
    $normalized=$Value.Replace(",",".")
    if ([double]::TryParse($normalized,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$parsed)) { return $parsed }
    return 0.0
}

function Get-HostCpuForGuestV74026 {
    param([int]$GuestCpu,[int]$ProcessorCount,[int]$ReservedLanes)
    $usableLanes=[Math]::Max($ProcessorCount-$ReservedLanes,2)
    $physicalCores=[Math]::Floor($usableLanes/2)
    $lane=$GuestCpu % $usableLanes
    if ($lane -lt $physicalCores) { return $lane*2 }
    return (($lane-$physicalCores)*2)+1
}
