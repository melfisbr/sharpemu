Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$script:Tag='[V74.0.118.7.6.3.12-DS-RAD-UI-PS5-TEXTURE-COMPOSE]'
$script:Version='V74.0.118.7.6.3.12'
$script:PackageRoot=Split-Path -Parent $PSScriptRoot

$script:ExpectedHostApiSha='7B70AF4489F275C1555E1BD2FCBB0B68C02619113F89ACEFBF3AE709457BE84D'
$script:ExpectedPresenterSha='0C1277923F8C24685AD682A4BDDD53082AB8C4CC43E49AB982D6A6ECB9FF64B4'
$script:ExpectedPartialSha='BFE9FAE11DE7F09E02317BC32760B35A3C90328418D65F0390F8CA5BECDD0063'
$script:ExpectedShaderSha='D925B12854CEE751236CAAFDF2D5E64F89AE3007F27FADDFBE136BCBD6EF66EE'
$script:ExpectedAmprSha='C315447D326ECCB6C0E40C33B7EE20B38571E6B1CD42567F7D1CA2E64FAE0519'

$script:PayloadHostApiSha='39EF8601349B2086464C1A990AFD216B19D86882AA6FE1F2C42DDCB1D8BBB9FD'
$script:PayloadPresenterSha='086EB8CAD532C59C8BC0EA0EBFAF1739C37DFBDDFA5CC40C2EDCAF45167C54AB'

$script:RelativeHostApi='src\SharpEmu.Libs\Media\RadBinkEmbeddedHostApiV724323171.cs'
$script:RelativePresenter='src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$script:RelativePartial='src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.RadUiSingleSurfaceV1187632.cs'
$script:RelativeShader='src\SharpEmu.ShaderCompiler.Vulkan\RadUiBlackKeyShaderV1187632.cs'
$script:RelativeAmpr='src\SharpEmu.Libs\Ampr\AmprExports.cs'

function Write-Tag([string]$Message){Write-Host "$script:Tag $Message"}
function Get-PatchesRoot{Split-Path -Parent $script:PackageRoot}
function Get-RepositoryRoot{
    $repo=Split-Path -Parent (Get-PatchesRoot)
    if(-not(Test-Path -LiteralPath (Join-Path $repo 'src'))){
        throw "$script:Tag repository root not found: $repo"
    }
    $repo
}
function Get-Sha([string]$Path){
    if(-not(Test-Path -LiteralPath $Path)){return ''}
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()
}
function Get-StatePath{
    Join-Path (Get-PatchesRoot) 'SharpEmu_V74_0_118_7_6_3_12_INSTALL_STATE.json'
}
function Get-BackupPointer{
    Join-Path (Get-PatchesRoot) 'SharpEmu_V74_0_118_7_6_3_12_LAST_BACKUP.txt'
}
function Get-HostPayload{
    Join-Path $script:PackageRoot 'payloads\RadBinkEmbeddedHostApiV724323171.cs'
}
function Get-PresenterPayload{
    Join-Path $script:PackageRoot 'payloads\VulkanVideoPresenter.cs'
}
function Get-LatestDotnetSdkRoot{
    $rows=@(& dotnet --list-sdks 2>$null)
    if($LASTEXITCODE -ne 0 -or $rows.Count -eq 0){
        throw "$script:Tag dotnet --list-sdks failed"
    }
    $parsed=@()
    foreach($row in $rows){
        if($row -match '^\s*([0-9][^\s]*)\s+\[(.+)\]\s*$'){
            $parsed += [pscustomobject]@{Version=$matches[1];Base=$matches[2]}
        }
    }
    $selected=$parsed | Sort-Object {
        try{[version]($_.Version.Split('-')[0])}
        catch{[version]'0.0'}
    } -Descending | Select-Object -First 1
    if($null -eq $selected){throw "$script:Tag could not resolve .NET SDK"}
    Join-Path $selected.Base $selected.Version
}
function Invoke-CSharpSyntaxProbe([string]$Path,[string]$Label){
    $sdk=Get-LatestDotnetSdkRoot
    $csc=Join-Path $sdk 'Roslyn\bincore\csc.dll'
    if(-not(Test-Path -LiteralPath $csc)){
        throw "$script:Tag csc.dll missing: $csc"
    }
    $dotnet=(Get-Command dotnet -CommandType Application -ErrorAction Stop).Source
    $compilerOutput=[string[]]@(
        & $dotnet $csc /nologo /noconfig /nostdlib /target:library /langversion:preview $Path 2>&1 |
            ForEach-Object{[string]$_}
    )
    $syntaxIds='CS1002|CS1003|CS1009|CS1010|CS1011|CS1012|CS1022|CS1024|CS1031|CS1039|CS1040|CS1513|CS1514|CS1519|CS1525|CS1733|CS8076|CS8086|CS8124|CS8803'
    $syntaxErrors=[string[]]@(
        $compilerOutput | Where-Object {
            $_ -match (':\s*error\s+('+$syntaxIds+')\s*:')
        }
    )
    if($syntaxErrors.Count -ne 0){
        throw "$script:Tag C# syntax failed ($Label): $($syntaxErrors -join ' | ')"
    }
    Write-Tag "SyntaxProbe=$Label PASSED sdk=$sdk"
}
function Assert-Baseline{
    $repo=Get-RepositoryRoot
    $hostApiPath=Join-Path $repo $script:RelativeHostApi
    $presenterPath=Join-Path $repo $script:RelativePresenter
    $partialPath=Join-Path $repo $script:RelativePartial
    $shaderPath=Join-Path $repo $script:RelativeShader
    $amprPath=Join-Path $repo $script:RelativeAmpr

    foreach($path in @($hostApiPath,$presenterPath,$partialPath,$shaderPath,$amprPath)){
        if(-not(Test-Path -LiteralPath $path)){
            throw "$script:Tag required source missing: $path"
        }
    }

    $hostSha=Get-Sha $hostApiPath
    $presenterSha=Get-Sha $presenterPath
    $partialSha=Get-Sha $partialPath
    $shaderSha=Get-Sha $shaderPath
    $amprSha=Get-Sha $amprPath

    Write-Tag "CurrentHostApiSHA=$hostSha"
    Write-Tag "CurrentPresenterSHA=$presenterSha"
    Write-Tag "CurrentPartialSHA=$partialSha"
    Write-Tag "CurrentShaderSHA=$shaderSha"
    Write-Tag "CurrentAmprSHA=$amprSha"

    $already=
        $hostSha -eq $script:PayloadHostApiSha -and
        $presenterSha -eq $script:PayloadPresenterSha

    if(-not$already){
        if($hostSha -ne $script:ExpectedHostApiSha){
            throw "$script:Tag HostApi baseline mismatch expected=$script:ExpectedHostApiSha actual=$hostSha"
        }
        if($presenterSha -ne $script:ExpectedPresenterSha){
            throw "$script:Tag Presenter baseline mismatch expected=$script:ExpectedPresenterSha actual=$presenterSha"
        }
    }

    if($partialSha -ne $script:ExpectedPartialSha){
        throw "$script:Tag partial baseline mismatch expected=$script:ExpectedPartialSha actual=$partialSha"
    }
    if($shaderSha -ne $script:ExpectedShaderSha){
        throw "$script:Tag shader baseline mismatch expected=$script:ExpectedShaderSha actual=$shaderSha"
    }
    if($amprSha -ne $script:ExpectedAmprSha){
        throw "$script:Tag AMPR baseline mismatch expected=$script:ExpectedAmprSha actual=$amprSha"
    }

    $hostText=[IO.File]::ReadAllText($hostApiPath)
    $presenterText=[IO.File]::ReadAllText($presenterPath)

    if($already){
        foreach($marker in @(
            'SHARPEMU_V74_0_118_7_6_3_12_RAD_UI_TEXTURE_CAPTURE',
            'RAD_UI_TEXTURE_CAPTURE_REGION')){
            if(-not$hostText.Contains($marker)){
                throw "$script:Tag installed HostApi marker missing: $marker"
            }
        }
        foreach($marker in @(
            'SHARPEMU_V74_0_118_7_6_3_12_RAD_UI_TEXTURE_CAPTURE',
            'RAD_UI_DESCRIPTORLESS_KEEP_GUEST',
            'RAD_UI_PRESENT_HANDOFF')){
            if(-not$presenterText.Contains($marker)){
                throw "$script:Tag installed Presenter marker missing: $marker"
            }
        }
    } else {
        if(-not$hostText.Contains('SHARPEMU_V74_0_118_7_6_3_11_MAIN_MENU_INTRO_LOOP_PARITY')){
            throw "$script:Tag expected V3.11 HostApi marker missing"
        }
        if(-not$presenterText.Contains('SHARPEMU_V74_0_118_7_6_3_2_MINIMAL_PRESENT_PATCH')){
            throw "$script:Tag expected Presenter integration marker missing"
        }
    }

    [pscustomobject]@{
        Already=$already
        HostApi=$hostApiPath
        Presenter=$presenterPath
        Partial=$partialPath
        Shader=$shaderPath
        Ampr=$amprPath
    }
}
function Resolve-RadVideo64{
    $configured=[Environment]::GetEnvironmentVariable('SHARPEMU_RADVIDEO64','Process')
    if($configured -and(Test-Path -LiteralPath $configured)){
        return (Resolve-Path -LiteralPath $configured).Path
    }
    $candidate=Join-Path ${env:ProgramFiles(x86)} 'RADVideo\radvideo64.exe'
    if(Test-Path -LiteralPath $candidate){
        return (Resolve-Path -LiteralPath $candidate).Path
    }
    $null
}
function Set-TestEnvironment{
    $rad=Resolve-RadVideo64
    if($null -eq $rad){throw "$script:Tag RADVideo64 not found"}

    $env:SHARPEMU_RADVIDEO64=$rad
    $env:SHARPEMU_BINK_MODE='rad'

    # Prefer the in-process licensed SDK adapter if the user has it. Current
    # machines without SharpEmu.BinkNative.dll automatically remain external RAD.
    $env:SHARPEMU_BINK_NATIVE_PREFER='1'

    $env:SHARPEMU_RAD_PLAYER_INPUT_LOCK='1'
    $env:SHARPEMU_DS_UI_BINK_RAD_INTERACTIVE='1'
    $env:SHARPEMU_DS_UI_BINK_INTERNAL='0'
    $env:SHARPEMU_DS_RAD_UI_NATIVE_LOOP_SYNC='1'
    $env:SHARPEMU_DS_RAD_UI_SWAPCHAIN_CONTINUITY='1'

    $env:SHARPEMU_DS_RAD_UI_TEXTURE_CAPTURE='1'
    $env:SHARPEMU_DS_RAD_UI_TEXTURE_CAPTURE_FPS='15'

    # Explicitly disable every legacy final-compositor experiment.
    $env:SHARPEMU_DS_RAD_MAIN_MENU_CAPTURE_COMPOSITE='0'
    $env:SHARPEMU_DS_RAD_MAIN_MENU_CAPTURE_EXPERIMENTAL='0'

    # Remains available only as legacy fallback if texture capture is manually disabled.
    $env:SHARPEMU_DS_RAD_UI_NEUTRAL_YUV='1'

    $env:SHARPEMU_LOG_AUDIO_OUT2='1'
    $env:SHARPEMU_LOG_AMPR_READS='1'

    Write-Tag "RAD=$rad mode=rad native_prefer=1 texture_capture=1 final_owner=guest-vulkan"
}
