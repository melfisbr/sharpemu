$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$Tag='[V75.0.4.6-BINK-FFMPEG-INPROCESS-NIHAV-OFF-FETCHTARGET]'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
function Get-LocalSha([string]$Path){return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()}
function Get-LocalPeMachine([string]$Path){
    $stream=[IO.File]::OpenRead($Path)
    try{
        $reader=New-Object IO.BinaryReader($stream)
        if($reader.ReadUInt16() -ne 0x5A4D){return 0}
        $stream.Position=0x3C;$pe=$reader.ReadInt32();if($pe -lt 0 -or $pe -gt ($stream.Length-8)){return 0}
        $stream.Position=$pe;if($reader.ReadUInt32() -ne 0x00004550){return 0};return [int]$reader.ReadUInt16()
    }finally{$stream.Dispose()}
}
$manifest=Join-Path $root 'manifest.sha256'
if(-not(Test-Path -LiteralPath $manifest -PathType Leaf)){throw "$Tag manifest missing"}
$bad=New-Object System.Collections.Generic.List[string]
$manifestLines=@(Get-Content -LiteralPath $manifest | Where-Object { -not[string]::IsNullOrWhiteSpace($_) })
foreach($line in $manifestLines){
    $manifestMatch=[regex]::Match($line,'^([0-9A-Fa-f]{64}) \*(.+)$')
    if(-not$manifestMatch.Success){$bad.Add("invalid manifest line: $line");continue}
    $expected=$manifestMatch.Groups[1].Value.ToUpperInvariant();$rel=$manifestMatch.Groups[2].Value;$path=Join-Path $root $rel
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){$bad.Add("missing $rel");continue}
    $actual=Get-LocalSha $path;if($actual -ne $expected){$bad.Add("sha mismatch $rel expected=$expected actual=$actual")}
}
if($bad.Count){$bad|ForEach-Object{Write-Host $_};throw "$Tag validation failed count=$($bad.Count)"}

# Parse every PowerShell file with the real Windows PowerShell parser before dot-sourcing common.ps1.
$parseErrors=New-Object System.Collections.Generic.List[string]
$scriptFiles=@(Get-ChildItem -LiteralPath (Join-Path $root 'scripts') -File -Filter '*.ps1')
foreach($scriptFile in $scriptFiles){
    $tokens=$null;$errors=$null
    [System.Management.Automation.Language.Parser]::ParseFile($scriptFile.FullName,[ref]$tokens,[ref]$errors)|Out-Null
    foreach($parseError in @($errors)){$parseErrors.Add("$($scriptFile.Name):$($parseError.Extent.StartLineNumber):$($parseError.Message)")}
}
if($parseErrors.Count){$parseErrors|ForEach-Object{Write-Host $_};throw "$Tag PowerShell parse validation failed count=$($parseErrors.Count)"}

# Guards for the exact failures seen in V75.0.4.4.
$cStyleQuoteEscape=([string][char]92)+([string][char]34)
foreach($scriptFile in $scriptFiles){
    $scriptText=[IO.File]::ReadAllText($scriptFile.FullName)
    if($scriptText -match '(?im)\$host\s*='){throw "$Tag reserved automatic variable assignment found in $($scriptFile.Name): `$Host"}
    if($scriptText.Contains($cStyleQuoteEscape)){throw "$Tag C-style escaped quote found in PowerShell source: $($scriptFile.Name)"}
    if($scriptText -match '(?im)^\s*(?:&\s*)?(?:git|git\.exe)\s+(clone|fetch|pull|checkout|reset|clean|rebase|switch)\b'){throw "$Tag forbidden Git mutation command in $($scriptFile.Name)"}
    if($scriptText -match '(?i)Invoke-WebRequest|Start-BitsTransfer|curl(?:\.exe)?\s|wget(?:\.exe)?\s'){throw "$Tag package script contains direct network downloader: $($scriptFile.Name)"}
}


$setupText=[IO.File]::ReadAllText((Join-Path $root 'scripts\setup_ffmpegcore.ps1'))
if(-not $setupText.Contains("'-t:FetchFfmpegRuntime'")){throw "$Tag setup does not invoke local FetchFfmpegRuntime target directly"}
if(-not $setupText.Contains("'-p:RuntimeIdentifier=win-x64'")){throw "$Tag setup does not pin RuntimeIdentifier=win-x64"}
if($setupText -match '(?im)^\s*(?:&\s*)?(?:git|git\.exe)\s+'){throw "$Tag setup contains a Git command"}

# Payload and binary checks do not depend on common.ps1.
$payloadRuntime=Join-Path $root 'payload\src\SharpEmu.Libs\Media\FfmpegRuntime.cs'
$payloadDecoder=Join-Path $root 'payload\src\SharpEmu.Libs\Media\FfmpegVideoDecoder.cs'
if((Get-LocalSha $payloadRuntime) -ne 'C265293A80D77CFC2627512BCCEDE352F0EA29D9D50073C115D3FA05DFFBCD01'){throw "$Tag FfmpegRuntime payload hash mismatch"}
if((Get-LocalSha $payloadDecoder) -ne 'EB5A20ECC3786E2566E49C15661E7BB6CD9918D564649B548A91DEA07762779A'){throw "$Tag FfmpegVideoDecoder payload hash mismatch"}
$adapter=Join-Path $root 'bin\SharpEmu.BinkNative.dll'
if(-not(Test-Path -LiteralPath $adapter -PathType Leaf)){throw "$Tag compatibility adapter missing"}
if((Get-LocalPeMachine $adapter) -ne 0x8664){throw "$Tag compatibility adapter is not AMD64"}

# Only now dot-source the common helpers and run the structural/idempotence self-test.
. (Join-Path $PSScriptRoot 'common.ps1')
$reference=Join-Path $root 'reference\final\HostMovieBridge.cs'
if(-not(Test-Path -LiteralPath $reference -PathType Leaf)){throw "$Tag HostMovieBridge reference missing"}
$temp=Join-Path $env:TEMP ("SharpEmu_V75045_HostSelfTest_"+[Guid]::NewGuid().ToString('N')+'.cs')
try{
    Copy-Item -LiteralPath $reference -Destination $temp -Force
    $first=Invoke-HostFfmpegTransform -Path $temp -Apply
    $post=[IO.File]::ReadAllText($temp)
    if(-not$post.Contains('SHARPEMU_BINK_FFMPEG_INPROCESS_HOST_V75_0_4_5')){throw "$Tag structural selftest marker missing"}
    if($first.Changed -lt 3){throw "$Tag structural selftest changed too few regions: $($first.Changed)"}
    $second=Invoke-HostFfmpegTransform -Path $temp -Apply
    if($second.Changed -ne 0){throw "$Tag structural transform is not idempotent second_changed=$($second.Changed)"}
}finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force}}
Write-Host "$Tag VALIDATION PASSED files=$($manifestLines.Count) ps51_parser=True reserved_host_guard=True cstyle_quote_guard=True host_selftest=True idempotent=True machine=AMD64 git_mutation=False direct_downloader=False fetch_target=True"
