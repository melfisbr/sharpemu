$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$script:Tag='[V75.0.4.5-BINK-FFMPEG-INPROCESS-NIHAV-OFF-PS51]'
$script:PackageRootV75045=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

function Write-Tag([string]$Message){ Write-Host "$script:Tag $Message" }
function Get-PackageRoot { return $script:PackageRootV75045 }
function Get-PatchesRoot { return (Split-Path -Parent (Get-PackageRoot)) }
function Get-RepositoryRoot {
    $repo=Split-Path -Parent (Get-PatchesRoot)
    if(-not(Test-Path -LiteralPath (Join-Path $repo 'src') -PathType Container)){throw "$script:Tag repository root not found: $repo"}
    return $repo
}
function Get-Sha([string]$Path){ if(Test-Path -LiteralPath $Path -PathType Leaf){return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()};return '' }
function Get-ReleaseRoot { return (Join-Path (Get-RepositoryRoot) 'artifacts\bin\Release\net10.0\win-x64') }
function Get-DebugRoot { return (Join-Path (Get-RepositoryRoot) 'artifacts\bin\Debug\net10.0\win-x64') }
function Get-StatePath { return (Join-Path (Get-PatchesRoot) 'SharpEmu_V75_0_4_5_BINK_FFMPEG_INPROCESS_STATE.json') }
function Get-FfmpegAutoGenVersion {
    $repo=Get-RepositoryRoot
    $central=Join-Path $repo 'Directory.Packages.props'
    if(Test-Path -LiteralPath $central -PathType Leaf){
        try{
            [xml]$xml=Get-Content -LiteralPath $central -Raw
            $node=@($xml.Project.ItemGroup.PackageVersion | Where-Object { $_.Include -eq 'FFmpeg.AutoGen' } | Select-Object -First 1)
            if($node.Count -gt 0 -and -not[string]::IsNullOrWhiteSpace([string]$node[0].Version)){return [string]$node[0].Version}
        }catch{}
    }
    return ''
}
function Assert-FfmpegAbiMatch {
    $v=Get-FfmpegAutoGenVersion
    if(-not[string]::IsNullOrWhiteSpace($v) -and $v -ne '7.1.1'){throw "$script:Tag FFmpeg.AutoGen ABI mismatch: fork=$v expected=7.1.1 for ffmpeg-core tag 3b502d4"}
    if([string]::IsNullOrWhiteSpace($v)){Write-Tag 'FFmpeg.AutoGen version could not be read from Directory.Packages.props; continuing with runtime tag 3b502d4.'}
    else{Write-Tag "FFmpeg ABI MATCH AutoGen=$v runtime_tag=3b502d4"}
}
function Stop-SharpEmu { Get-Process SharpEmu -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }
function Get-PeMachine([string]$Path){
    $s=[IO.File]::OpenRead($Path)
    try{
        $br=New-Object IO.BinaryReader($s)
        if($br.ReadUInt16() -ne 0x5A4D){return 0}
        $s.Position=0x3C;$pe=$br.ReadInt32();if($pe -lt 0 -or $pe -gt ($s.Length-8)){return 0}
        $s.Position=$pe;if($br.ReadUInt32() -ne 0x00004550){return 0};return [int]$br.ReadUInt16()
    }finally{$s.Dispose()}
}
function Read-Normalized([string]$Path){ return ([IO.File]::ReadAllText($Path)).Replace("`r`n","`n") }
function Write-PreservedText([string]$Path,[string]$Normalized,[bool]$UsesCrLf,[bool]$HasBom){
    $write=if($UsesCrLf){$Normalized.Replace("`n","`r`n")}else{$Normalized}
    $enc=[Text.UTF8Encoding]::new($HasBom)
    [IO.File]::WriteAllText($Path,$write,$enc)
}
function Replace-Once([string]$Text,[string]$Old,[string]$New,[string]$Label){
    $first=$Text.IndexOf($Old,[StringComparison]::Ordinal)
    if($first -lt 0){throw "$script:Tag transform anchor missing: $Label"}
    $second=$Text.IndexOf($Old,$first+$Old.Length,[StringComparison]::Ordinal)
    if($second -ge 0){throw "$script:Tag transform anchor ambiguous: $Label"}
    return $Text.Substring(0,$first)+$New+$Text.Substring($first+$Old.Length)
}
function Get-FfmpegFixedBaselines {
    return @(
      [pscustomobject]@{Rel='src\SharpEmu.Libs\Media\FfmpegVideoDecoder.cs';Original='28D2B22FED690080F297B2FB7535013468A8B383474FC24D1C6038F5F66C7146';Prior='C7AE18D138CE354276F77F2A30591E9070472C713121AAF0B557BB027DDB1AF5';Patched='EB5A20ECC3786E2566E49C15661E7BB6CD9918D564649B548A91DEA07762779A'},
      [pscustomobject]@{Rel='src\SharpEmu.Libs\Media\FfmpegRuntime.cs';Original='5FE39A47B9BE569B2680E2B650669692D7EF761ECB5D76899E010BA679542498';Prior='412EFB24328DB338899235FB141DEB39063657EB4FCC996E88155040CE68277B';Patched='C265293A80D77CFC2627512BCCEDE352F0EA29D9D50073C115D3FA05DFFBCD01'}
    )
}
function Test-OwnershipPrerequisites([string]$Repo){
    $hostMoviePath=Join-Path $Repo 'src\SharpEmu.Libs\Media\HostMovieBridge.cs'
    $nihav=Join-Path $Repo 'src\SharpEmu.Libs\Media\NihavBink2Decoder.cs'
    if(-not(Test-Path $hostMoviePath)){throw "$script:Tag HostMovieBridge missing"}
    if(-not(Test-Path $nihav)){throw "$script:Tag NihavBink2Decoder missing"}
    $ht=[IO.File]::ReadAllText($hostMoviePath);$nt=[IO.File]::ReadAllText($nihav)
    foreach($needle in @('SHARPEMU_BINK_NATIVE_NIHAV_OWNERSHIP_V75_0_4_1','_nativeRadExclusiveOwnerActiveV75041','AttachRadNativeMovieLocked')){if(-not$ht.Contains($needle)){throw "$script:Tag V75.0.4.3 ownership prerequisite missing in HostMovieBridge: $needle"}}
    foreach($needle in @('SHARPEMU_BINK_NATIVE_NIHAV_OWNERSHIP_V75_0_4_1','nihav_suppressed','IsNativeRadExclusiveOwnerActiveV75041')){if(-not$nt.Contains($needle)){throw "$script:Tag V75.0.4.3 Nihav suppression prerequisite missing: $needle"}}
}
function Invoke-HostFfmpegTransform {
    param([Parameter(Mandatory=$true)][string]$Path,[switch]$Apply)
    $bytes=[IO.File]::ReadAllBytes($Path)
    $hasBom=$bytes.Length -ge 3 -and $bytes[0]-eq 0xEF -and $bytes[1]-eq 0xBB -and $bytes[2]-eq 0xBF
    $raw=[IO.File]::ReadAllText($Path);$usesCrLf=$raw.Contains("`r`n");$text=$raw.Replace("`r`n","`n")
    $before=Get-Sha $Path;$changed=0
    if(-not$text.Contains('SHARPEMU_BINK_FFMPEG_INPROCESS_HOST_V75_0_4_5')){
        # Replace only the V75 native attach method; unrelated fork changes remain untouched.
        $start=$text.IndexOf('private static bool AttachRadNativeMovieLocked(',[StringComparison]::Ordinal)
        if($start -lt 0){throw "$script:Tag AttachRadNativeMovieLocked locator missing"}
        $end=$text.IndexOf('private static bool AttachRadMovieLocked(', $start+1,[StringComparison]::Ordinal)
        if($end -lt 0){throw "$script:Tag AttachRadMovieLocked boundary missing"}
        # Preserve indentation before the next method.
        while($end -gt 0 -and ($text[$end-1] -eq ' ' -or $text[$end-1] -eq "`t")){$end--}
        $newAttach=Read-Normalized (Join-Path (Get-PackageRoot) 'transforms\host_movie_bridge\ffmpeg_inprocess_attach.new.txt')
        $text=$text.Substring(0,$start)+$newAttach+"`n"+$text.Substring($end)
        $changed++

        # Persistent main_menu loop must reopen through the same FFmpeg owner.
        $loopMethod=$text.IndexOf('private static bool TryRestartDemonSoulsUiBinkLoopV74088(',[StringComparison]::Ordinal)
        if($loopMethod -lt 0){throw "$script:Tag UI loop method locator missing"}
        $loopStart=$text.IndexOf('if (restartMode == MovieMode.NativeRad)', $loopMethod,[StringComparison]::Ordinal)
        $loopEnd=$text.IndexOf('else if (NihavBink2Decoder.TryOpen(', $loopStart,[StringComparison]::Ordinal)
        if($loopStart -lt 0 -or $loopEnd -lt 0){throw "$script:Tag NativeRad UI loop block locator missing"}
        $lineStart=$text.LastIndexOf("`n",$loopStart);if($lineStart -lt 0){$lineStart=0}else{$lineStart++}
        $lineEnd=$text.LastIndexOf("`n",$loopEnd);if($lineEnd -lt 0){throw "$script:Tag UI loop else line boundary missing"};$lineEnd++
        $newLoop=Read-Normalized (Join-Path (Get-PackageRoot) 'transforms\host_movie_bridge\ffmpeg_inprocess_loop.new.txt')
        $text=$text.Substring(0,$lineStart)+$newLoop+$text.Substring($lineEnd)
        $changed++

        $oldOwner='return RadBinkNativeSdkDecoderV7500.IsRuntimeAvailable &&'
        $newOwner="return (FfmpegRuntime.IsRuntimeCandidatePresent ||`n               RadBinkNativeSdkDecoderV7500.IsRuntimeAvailable) &&"
        if($text.Contains($oldOwner)){$text=Replace-Once $text $oldOwner $newOwner 'native owner availability';$changed++}
        elseif(-not$text.Contains('FfmpegRuntime.IsRuntimeCandidatePresent ||')){throw "$script:Tag native owner availability form is incompatible"}

        $oldAuto = @(
            'Environment.GetEnvironmentVariable('
            '                "SHARPEMU_BINK_NATIVE_PREFER") != "0" &&'
            '            RadBinkNativeSdkDecoderV7500.IsRuntimeAvailable)'
        ) -join "`n"
        $newAuto = @(
            'Environment.GetEnvironmentVariable('
            '                "SHARPEMU_BINK_NATIVE_PREFER") != "0" &&'
            '            (FfmpegRuntime.IsRuntimeCandidatePresent ||'
            '             RadBinkNativeSdkDecoderV7500.IsRuntimeAvailable))'
        ) -join "`n"
        if($text.Contains($oldAuto)){$text=Replace-Once $text $oldAuto $newAuto 'rad auto-select availability';$changed++}
        elseif(-not($text.Contains('SHARPEMU_BINK_NATIVE_PREFER') -and $text.Contains('FfmpegRuntime.IsRuntimeCandidatePresent'))){throw "$script:Tag rad auto-select form is incompatible"}
    }

    foreach($needle in @('SHARPEMU_BINK_FFMPEG_INPROCESS_HOST_V75_0_4_5','TryOpenPreferredNativeRadDecoderV75045','FfmpegVideoDecoder.TryOpen','SHARPEMU_BINK_LEGACY_ADAPTER_FALLBACK','decoder={backend}','nihav_owner=False native_rad_owner=True')){if(-not$text.Contains($needle)){throw "$script:Tag FFmpeg host postcondition missing: $needle"}}
    $attachStart=$text.IndexOf('private static bool AttachRadNativeMovieLocked(',[StringComparison]::Ordinal)
    $attachEnd=$text.IndexOf('private static bool AttachRadMovieLocked(', $attachStart+1,[StringComparison]::Ordinal)
    if($attachStart -lt 0 -or $attachEnd -lt 0){throw "$script:Tag transformed attach method boundaries invalid"}
    $attachSegment=$text.Substring($attachStart,$attachEnd-$attachStart)
    if($attachSegment.Contains('AttachNihavMovieLocked') -or $attachSegment.Contains('NihavBink2Decoder.TryOpen')){throw "$script:Tag Nihav fallback detected inside NativeRad attach method"}
    if($Apply -and $changed -gt 0){Write-PreservedText $Path $text $usesCrLf $hasBom}
    return [pscustomobject]@{Before=$before;Changed=$changed;Already=($changed -eq 0)}
}
