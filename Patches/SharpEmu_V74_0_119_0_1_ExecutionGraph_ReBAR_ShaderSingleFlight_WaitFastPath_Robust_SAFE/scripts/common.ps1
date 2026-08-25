Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$script:Tag='[V74.0.119.0.1-EXECUTION-GRAPH-REBAR-SHADER-SINGLEFLIGHT-WAIT-FASTPATH-ROBUST-SAFE]'
$script:Version='V74.0.119.0.1'
$script:StateName='SharpEmu_V74_0_119_0_1_STATE.json'
$script:LastBackupName='SharpEmu_V74_0_119_0_1_LAST_BACKUP.txt'

function Write-Tag([string]$Message){Write-Host "$script:Tag $Message"}
function Get-PackageRoot{Split-Path -Parent $PSScriptRoot}
function Get-PatchesRoot{Split-Path -Parent (Get-PackageRoot)}
function Get-RepositoryRoot{
    $r=Split-Path -Parent (Get-PatchesRoot)
    if(-not(Test-Path -LiteralPath (Join-Path $r 'src') -PathType Container)){
        throw "$script:Tag repository root not found: $r"
    }
    [IO.Path]::GetFullPath($r)
}
function Get-Sha([string]$Path){
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return ''}
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}
function Write-Utf8NoBom([string]$Path,[string]$Text){
    $enc=New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($Path,$Text,$enc)
}
function Parse-PowerShell([string]$Path){
    $tokens=$null;$errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile(
        $Path,[ref]$tokens,[ref]$errors)
    if($errors.Count-gt0){
        throw "$script:Tag AST parse failed: $Path :: $((@($errors|ForEach-Object{$_.Message})-join ' | '))"
    }
}
function Get-StatePath{Join-Path (Get-PatchesRoot) $script:StateName}
function Save-State([int]$Phase,[string]$Status,[hashtable]$Extra){
    $data=[ordered]@{
        version=$script:Version
        timestamp=(Get-Date).ToString('o')
        phase=$Phase
        status=$Status
    }
    if($null-ne$Extra){foreach($k in $Extra.Keys){$data[$k]=$Extra[$k]}}
    Write-Utf8NoBom (Get-StatePath) (($data|ConvertTo-Json -Depth 8)+"`r`n")
}
function Read-State([int]$MinPhase){
    $p=Get-StatePath
    if(-not(Test-Path -LiteralPath $p)){throw "$script:Tag state missing; run earlier phase"}
    $s=Get-Content -LiteralPath $p -Raw|ConvertFrom-Json
    if([int]$s.phase-lt$MinPhase){throw "$script:Tag state phase=$($s.phase) required=$MinPhase"}
    $s
}
function Get-AgcSource{
    $p=Join-Path (Get-RepositoryRoot) 'src\SharpEmu.Libs\Agc\AgcExports.cs'
    if(-not(Test-Path $p -PathType Leaf)){throw "$script:Tag AgcExports.cs missing"};$p
}
function Get-PresenterSource{
    $p=Join-Path (Get-RepositoryRoot) 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
    if(-not(Test-Path $p -PathType Leaf)){throw "$script:Tag VulkanVideoPresenter.cs missing"};$p
}
function Get-HostPoolSource{
    $p=Join-Path (Get-RepositoryRoot) 'src\SharpEmu.Libs\VideoOut\VulkanHostBufferPool.cs'
    if(-not(Test-Path $p -PathType Leaf)){throw "$script:Tag VulkanHostBufferPool.cs missing"};$p
}
function Get-EnvelopeSource{
    $p=Join-Path (Get-RepositoryRoot) 'src\SharpEmu.CLI\DemonsSoulsGpuQueueEnvelopeV74011224.cs'
    if(-not(Test-Path $p -PathType Leaf)){throw "$script:Tag queue envelope missing"};$p
}
function Assert-Baseline{
    $a=[IO.File]::ReadAllText((Get-AgcSource))
    foreach($m in @(
        '_graphicsShaderCache',
        '_computeShaderCache',
        'HasLatchedSatisfiedV74100',
        'DrainResumableDcbs',
        'MonitorGpuWaits'
    )){
        if(-not$a.Contains($m)){throw "$script:Tag AGC baseline missing: $m"}
    }

    $p=[IO.File]::ReadAllText((Get-PresenterSource))
    foreach($m in @(
        'SHARPEMU_V74_0_118_0_GPU_RESIDENT_SHADER_ID',
        'SHARPEMU_V74_0_117_16_DESCRIPTOR_SET_BLOCK_CACHE',
        'ResidentShaderProgramV1180',
        'CreateDeferredReadOnlyGlobalBufferResourceV11712',
        'CreateHostBufferUninitializedV11712'
    )){
        if(-not$p.Contains($m)){throw "$script:Tag V118.0.1 presenter baseline missing: $m"}
    }
    if($p.Contains('SHARPEMU_V74_0_117_15_TEXTURE_BACKING_VIEW_ALIAS')){
        throw "$script:Tag V117.15 texture alias is present. Refuse this baseline."
    }

    $q=[IO.File]::ReadAllText((Get-EnvelopeSource))
    foreach($m in @(
        'SHARPEMU_V74_0_118_0_GPU_RESIDENT_SHADER_ENVELOPE',
        'SHARPEMU_DESCRIPTOR_SET_CACHE_V11716',
        'SHARPEMU_PENDING_GUEST_WORK_PRODUCER_ITEMS'
    )){
        if(-not$q.Contains($m)){throw "$script:Tag V118.0.1 envelope baseline missing: $m"}
    }
}
function Assert-V1190Markers(
    [string]$Agc,
    [string]$Presenter,
    [string]$HostPool,
    [string]$Envelope)
{
    $a=[IO.File]::ReadAllText($Agc)
    foreach($m in @(
        'SHARPEMU_V74_0_119_0_SHADER_SINGLEFLIGHT',
        'SHARPEMU_V74_0_119_0_WAITER_EVENT_FASTPATH',
        'GetGraphicsShaderCompileGateV1190',
        'GetComputeShaderCompileGateV1190',
        '[V74.0.119.0][EXECUTION_GRAPH]'
    )){
        if(-not$a.Contains($m)){throw "$script:Tag V119 AGC marker missing: $m"}
    }

    $p=[IO.File]::ReadAllText($Presenter)
    foreach($m in @(
        'SHARPEMU_V74_0_119_0_RESIDENT_SHADER_REFERENCE_FASTPATH',
        'SHARPEMU_V74_0_119_0_REBAR_GLOBAL_DIRECT',
        'SourceReferenceV1190',
        'TryCreateRebarHostBufferUninitializedV1190',
        '[V74.0.119.0][REBAR_GLOBAL_DIRECT]'
    )){
        if(-not$p.Contains($m)){throw "$script:Tag V119 presenter marker missing: $m"}
    }

    $h=[IO.File]::ReadAllText($HostPool)
    if(-not$h.Contains('MemoryClassV1190')){
        throw "$script:Tag V119 host pool key marker missing"
    }

    $q=[IO.File]::ReadAllText($Envelope)
    foreach($m in @(
        'SHARPEMU_V74_0_119_0_EXECUTION_GRAPH_ENVELOPE',
        'SHARPEMU_SHADER_SINGLEFLIGHT_V1190',
        'SHARPEMU_REBAR_GLOBAL_DIRECT_V1190',
        'SHARPEMU_PROFILE_RENDER'
    )){
        if(-not$q.Contains($m)){throw "$script:Tag V119 envelope marker missing: $m"}
    }
}
