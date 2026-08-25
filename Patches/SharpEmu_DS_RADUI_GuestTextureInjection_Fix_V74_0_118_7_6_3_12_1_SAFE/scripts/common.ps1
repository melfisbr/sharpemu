Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:Tag='[V74.0.118.7.6.3.12.1-DS-RAD-UI-GUEST-TEXTURE-INJECTION]'
$script:Version='V74.0.118.7.6.3.12.1'
$script:PackageRoot=Split-Path -Parent $PSScriptRoot

$script:Files=[ordered]@{
  HostApi=[ordered]@{Rel='SharpEmu.Libs\Media\RadBinkEmbeddedHostApiV724323171.cs'; Before='7B70AF4489F275C1555E1BD2FCBB0B68C02619113F89ACEFBF3AE709457BE84D'; After='A091C1C2C7E209C99ECB45BD5A0E4F32524A1B8F29967DD11A1D9C40668345E1'}
  RadExternal=[ordered]@{Rel='SharpEmu.Libs\Media\RadBinkExternalPlaybackV7243231.cs'; Before='3CDD89DC37B145F781239F4D0136ED8A95FF2BF8B33ABCC65395A2FDAFFE4CA5'; After='5707A299CCE9BE9D4AF55A8D5E25C7BA7C08CA59FF8C7E9BA35EC74105A385DD'}
  Presenter=[ordered]@{Rel='SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'; Before='0C1277923F8C24685AD682A4BDDD53082AB8C4CC43E49AB982D6A6ECB9FF64B4'; After='4C8BCE7DE87A20AF6925404C5A45817B81383BDAA73D0A838B63AA8A8CB8CAE8'}
}
$script:Preserve=[ordered]@{
  Partial=[ordered]@{Rel='SharpEmu.Libs\VideoOut\VulkanVideoPresenter.RadUiSingleSurfaceV1187632.cs'; Sha='BFE9FAE11DE7F09E02317BC32760B35A3C90328418D65F0390F8CA5BECDD0063'}
  Shader=[ordered]@{Rel='SharpEmu.ShaderCompiler.Vulkan\RadUiBlackKeyShaderV1187632.cs'; Sha='D925B12854CEE751236CAAFDF2D5E64F89AE3007F27FADDFBE136BCBD6EF66EE'}
  HostMovie=[ordered]@{Rel='SharpEmu.Libs\Media\HostMovieBridge.cs'; Sha='D3BC791213F1815C5C3E2B2713E90590C507C685DA4C95E308E4E72A4923B91B'}
  VideoOut=[ordered]@{Rel='SharpEmu.Libs\VideoOut\VideoOutExports.cs'; Sha='28DB0828DBBCDD089A7B70AAD1CC8F290BDC446E018F5B6493E77B4AD42C84F7'}
  Ampr=[ordered]@{Rel='SharpEmu.Libs\Ampr\AmprExports.cs'; Sha='C315447D326ECCB6C0E40C33B7EE20B38571E6B1CD42567F7D1CA2E64FAE0519'}
}
function Write-Tag([string]$Message){Write-Host "$script:Tag $Message"}
function Get-PatchesRoot { Split-Path -Parent $script:PackageRoot }
function Get-RepositoryRoot {
    $repo=Split-Path -Parent (Get-PatchesRoot)
    if(-not(Test-Path -LiteralPath (Join-Path $repo 'src'))){throw "$script:Tag repository root not found: $repo"}
    $repo
}
function Get-StatePath { Join-Path (Get-PatchesRoot) 'SharpEmu_V74_0_118_7_6_3_12_1_INSTALL_STATE.json' }
function Get-BackupPointer { Join-Path (Get-PatchesRoot) 'SharpEmu_V74_0_118_7_6_3_12_1_LAST_BACKUP.txt' }
function Get-Sha([string]$Path){ if(-not(Test-Path -LiteralPath $Path)){return ''}; (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant() }
function Get-SourcePath([string]$Rel){ Join-Path (Join-Path (Get-RepositoryRoot) 'src') $Rel }
function Get-PayloadPath([string]$Rel){ Join-Path (Join-Path $script:PackageRoot 'payload') $Rel }
function Get-LatestDotnetSdkRoot {
    $rows=@(& dotnet --list-sdks 2>$null)
    if($LASTEXITCODE -ne 0 -or $rows.Count -eq 0){throw "$script:Tag dotnet --list-sdks failed"}
    $parsed=@()
    foreach($row in $rows){
        if($row -match '^\s*([0-9][^\s]*)\s+\[(.+)\]\s*$'){
            $parsed += [pscustomobject]@{Version=$matches[1];Base=$matches[2]}
        }
    }
    $selected=$parsed|Sort-Object {try{[version]($_.Version.Split('-')[0])}catch{[version]'0.0'}} -Descending|Select-Object -First 1
    if($null -eq $selected){throw "$script:Tag could not resolve .NET SDK"}
    Join-Path $selected.Base $selected.Version
}
function Invoke-CSharpSyntaxProbe([string]$Path,[string]$Label){
    $sdk=Get-LatestDotnetSdkRoot
    $csc=Join-Path $sdk 'Roslyn\bincore\csc.dll'
    if(-not(Test-Path -LiteralPath $csc)){throw "$script:Tag csc.dll missing: $csc"}
    $dotnet=(Get-Command dotnet -CommandType Application -ErrorAction Stop).Source
    $output=@(& $dotnet $csc /nologo /noconfig /nostdlib /target:library /langversion:preview $Path 2>&1|ForEach-Object{"$_"})
    $syntaxIds=@('CS0106','CS0116','CS1002','CS1003','CS1009','CS1010','CS1011','CS1012','CS1022','CS1024','CS1026','CS1031','CS1039','CS1040','CS1513','CS1514','CS1519','CS1525','CS1733','CS8076','CS8086','CS8124','CS8803')
    $syntax=@()
    foreach($line in $output){
        foreach($id in $syntaxIds){
            if($line -match ("\berror\s+"+[regex]::Escape($id)+"\b")){$syntax += $line.Trim(); break}
        }
    }
    if($syntax.Count -ne 0){throw "$script:Tag C# syntax failed ($Label): $($syntax -join ' | ')"}
    Write-Tag "SyntaxProbe=$Label PASSED sdk=$sdk"
}
function Get-BaselineState {
    $sourceState=[ordered]@{}
    $allBefore=$true; $allAfter=$true
    foreach($entry in $script:Files.GetEnumerator()){
        $path=Get-SourcePath $entry.Value.Rel
        if(-not(Test-Path -LiteralPath $path)){throw "$script:Tag source missing: $path"}
        $sha=Get-Sha $path
        Write-Tag "Current$($entry.Key)SHA=$sha"
        $sourceState[$entry.Key]=[ordered]@{Path=$path;Sha=$sha}
        if($sha -ne $entry.Value.Before){$allBefore=$false}
        if($sha -ne $entry.Value.After){$allAfter=$false}
    }
    foreach($entry in $script:Preserve.GetEnumerator()){
        $path=Get-SourcePath $entry.Value.Rel
        if(-not(Test-Path -LiteralPath $path)){throw "$script:Tag preserved prerequisite missing: $path"}
        $sha=Get-Sha $path
        Write-Tag "Current$($entry.Key)SHA=$sha"
        if($sha -ne $entry.Value.Sha){throw "$script:Tag $($entry.Key) baseline mismatch expected=$($entry.Value.Sha) actual=$sha"}
    }
    if($allBefore){return [pscustomobject]@{State='original';Sources=$sourceState}}
    if($allAfter){return [pscustomobject]@{State='installed';Sources=$sourceState}}
    throw "$script:Tag mixed/drifted V3.11/V3.12 source state; nothing changed"
}
function Assert-Payloads {
    foreach($entry in $script:Files.GetEnumerator()){
        $path=Get-PayloadPath $entry.Value.Rel
        if(-not(Test-Path -LiteralPath $path)){throw "$script:Tag payload missing: $path"}
        $sha=Get-Sha $path
        if($sha -ne $entry.Value.After){throw "$script:Tag payload hash mismatch $($entry.Key) expected=$($entry.Value.After) actual=$sha"}
        Invoke-CSharpSyntaxProbe $path $entry.Key
    }
}
function Resolve-RadVideo64 {
    $configured=[Environment]::GetEnvironmentVariable('SHARPEMU_RADVIDEO64','Process')
    if($configured -and(Test-Path -LiteralPath $configured)){return (Resolve-Path -LiteralPath $configured).Path}
    $candidate=Join-Path ${env:ProgramFiles(x86)} 'RADVideo\radvideo64.exe'
    if(Test-Path -LiteralPath $candidate){return (Resolve-Path -LiteralPath $candidate).Path}
    $null
}
function Set-TestEnvironment {
    $rad=Resolve-RadVideo64
    if($null -eq $rad){throw "$script:Tag RADVideo64 not found"}
    $env:SHARPEMU_RADVIDEO64=$rad
    $env:SHARPEMU_BINK_MODE='rad'
    $env:SHARPEMU_BINK_NATIVE_PREFER='0'
    $env:SHARPEMU_RAD_PLAYER_INPUT_LOCK='1'
    $env:SHARPEMU_DS_UI_BINK_RAD_INTERACTIVE='1'
    $env:SHARPEMU_DS_UI_BINK_INTERNAL='0'
    $env:SHARPEMU_DS_RAD_UI_NATIVE_LOOP_SYNC='1'
    $env:SHARPEMU_DS_RAD_UI_TEXTURE_INJECTION='1'
    $env:SHARPEMU_DS_RAD_UI_TEXTURE_CAPTURE_FPS='10'
    $env:SHARPEMU_DS_RAD_MAIN_MENU_CAPTURE_COMPOSITE='0'
    $env:SHARPEMU_DS_RAD_MAIN_MENU_CAPTURE_EXPERIMENTAL='0'
    $env:SHARPEMU_DS_RAD_UI_NEUTRAL_YUV='0'
    $env:SHARPEMU_DS_UI_BINK_CHROMA_ORDER='uv'
    $env:SHARPEMU_DS_RAD_UI_SWAPCHAIN_CONTINUITY='1'
    $env:SHARPEMU_LOG_AUDIO_OUT2='1'
    $env:SHARPEMU_LOG_AMPR_READS='1'
    Write-Tag "RAD=$rad integration=rad-frame-source-to-guest-yuv final_owner=guest-videoout texture_injection=1 capture_fps=10 chroma=uv"
}
