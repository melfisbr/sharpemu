Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:Tag='[V75.0.4.3-BINK-NATIVE-AV-NIHAV-OWNER-LOCALFORK]'
# Use a uniquely named script-scope variable. PowerShell variable names are
# case-insensitive; V75.0.4.1 accidentally reused $packageRoot in RUN_4 and
# zeroed $script:PackageRoot. Do not reuse this identifier for local state.
$script:PackageRootV75043=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

function Write-Tag([string]$Message){ Write-Host "$script:Tag $Message" }
function Get-PackageRootV75043 { return $script:PackageRootV75043 }
function Get-PatchesRoot { return (Split-Path -Parent (Get-PackageRootV75043)) }
function Get-RepositoryRoot {
    $patches=Get-PatchesRoot
    $repo=Split-Path -Parent $patches
    if(-not(Test-Path -LiteralPath (Join-Path $repo 'src') -PathType Container)){ throw "$script:Tag repository root not found: $repo" }
    return $repo
}
function Get-Sha([string]$Path){ if(Test-Path -LiteralPath $Path -PathType Leaf){ return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant() }; return '' }
function Get-TextSha([string]$Text){
    $sha=[Security.Cryptography.SHA256]::Create()
    try { $bytes=[Text.Encoding]::UTF8.GetBytes($Text); return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','') }
    finally { $sha.Dispose() }
}
function Get-PeMachine([string]$Path){
    $s=[IO.File]::OpenRead($Path)
    try{
        $br=New-Object IO.BinaryReader($s)
        if($br.ReadUInt16() -ne 0x5A4D){return 0}
        $s.Position=0x3C;$pe=$br.ReadInt32()
        if($pe -lt 0 -or $pe -gt ($s.Length-8)){return 0}
        $s.Position=$pe
        if($br.ReadUInt32() -ne 0x00004550){return 0}
        return [int]$br.ReadUInt16()
    }finally{$s.Dispose()}
}
function Get-AdapterPath { return (Join-Path (Get-PackageRootV75043) 'bin\SharpEmu.BinkNative.dll') }
function Get-ReleaseRoot { return (Join-Path (Get-RepositoryRoot) 'artifacts\bin\Release\net10.0\win-x64') }
function Get-DebugRoot { return (Join-Path (Get-RepositoryRoot) 'artifacts\bin\Debug\net10.0\win-x64') }
function Get-PluginDirs { return @((Join-Path (Get-ReleaseRoot) 'plugins\bink2'),(Join-Path (Get-DebugRoot) 'plugins\bink2')) }
function Get-StatePath { return (Join-Path (Get-PatchesRoot) 'SharpEmu_V75_0_4_3_BINK_NATIVE_FFMPEGCORE_AV_STATE.json') }
function Stop-SharpEmu { Get-Process SharpEmu -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }

# Files whose V75.0.4/V75.0.4.1 updates are safe as exact replacements because
# the user's failing precheck proved the first three remain on an accepted hash.
# Policy is also guarded by the same 3-state hash check before any write.
function Get-FixedBaselines {
    return @(
      [pscustomobject]@{Rel='src\SharpEmu.Libs\Media\BinkNativeSdkAbiV7500.cs';Original='CF93BEF4C1DAED11500A28A83F25C1A72407A84ED9371EF31C5E72399A8D9494';Intermediate='38DCE90830E561D1C571CCD3CE1E016DD026BAFD79AF2B5A773E76B122C7A3A6';Patched='38DCE90830E561D1C571CCD3CE1E016DD026BAFD79AF2B5A773E76B122C7A3A6'},
      [pscustomobject]@{Rel='src\SharpEmu.Libs\Media\RadBinkNativeSdkDecoderV7500.cs';Original='E65A0D5896832F3955561983933E4E1C7558501DE143EFE11D3E647731A452C6';Intermediate='BD2A709C3E16444A793D3B21118E40AACC1A9D383AF5CA2B580FBA1782159CBB';Patched='BD2A709C3E16444A793D3B21118E40AACC1A9D383AF5CA2B580FBA1782159CBB'},
      [pscustomobject]@{Rel='src\SharpEmu.Libs\Media\MediaFramePlayback.cs';Original='C1403289699A4F51E83BC7F0CCF09ABF563A46C356D282AB1CFDF8432088CB37';Intermediate='298DBCC42C732276F65567947A5BD3E4EE260F17A50208D37C0DC7741A0C13A2';Patched='298DBCC42C732276F65567947A5BD3E4EE260F17A50208D37C0DC7741A0C13A2'},
      [pscustomobject]@{Rel='src\SharpEmu.Libs\Media\DemonSoulsGuestOwnedRadBootPolicyV317209.cs';Original='724006D61ED862C45EBB694825CF926D5F0CC9B20BDE0C342A8B173342F53885';Intermediate='F448508341FEB293478F991B6397D9129824CC30BA7B863C853C88D3FD44F7AF';Patched='B4FF81A67AA764EED1CD611E1E6629FD450DF379CAD1017534D92403ECADE643'}
    )
}
function Get-StructuralTargets {
    return @(
      [pscustomobject]@{Rel='src\SharpEmu.Libs\Media\HostMovieBridge.cs';Transform='transforms\host_movie_bridge';Marker='SHARPEMU_BINK_NATIVE_NIHAV_OWNERSHIP_V75_0_4_1'},
      [pscustomobject]@{Rel='src\SharpEmu.Libs\Media\NihavBink2Decoder.cs';Transform='transforms\nihav';Marker='SHARPEMU_BINK_NATIVE_NIHAV_OWNERSHIP_V75_0_4_1'}
    )
}
function Count-Ordinal([string]$Text,[string]$Needle){
    if([string]::IsNullOrEmpty($Needle)){return 0}
    $count=0;$offset=0
    while($true){$i=$Text.IndexOf($Needle,$offset,[StringComparison]::Ordinal);if($i -lt 0){break};$count++;$offset=$i+$Needle.Length}
    return $count
}
function Test-HostOwnershipSemanticPostconditions([string]$Text){
    $required=@(
      '_nativeRadExclusiveOwnerActiveV75041',
      'legacy_nihav_route_promoted',
      'Volatile.Write(ref _nativeRadExclusiveOwnerActiveV75041, 1);',
      'private static bool NativeRadExclusiveOwnerEnabledV75041()',
      'if (NativeRadExclusiveOwnerEnabledV75041())',
      'Volatile.Write(ref _nativeRadExclusiveOwnerActiveV75041, 0);'
    )
    foreach($needle in $required){if(-not $Text.Contains($needle)){throw "$script:Tag HostMovieBridge ownership postcondition missing: $needle"}}

    # External RAD/radvideo64 fallback must never be the implicit path. If this
    # fork still has such a fallback branch, it must be explicit opt-in (=1).
    if($Text -match '(?s)SHARPEMU_BINK_NATIVE_FALLBACK.{0,260}!=\s*"0".{0,260}AttachRadMovieLocked'){
        throw "$script:Tag HostMovieBridge still contains implicit external-RAD fallback (!= 0); refusing local fork modification"
    }
}
function Test-NihavOwnershipSemanticPostconditions([string]$Text){
    $required=@('SHARPEMU_BINK_NATIVE_NIHAV_OWNERSHIP_V75_0_4_1','nihav_suppressed','IsNativeRadExclusiveOwnerActiveV75041')
    foreach($needle in $required){if(-not $Text.Contains($needle)){throw "$script:Tag Nihav ownership postcondition missing: $needle"}}
}
function Get-HunkSemanticNeedle([string]$TransformRelative,[string]$Name){
    if($TransformRelative -eq 'transforms\host_movie_bridge'){
      switch($Name){
        'h01.old.txt' { return '_nativeRadExclusiveOwnerActiveV75041' }
        'h02.old.txt' { return 'restartMode == MovieMode.NativeRad' }
        'h03.old.txt' { return 'result=rewound size={info.Width}x{info.Height} mode={restartMode}' }
        'h04.old.txt' { return 'ResolveMode() == MovieMode.NativeRad' }
        'h05.old.txt' { return 'legacy_nihav_route_promoted' }
        'h07.old.txt' { return 'Volatile.Write(ref _nativeRadExclusiveOwnerActiveV75041, 1);' }
        'h08.old.txt' { return 'decoder=native-ffmpeg-core-av' }
        'h09.old.txt' { return 'private static bool NativeRadExclusiveOwnerEnabledV75041()' }
        'h10.old.txt' { return 'if (NativeRadExclusiveOwnerEnabledV75041())' }
        'h11.old.txt' { return 'Volatile.Write(ref _nativeRadExclusiveOwnerActiveV75041, 0);' }
        'h12.old.txt' { return 'completionMode != MovieMode.NativeRad' }
        'h13.old.txt' { return 'var completionMode = ResolveMode();' }
      }
    } elseif($TransformRelative -eq 'transforms\nihav') {
      switch($Name){
        'n01.old.txt' { return 'SHARPEMU_BINK_NATIVE_NIHAV_OWNERSHIP_V75_0_4_1' }
        'n02.old.txt' { return 'nihav_suppressed' }
      }
    }
    return $null
}
function Invoke-StructuralTransform {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$TransformRelative,[switch]$Apply)
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "$script:Tag structural source missing: $Path"}
    $bytes=[IO.File]::ReadAllBytes($Path)
    $hasBom=$bytes.Length -ge 3 -and $bytes[0]-eq 0xEF -and $bytes[1]-eq 0xBB -and $bytes[2]-eq 0xBF
    $raw=[IO.File]::ReadAllText($Path)
    $usesCrLf=$raw.Contains("`r`n")
    $text=$raw.Replace("`r`n","`n")
    $before=Get-Sha $Path
    $dir=Join-Path (Get-PackageRootV75043) $TransformRelative
    $olds=@(Get-ChildItem -LiteralPath $dir -File -Filter '*.old.txt' | Sort-Object Name)
    if($olds.Count -eq 0){throw "$script:Tag no transforms found: $TransformRelative"}
    $applied=0;$already=0;$semanticAlready=0;$optionalAbsent=0
    foreach($oldFile in $olds){
        $newPath=$oldFile.FullName -replace '\.old\.txt$','.new.txt'
        if(-not(Test-Path -LiteralPath $newPath -PathType Leaf)){throw "$script:Tag transform pair missing: $newPath"}
        $old=([IO.File]::ReadAllText($oldFile.FullName)).Replace("`r`n","`n")
        $new=([IO.File]::ReadAllText($newPath)).Replace("`r`n","`n")
        $oldCount=Count-Ordinal $text $old
        $newCount=Count-Ordinal $text $new
        if($newCount -eq 1){$already++;continue}
        if($oldCount -eq 1){
            $idx=$text.IndexOf($old,[StringComparison]::Ordinal)
            $text=$text.Substring(0,$idx)+$new+$text.Substring($idx+$old.Length)
            $applied++
            continue
        }

        # Preserve local-fork improvements: if a hunk was reformatted/reworked
        # but its semantic postcondition is already present, accept it without
        # rewriting that section. h06 is special: a newer fork may have removed
        # external RAD fallback entirely, which is safer than our old hunk.
        $semantic=Get-HunkSemanticNeedle $TransformRelative $oldFile.Name
        if($semantic -and $text.Contains($semantic)){
            if($oldFile.Name -eq 'h13.old.txt'){
                if((Count-Ordinal $text $semantic) -ge 2){$semanticAlready++;continue}
            }else{$semanticAlready++;continue}
        }
        if($TransformRelative -eq 'transforms\host_movie_bridge' -and $oldFile.Name -eq 'h06.old.txt'){
            $optionalAbsent++
            continue
        }
        throw "$script:Tag structural transform incompatible file=$Path hunk=$($oldFile.BaseName) old_count=$oldCount new_count=$newCount semantic_present=$([bool]($semantic -and $text.Contains($semantic)))"
    }

    if($TransformRelative -eq 'transforms\host_movie_bridge'){Test-HostOwnershipSemanticPostconditions $text}
    if($TransformRelative -eq 'transforms\nihav'){Test-NihavOwnershipSemanticPostconditions $text}

    if($Apply){
        $writeText=if($usesCrLf){$text.Replace("`n","`r`n")}else{$text}
        $enc=[Text.UTF8Encoding]::new([bool]$hasBom)
        [IO.File]::WriteAllText($Path,$writeText,$enc)
    }
    return [pscustomobject]@{Before=$before;Applied=$applied;Already=$already;SemanticAlready=$semanticAlready;OptionalAbsent=$optionalAbsent;Hunks=$olds.Count;PreviewSha=(Get-TextSha $text)}
}
