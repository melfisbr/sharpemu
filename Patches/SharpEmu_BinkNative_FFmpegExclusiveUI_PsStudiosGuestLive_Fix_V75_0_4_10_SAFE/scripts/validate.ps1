$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$Tag='[V75.0.4.10-BINK-FFMPEG-EXCLUSIVE-UI-PS-STUDIOS-GUEST-LIVE]'
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
# V75.0.4.7: command-policy checks use the parsed AST, not raw text.
# This prevents the validator from flagging its own detector strings as executable download commands.
$cStyleQuoteEscape=([string][char]92)+([string][char]34)
foreach($scriptFile in $scriptFiles){
    $scriptText=[IO.File]::ReadAllText($scriptFile.FullName)
    if($scriptText -match '(?im)\$host\s*='){throw "$Tag reserved automatic variable assignment found in $($scriptFile.Name): `$Host"}
    if($scriptText.Contains($cStyleQuoteEscape)){throw "$Tag C-style escaped quote found in PowerShell source: $($scriptFile.Name)"}

    $astTokens=$null
    $astErrors=$null
    $ast=[System.Management.Automation.Language.Parser]::ParseFile($scriptFile.FullName,[ref]$astTokens,[ref]$astErrors)
    if(@($astErrors).Count -ne 0){throw "$Tag AST command-policy parse failed for $($scriptFile.Name)"}
    $commandNodes=@($ast.FindAll({param($node) $node -is [System.Management.Automation.Language.CommandAst]},$true))
    foreach($commandNode in $commandNodes){
        $commandName=$commandNode.GetCommandName()
        if([string]::IsNullOrWhiteSpace($commandName)){continue}
        $commandNameLower=$commandName.ToLowerInvariant()
        if($commandNameLower -in @('invoke-webrequest','invoke-restmethod','start-bitstransfer','curl','curl.exe','wget','wget.exe')){
            throw "$Tag package script contains direct network downloader command: $($scriptFile.Name) command=$commandName"
        }
        if($commandNameLower -eq 'git' -or $commandNameLower -eq 'git.exe'){
            $gitCommandText=$commandNode.Extent.Text.ToLowerInvariant()
            if($gitCommandText -match '^\s*(?:&\s*)?git(?:\.exe)?\s+(clone|fetch|pull|checkout|reset|clean|rebase|switch)\b'){
                throw "$Tag forbidden Git mutation command in $($scriptFile.Name): $($commandNode.Extent.Text)"
            }
        }
    }
}


$setupText=[IO.File]::ReadAllText((Join-Path $root 'scripts\setup_ffmpegcore.ps1'))
if(-not $setupText.Contains("'-t:FetchFfmpegRuntime'")){throw "$Tag setup does not invoke local FetchFfmpegRuntime target directly"}
if(-not $setupText.Contains("'-p:RuntimeIdentifier=win-x64'")){throw "$Tag setup does not pin RuntimeIdentifier=win-x64"}
if($setupText -match '(?im)^\s*(?:&\s*)?(?:git|git\.exe)\s+'){throw "$Tag setup contains a Git command"}


# V75.0.4.9 regression guard: PowerShell StrictMode must handle a single backup file.
$applyBuildText=[IO.File]::ReadAllText((Join-Path $root 'scripts\apply_build.ps1'))
$scalarSafe="if(@(Get-ChildItem `$stage -Recurse -File).Count -gt 0)"
if(-not $applyBuildText.Contains($scalarSafe)){throw "$Tag scalar-safe backup enumeration guard missing in apply_build.ps1"}
$singleFileProbe=@([pscustomobject]@{Name='one'})
if($singleFileProbe.Count -ne 1){throw "$Tag scalar-safe Count selftest failed"}

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
$temp=Join-Path $env:TEMP ("SharpEmu_V750410_HostSelfTest_"+[Guid]::NewGuid().ToString('N')+'.cs')
try{
    Copy-Item -LiteralPath $reference -Destination $temp -Force
    $firstFf=Invoke-HostFfmpegTransform -Path $temp -Apply
    $firstExclusive=Invoke-FfmpegExclusiveRouteTransformV75048 -Path $temp -Apply
    $firstFresh=Invoke-PostStudiosFreshFrameHandoffV75049 -Path $temp -Apply
    $post=[IO.File]::ReadAllText($temp)
    foreach($marker in @(
        'SHARPEMU_BINK_FFMPEG_INPROCESS_HOST_V75_0_4_5',
        'SHARPEMU_BINK_FFMPEG_EXCLUSIVE_ROUTE_V75_0_4_8',
        'SHARPEMU_BINK_FFMPEG_RESOLVE_GUARD_V75_0_4_8',
        'SHARPEMU_BINK_FFMPEG_ATTACH_GUARD_V75_0_4_8',
        'SHARPEMU_BINK_FFMPEG_BLOCK_EXTERNAL_RAD_V75_0_4_8',
        'SHARPEMU_BINK_FFMPEG_BLOCK_NIHAV_V75_0_4_8',
        'SHARPEMU_BINK_FFMPEG_POST_STUDIOS_FRESH_HANDOFF_V75_0_4_9',
        'SHARPEMU_BINK_FFMPEG_POST_STUDIOS_CLOSE_HANDOFF_V75_0_4_9'))
    {
        if(-not $post.Contains($marker)){throw "$Tag structural selftest marker missing: $marker"}
    }
    if($firstFf.Changed -lt 3){throw "$Tag FFmpeg structural selftest changed too few regions: $($firstFf.Changed)"}
    if($firstExclusive.Changed -lt 5){throw "$Tag exclusive-route selftest changed too few regions: $($firstExclusive.Changed)"}
    if($firstFresh.Changed -lt 2){throw "$Tag post-Studios fresh-frame selftest changed too few regions: $($firstFresh.Changed)"}
    $secondFf=Invoke-HostFfmpegTransform -Path $temp -Apply
    $secondExclusive=Invoke-FfmpegExclusiveRouteTransformV75048 -Path $temp -Apply
    $secondFresh=Invoke-PostStudiosFreshFrameHandoffV75049 -Path $temp -Apply
    if($secondFf.Changed -ne 0 -or $secondExclusive.Changed -ne 0 -or $secondFresh.Changed -ne 0){throw "$Tag composite transform is not idempotent ffmpeg=$($secondFf.Changed) exclusive=$($secondExclusive.Changed) fresh=$($secondFresh.Changed)"}
}finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force}}


$assistReference=Join-Path $root 'reference\baseline_v75_0_4_10\BinkHostPlaybackAssist.cs'
if(-not(Test-Path -LiteralPath $assistReference -PathType Leaf)){throw "$Tag BinkHostPlaybackAssist reference missing"}
$assistTemp=Join-Path $env:TEMP ("SharpEmu_V750410_AssistSelfTest_"+[Guid]::NewGuid().ToString('N')+'.cs')
try{
    Copy-Item -LiteralPath $assistReference -Destination $assistTemp -Force
    $assistFirst=Invoke-PsStudiosGuestLiveTransformV750410 -Path $assistTemp -Apply
    if($assistFirst.Changed -ne 2){throw "$Tag ps_studios guest-live selftest expected two changes, got $($assistFirst.Changed)"}
    $assistPost=[IO.File]::ReadAllText($assistTemp)
    foreach($needle in @('SHARPEMU_BINK_FFMPEG_PS_STUDIOS_GUEST_LIVE_V75_0_4_10','_ffmpegPsStudiosGuestLiveV750410','"ps_studios_logo.bk2"','"native-rad"')){if(-not $assistPost.Contains($needle)){throw "$Tag ps_studios guest-live selftest missing: $needle"}}
    $assistSecond=Invoke-PsStudiosGuestLiveTransformV750410 -Path $assistTemp -Apply
    if($assistSecond.Changed -ne 0){throw "$Tag ps_studios guest-live transform is not idempotent"}
}finally{if(Test-Path -LiteralPath $assistTemp){Remove-Item -LiteralPath $assistTemp -Force}}
Write-Host "$Tag VALIDATION PASSED files=$($manifestLines.Count) ps51_parser=True ast_command_guard=True reserved_host_guard=True cstyle_quote_guard=True ffmpeg_selftest=True exclusive_route_selftest=True post_studios_fresh_selftest=True ps_studios_guest_live_selftest=True scalar_count_guard=True idempotent=True machine=AMD64 git_mutation=False direct_downloader=False fetch_target=True ui_binks=ffmpeg post_studios_handoff=fresh-guest-frame ps_studios_guest_execution=live external_rad_normal_route=False nihav_normal_route=False"
