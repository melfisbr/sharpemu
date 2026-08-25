Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$script:Tag='[V74.0.120.0-DRAW-FEED-NOALLOC-GLOBAL-LOOKUP-LAYOUT-CANONICAL-PROFILE-SAFE]'
$script:Version='V74.0.120.0'
$script:StateName='SharpEmu_V74_0_120_0_STATE.json'
$script:LastBackupName='SharpEmu_V74_0_120_0_LAST_BACKUP.txt'

function Write-Tag([string]$Message){Write-Host "$script:Tag $Message"}
function Get-PackageRoot{Split-Path -Parent $PSScriptRoot}
function Get-PatchesRoot{Split-Path -Parent (Get-PackageRoot)}
function Get-RepositoryRoot{
    $root=Split-Path -Parent (Get-PatchesRoot)
    if(-not(Test-Path -LiteralPath (Join-Path $root 'src') -PathType Container)){
        throw "$script:Tag repository root not found: $root"
    }
    [IO.Path]::GetFullPath($root)
}
function Get-PresenterSource{
    $path=Join-Path (Get-RepositoryRoot) 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "$script:Tag VulkanVideoPresenter.cs missing"}
    $path
}
function Get-Sha([string]$Path){
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return ''}
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}
function Write-Utf8NoBom([string]$Path,[string]$Text){
    $enc=New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($Path,$Text,$enc)
}
function Parse-PowerShellFile([string]$Path){
    $tokens=$null;$errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile(
        $Path,[ref]$tokens,[ref]$errors)
    if($errors.Count-gt0){
        throw "$script:Tag PowerShell AST failed $Path :: $((@($errors|ForEach-Object{$_.Message})-join ' | '))"
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
    if($Extra){foreach($key in $Extra.Keys){$data[$key]=$Extra[$key]}}
    Write-Utf8NoBom (Get-StatePath) (($data|ConvertTo-Json -Depth 8)+"`r`n")
}
function Read-State([int]$MinimumPhase){
    $path=Get-StatePath
    if(-not(Test-Path -LiteralPath $path)){throw "$script:Tag state missing"}
    $state=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
    if([int]$state.phase-lt$MinimumPhase){
        throw "$script:Tag state phase=$($state.phase) required=$MinimumPhase"
    }
    $state
}
function Assert-Baseline([string]$Presenter){
    $text=[IO.File]::ReadAllText($Presenter)
    foreach($marker in @(
        'SHARPEMU_V74_0_117_16_DESCRIPTOR_SET_BLOCK_CACHE',
        'SHARPEMU_V74_0_118_0_GPU_RESIDENT_SHADER_ID',
        'SHARPEMU_V74_0_56_23_DRAW_RESOURCE_PHASES',
        'PrepareGuestBufferAllocations',
        '_guestBufferAllocations.Sort',
        'CreateTranslatedDrawResources'
    )){
        if(-not$text.Contains($marker)){throw "$script:Tag baseline marker missing: $marker"}
    }
    if(-not($text.Contains('REBAR_GLOBAL_DIRECT') -or
            $text.Contains('SHARPEMU_V74_0_119_0_REBAR_GLOBAL_DIRECT'))){
        throw "$script:Tag V119 ReBAR/execution-graph source marker missing; current source is not the tested V118.0.1/V119 baseline"
    }
    if($text.Contains('SHARPEMU_V74_0_117_15_TEXTURE_BACKING_VIEW_ALIAS')){
        throw "$script:Tag forbidden V117.15 texture-backing alias marker present"
    }
}
function Assert-V120Markers([string]$Presenter){
    $text=[IO.File]::ReadAllText($Presenter)
    foreach($marker in @(
        'SHARPEMU_V74_0_120_0_DRAW_FEED_HOTPATH',
        'FindGuestBufferAllocationV120',
        'ResourceLayoutShapeV120',
        'TargetFormatLayoutShapeV120',
        'BlendLayoutShapeV120',
        'GetCanonicalResourceLayoutKeyV120',
        'GetCanonicalRenderTargetLayoutKeyV120',
        'GetCanonicalBlendLayoutKeyV120',
        'FindFeedbackTargetV120',
        '[V74.0.120.0][DRAW_HOTPATH]'
    )){
        if(-not$text.Contains($marker)){throw "$script:Tag V120 marker missing: $marker"}
    }
}
