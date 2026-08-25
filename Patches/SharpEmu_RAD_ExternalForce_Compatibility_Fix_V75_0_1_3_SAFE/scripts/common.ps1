Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$script:Tag='[V75.0.1.3-RAD-EXTERNAL-COMPAT]'
$script:Version='V75.0.1.3'
$script:PackageRoot=Split-Path -Parent $PSScriptRoot

$script:ExpectedHostSha='D3BC791213F1815C5C3E2B2713E90590C507C685DA4C95E308E4E72A4923B91B'
$script:ExpectedPlaybackSha='C1403289699A4F51E83BC7F0CCF09ABF563A46C356D282AB1CFDF8432088CB37'
$script:ExpectedAbiSha='CF93BEF4C1DAED11500A28A83F25C1A72407A84ED9371EF31C5E72399A8D9494'
$script:ExpectedDecoderSha='E65A0D5896832F3955561983933E4E1C7558501DE143EFE11D3E647731A452C6'
$script:PreviewHostSha='E50C35B7A3FFBCFEEF6A5F4DCC5685350921E3AF8CEB39B6916F83C35535F708'

$script:RelativeHost='src\SharpEmu.Libs\Media\HostMovieBridge.cs'
$script:RelativePlayback='src\SharpEmu.Libs\Media\MediaFramePlayback.cs'
$script:RelativeAbi='src\SharpEmu.Libs\Media\BinkNativeSdkAbiV7500.cs'
$script:RelativeDecoder='src\SharpEmu.Libs\Media\RadBinkNativeSdkDecoderV7500.cs'

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
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return ''}
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()
}
function Get-StatePath{
    Join-Path (Get-PatchesRoot) 'SharpEmu_V75_0_1_3_RAD_EXTERNAL_STATE.json'
}
function Get-BackupPointer{
    Join-Path (Get-PatchesRoot) 'SharpEmu_V75_0_1_3_LAST_BACKUP.txt'
}
function Normalize-Lf([string]$Text){
    if($null -eq $Text){return ''}
    $Text.Replace("`r`n","`n").Replace("`r","`n")
}
function Get-TextStyle([string]$Path){
    $bytes=[IO.File]::ReadAllBytes($Path)
    $hasBom=$bytes.Length -ge 3 -and
        $bytes[0] -eq 0xEF -and
        $bytes[1] -eq 0xBB -and
        $bytes[2] -eq 0xBF
    $raw=[IO.File]::ReadAllText($Path)
    [pscustomobject]@{Raw=$raw;UseCrlf=$raw.Contains("`r`n");UseBom=$hasBom}
}
function Write-SourceText([string]$Path,[string]$Text,[bool]$UseCrlf,[bool]$UseBom){
    $value=Normalize-Lf $Text
    if($UseCrlf){$value=$value.Replace("`n","`r`n")}
    $encoding=New-Object System.Text.UTF8Encoding($UseBom)
    [IO.File]::WriteAllText($Path,$value,$encoding)
}
function Get-TransformPairs{
    $dir=Join-Path $script:PackageRoot 'transforms\hostmovie'
    $olds=@(Get-ChildItem -LiteralPath $dir -File -Filter '*.old.txt'|Sort-Object Name)
    $pairs=@()
    foreach($old in $olds){
        $new=$old.FullName.Replace('.old.txt','.new.txt')
        if(-not(Test-Path -LiteralPath $new -PathType Leaf)){
            throw "$script:Tag transform pair missing: $new"
        }
        $pairs += [pscustomobject]@{Id=$old.BaseName.Replace('.old','');Old=$old.FullName;New=$new}
    }
    $pairs
}
function Get-HunkState([string]$Text,[string]$Old,[string]$New){
    $oldCount=([regex]::Matches($Text,[regex]::Escape($Old))).Count
    $newCount=([regex]::Matches($Text,[regex]::Escape($New))).Count
    $state='invalid'
    if($oldCount -eq 1 -and $newCount -eq 0){$state='original'}
    elseif($oldCount -eq 0 -and $newCount -eq 1){$state='patched'}
    [pscustomobject]@{State=$state;OldCount=$oldCount;NewCount=$newCount}
}
function Invoke-HostPatch([string]$Source,[string]$Destination){
    $style=Get-TextStyle $Source
    $text=Normalize-Lf $style.Raw
    $applied=0
    $already=0
    foreach($pair in @(Get-TransformPairs)){
        $old=Normalize-Lf([IO.File]::ReadAllText($pair.Old))
        $new=Normalize-Lf([IO.File]::ReadAllText($pair.New))
        $shape=Get-HunkState $text $old $new
        if($shape.State -eq 'original'){
            $idx=$text.IndexOf($old,[StringComparison]::Ordinal)
            $text=$text.Remove($idx,$old.Length).Insert($idx,$new)
            $applied++
        }elseif($shape.State -eq 'patched'){
            $already++
        }else{
            throw "$script:Tag unsupported HostMovieBridge shape $($pair.Id): old=$($shape.OldCount) new=$($shape.NewCount)"
        }
    }
    Write-SourceText $Destination $text $style.UseCrlf $style.UseBom
    [pscustomobject]@{Applied=$applied;Already=$already;Before=(Get-Sha $Source);After=(Get-Sha $Destination)}
}
function Get-CurrentState{
    $repo=Get-RepositoryRoot
    $hostPath=Join-Path $repo $script:RelativeHost
    $playback=Join-Path $repo $script:RelativePlayback
    $abi=Join-Path $repo $script:RelativeAbi
    $decoder=Join-Path $repo $script:RelativeDecoder
    foreach($path in @($hostPath,$playback,$abi,$decoder)){
        if(-not(Test-Path -LiteralPath $path -PathType Leaf)){
            throw "$script:Tag required source missing: $path"
        }
    }
    $hostText=[IO.File]::ReadAllText($hostPath)
    $playText=[IO.File]::ReadAllText($playback)
    [pscustomobject]@{
        Host=$hostPath
        Playback=$playback
        Abi=$abi
        Decoder=$decoder
        HostSha=(Get-Sha $hostPath)
        PlaybackSha=(Get-Sha $playback)
        AbiSha=(Get-Sha $abi)
        DecoderSha=(Get-Sha $decoder)
        AlreadyPatched=$hostText.Contains('SHARPEMU_V75_0_1_3_EXTERNAL_RAD_COMPATIBILITY_FORCE')
        HasPixelLayout=$playText.Contains('internal enum MediaFramePixelLayout')
        HasPixelLayoutSource=$playText.Contains('internal interface IMediaFramePixelLayoutSource')
        HasV74105=$playText.Contains('SHARPEMU_V74_0_105_UI_BINK_DIRECT_YUV')
        HasV74110=$playText.Contains('SHARPEMU_V74_0_110_UI_BINK_TIME_AWARE_RESERVOIR')
    }
}
function Assert-CompatibilityBaseline{
    $s=Get-CurrentState
    Write-Tag "CurrentHostMovieSHA=$($s.HostSha)"
    Write-Tag "CurrentPlaybackSHA=$($s.PlaybackSha)"
    Write-Tag "CurrentAbiSHA=$($s.AbiSha)"
    Write-Tag "CurrentDecoderSHA=$($s.DecoderSha)"
    Write-Tag "MediaFramePixelLayout=$($s.HasPixelLayout)"
    Write-Tag "IMediaFramePixelLayoutSource=$($s.HasPixelLayoutSource)"
    Write-Tag "V74_0_105_DirectYuv=$($s.HasV74105)"
    Write-Tag "V74_0_110_Reservoir=$($s.HasV74110)"

    if(-not$s.AlreadyPatched -and $s.HostSha -ne $script:ExpectedHostSha){
        throw "$script:Tag HostMovieBridge baseline mismatch expected=$script:ExpectedHostSha actual=$($s.HostSha)"
    }
    if($s.PlaybackSha -ne $script:ExpectedPlaybackSha){
        throw "$script:Tag MediaFramePlayback changed; refusing destructive rollback expected=$script:ExpectedPlaybackSha actual=$($s.PlaybackSha)"
    }
    if($s.AbiSha -ne $script:ExpectedAbiSha -or $s.DecoderSha -ne $script:ExpectedDecoderSha){
        throw "$script:Tag V75 managed adapter sources changed; package leaves them compile-only and requires the observed baseline"
    }
    if(-not$s.HasPixelLayout -or -not$s.HasPixelLayoutSource -or -not$s.HasV74105){
        throw "$script:Tag compatibility contracts missing; do NOT restore pre-V75 MediaFramePlayback"
    }
    $s
}
function Get-NativeAdapterPaths{
    $repo=Get-RepositoryRoot
    @(
        (Join-Path $repo 'artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\SharpEmu.BinkNative.dll'),
        (Join-Path $repo 'artifacts\bin\Release\net10.0\win-x64\plugins\bink2\SharpEmu.BinkNative.dll')
    )
}
function Backup-And-RemoveNativeAdapter([string]$BackupRoot){
    foreach($path in @(Get-NativeAdapterPaths)){
        if(Test-Path -LiteralPath $path -PathType Leaf){
            $label=if($path -like '*\Debug\*'){'Debug_SharpEmu.BinkNative.dll'}else{'Release_SharpEmu.BinkNative.dll'}
            if(-not[string]::IsNullOrWhiteSpace($BackupRoot)){
                Copy-Item -LiteralPath $path -Destination (Join-Path $BackupRoot $label) -Force
            }
            Remove-Item -LiteralPath $path -Force
            Write-Tag "RemovedNativeAdapter=$path"
        }
    }
}
function Get-InstalledRadVideo64{
    $configured=[Environment]::GetEnvironmentVariable('SHARPEMU_RADVIDEO64','Process')
    if(-not[string]::IsNullOrWhiteSpace($configured) -and (Test-Path -LiteralPath $configured -PathType Leaf)){
        return (Resolve-Path -LiteralPath $configured).Path
    }
    $pf86=${env:ProgramFiles(x86)}
    if(-not[string]::IsNullOrWhiteSpace($pf86)){
        $candidate=Join-Path $pf86 'RADVideo\radvideo64.exe'
        if(Test-Path -LiteralPath $candidate -PathType Leaf){
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    $null
}
function Set-ExternalRadEnvironment{
    $rad=Get-InstalledRadVideo64
    if($null -eq $rad){throw "$script:Tag official RAD executable not found"}
    Remove-Item Env:SHARPEMU_BINK_NATIVE_DLL -ErrorAction SilentlyContinue
    Remove-Item Env:SHARPEMU_BINK_RUNTIME_DLL -ErrorAction SilentlyContinue
    $env:SHARPEMU_RADVIDEO64=$rad
    $env:SHARPEMU_BINK_MODE='external-rad'
    $env:SHARPEMU_BINK_NATIVE_PREFER='0'
    $env:SHARPEMU_BINK_NATIVE_FALLBACK='1'
    $env:SHARPEMU_DS_UI_BINK_RAD_INTERACTIVE='1'
    $env:SHARPEMU_DS_UI_BINK_INTERNAL='0'
    $env:SHARPEMU_LOG_AUDIO_OUT2='1'
    $env:SHARPEMU_LOG_AMPR_READS='1'
    Write-Tag "ExternalRAD=$rad mode=external-rad native_prefer=0"
}
