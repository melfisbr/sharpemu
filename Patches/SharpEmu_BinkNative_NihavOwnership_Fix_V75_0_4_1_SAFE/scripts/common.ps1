Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:Tag='[V75.0.4.1-BINK-NATIVE-FFMPEGCORE-AV-NIHAV-OWNER]'
$script:PackageRoot=Split-Path -Parent $PSScriptRoot

function Write-Tag([string]$Message){ Write-Host "$script:Tag $Message" }
function Get-PatchesRoot { Split-Path -Parent $script:PackageRoot }
function Get-RepositoryRoot {
    $patches=Get-PatchesRoot
    $repo=Split-Path -Parent $patches
    if(-not(Test-Path -LiteralPath (Join-Path $repo 'src') -PathType Container)){ throw "$script:Tag repository root not found: $repo" }
    return $repo
}
function Get-Sha([string]$Path){ if(Test-Path -LiteralPath $Path -PathType Leaf){ return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant() }; return '' }
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
function Get-AdapterPath { Join-Path $script:PackageRoot 'bin\SharpEmu.BinkNative.dll' }
function Get-ReleaseRoot { Join-Path (Get-RepositoryRoot) 'artifacts\bin\Release\net10.0\win-x64' }
function Get-DebugRoot { Join-Path (Get-RepositoryRoot) 'artifacts\bin\Debug\net10.0\win-x64' }
function Get-PluginDirs {
    @((Join-Path (Get-ReleaseRoot) 'plugins\bink2'),(Join-Path (Get-DebugRoot) 'plugins\bink2'))
}
function Get-StatePath { Join-Path (Get-PatchesRoot) 'SharpEmu_V75_0_4_1_BINK_NATIVE_FFMPEGCORE_AV_STATE.json' }
function Get-Baselines {
    @(
      [pscustomobject]@{Rel='src\SharpEmu.Libs\Media\BinkNativeSdkAbiV7500.cs';Original='CF93BEF4C1DAED11500A28A83F25C1A72407A84ED9371EF31C5E72399A8D9494';Intermediate='38DCE90830E561D1C571CCD3CE1E016DD026BAFD79AF2B5A773E76B122C7A3A6';Patched='38DCE90830E561D1C571CCD3CE1E016DD026BAFD79AF2B5A773E76B122C7A3A6'},
      [pscustomobject]@{Rel='src\SharpEmu.Libs\Media\RadBinkNativeSdkDecoderV7500.cs';Original='E65A0D5896832F3955561983933E4E1C7558501DE143EFE11D3E647731A452C6';Intermediate='BD2A709C3E16444A793D3B21118E40AACC1A9D383AF5CA2B580FBA1782159CBB';Patched='BD2A709C3E16444A793D3B21118E40AACC1A9D383AF5CA2B580FBA1782159CBB'},
      [pscustomobject]@{Rel='src\SharpEmu.Libs\Media\MediaFramePlayback.cs';Original='C1403289699A4F51E83BC7F0CCF09ABF563A46C356D282AB1CFDF8432088CB37';Intermediate='298DBCC42C732276F65567947A5BD3E4EE260F17A50208D37C0DC7741A0C13A2';Patched='298DBCC42C732276F65567947A5BD3E4EE260F17A50208D37C0DC7741A0C13A2'},
      [pscustomobject]@{Rel='src\SharpEmu.Libs\Media\HostMovieBridge.cs';Original='D3BC791213F1815C5C3E2B2713E90590C507C685DA4C95E308E4E72A4923B91B';Intermediate='33430C179DF9F845652EC8862A69AD6224E0C507C34AAF9B32718E911A96A36E';Patched='1DF2C816E16659E2AE21CFDE9ECA2BE85AD5D733BF905BCC6CF330D548ADADC0'},
      [pscustomobject]@{Rel='src\SharpEmu.Libs\Media\DemonSoulsGuestOwnedRadBootPolicyV317209.cs';Original='724006D61ED862C45EBB694825CF926D5F0CC9B20BDE0C342A8B173342F53885';Intermediate='F448508341FEB293478F991B6397D9129824CC30BA7B863C853C88D3FD44F7AF';Patched='B4FF81A67AA764EED1CD611E1E6629FD450DF379CAD1017534D92403ECADE643'},
      [pscustomobject]@{Rel='src\SharpEmu.Libs\Media\NihavBink2Decoder.cs';Original='658A46C1ACD8CF5FB40DC955D47A1357AD8E925C1E40C526B9D5DECA00D4B80F';Intermediate='658A46C1ACD8CF5FB40DC955D47A1357AD8E925C1E40C526B9D5DECA00D4B80F';Patched='68DA0EB56AE8947375C51A25ABD2CF61C6B2DD6F5B48EC82A755A50F56F5FEA2'}
    )
}
function Stop-SharpEmu { Get-Process SharpEmu -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }
