Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$script:Tag='[V74.0.118.7.6.3.13-DS-RAD-NIHAV-HYBRID]'
$script:Version='V74.0.118.7.6.3.13'
$script:KnownHostMovieBridgeSha='D3BC791213F1815C5C3E2B2713E90590C507C685DA4C95E308E4E72A4923B91B'
$script:PackageRoot=Split-Path -Parent $PSScriptRoot

$script:RelativeHostMovieBridge='src\SharpEmu.Libs\Media\HostMovieBridge.cs'
$script:RelativePresenter='src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$script:RelativeAgc='src\SharpEmu.Libs\Agc\AgcExports.cs'
$script:RelativeNativeWorker='src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.NativeWorker.cs'
$script:RelativeNihav='src\SharpEmu.Libs\Media\NihavBink2Decoder.cs'
$script:RelativePlayback='src\SharpEmu.Libs\Media\MediaFramePlayback.cs'

function Write-Tag([string]$Message) {
    Write-Host "$script:Tag $Message"
}

function Get-PatchesRoot {
    Split-Path -Parent $script:PackageRoot
}

function Get-RepositoryRoot {
    $repo=Split-Path -Parent (Get-PatchesRoot)
    if(-not(Test-Path -LiteralPath (Join-Path $repo 'src'))) {
        throw "$script:Tag repository root not found: $repo"
    }
    $repo
}

function Get-StatePath {
    Join-Path (Get-PatchesRoot) 'SharpEmu_V74_0_118_7_6_3_13_INSTALL_STATE.json'
}

function Get-BackupPointer {
    Join-Path (Get-PatchesRoot) 'SharpEmu_V74_0_118_7_6_3_13_LAST_BACKUP.txt'
}

function Get-Sha([string]$Path) {
    if(-not(Test-Path -LiteralPath $Path)) { return '' }
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()
}

function Normalize-Lf([string]$Text) {
    if($null -eq $Text) { return '' }
    $Text.Replace("`r`n","`n").Replace("`r","`n")
}

function Get-TextStyle([string]$Path) {
    $bytes=[IO.File]::ReadAllBytes($Path)
    $hasBom=
        $bytes.Length -ge 3 -and
        $bytes[0] -eq 0xEF -and
        $bytes[1] -eq 0xBB -and
        $bytes[2] -eq 0xBF
    $raw=[IO.File]::ReadAllText($Path)
    [pscustomobject]@{
        Raw=$raw
        UseCrlf=$raw.Contains("`r`n")
        UseBom=$hasBom
    }
}

function Write-SourceText(
    [string]$Path,
    [string]$Text,
    [bool]$UseCrlf,
    [bool]$UseBom)
{
    $value=Normalize-Lf $Text
    if($UseCrlf) {
        $value=$value.Replace("`n","`r`n")
    }
    $encoding=New-Object System.Text.UTF8Encoding($UseBom)
    [IO.File]::WriteAllText($Path,$value,$encoding)
}

function Get-OldHunk {
    Normalize-Lf(
        [IO.File]::ReadAllText(
            (Join-Path $script:PackageRoot
                'transforms\host_movie_bridge\h01.old.txt')))
}

function Get-NewHunk {
    Normalize-Lf(
        [IO.File]::ReadAllText(
            (Join-Path $script:PackageRoot
                'transforms\host_movie_bridge\h01.new.txt')))
}

function Get-HunkState([string]$Text) {
    $old=Get-OldHunk
    $new=Get-NewHunk
    $oldCount=([regex]::Matches($Text,[regex]::Escape($old))).Count
    $newCount=([regex]::Matches($Text,[regex]::Escape($new))).Count
    $state='invalid'
    if($oldCount -eq 1 -and $newCount -eq 0) { $state='original' }
    elseif($oldCount -eq 0 -and $newCount -eq 1) { $state='patched' }
    [pscustomobject]@{
        State=$state
        OldCount=$oldCount
        NewCount=$newCount
    }
}

function Invoke-HybridTransform(
    [string]$Source,
    [string]$Destination)
{
    $style=Get-TextStyle $Source
    $text=Normalize-Lf $style.Raw
    $shape=Get-HunkState $text

    if($shape.State -eq 'invalid') {
        throw "$script:Tag unsupported HostMovieBridge shape old=$($shape.OldCount) new=$($shape.NewCount); nothing changed"
    }

    if($shape.State -eq 'patched') {
        Write-SourceText $Destination $text $style.UseCrlf $style.UseBom
        return [pscustomobject]@{
            Status='already'
            Before=(Get-Sha $Source)
            After=(Get-Sha $Destination)
        }
    }

    $old=Get-OldHunk
    $new=Get-NewHunk
    $index=$text.IndexOf($old,[StringComparison]::Ordinal)
    if($index -lt 0) {
        throw "$script:Tag HostMovieBridge old hunk index not found"
    }
    $patched=$text.Remove($index,$old.Length).Insert($index,$new)

    $post=Get-HunkState $patched
    if($post.State -ne 'patched') {
        throw "$script:Tag HostMovieBridge transform postcondition failed old=$($post.OldCount) new=$($post.NewCount)"
    }

    Write-SourceText $Destination $patched $style.UseCrlf $style.UseBom
    [pscustomobject]@{
        Status='applied'
        Before=(Get-Sha $Source)
        After=(Get-Sha $Destination)
    }
}

function Get-PerfPaths {
    $repo=Get-RepositoryRoot
    [ordered]@{
        NativeWorker=(Join-Path $repo $script:RelativeNativeWorker)
        Presenter=(Join-Path $repo $script:RelativePresenter)
        Agc=(Join-Path $repo $script:RelativeAgc)
        Nihav=(Join-Path $repo $script:RelativeNihav)
        Playback=(Join-Path $repo $script:RelativePlayback)
    }
}

function Assert-PerfMarkers {
    $paths=Get-PerfPaths
    $requirements=[ordered]@{
        NativeWorker=@(
            'SHARPEMU_V74_0_3_4_NO_MANAGED_INLINE_FALLBACK',
            '[V73.20.4.1][DEDICATED]',
            'SHARPEMU_V74_0_10_RENDERER_RESOURCE_NATIVE_LANE',
            '[V74.0.10][NATIVE_LANE]')
        Presenter=@(
            'SHARPEMU_V74_0_56_16_ADAPTIVE_UNIFIED_COMPUTE',
            'SHARPEMU_V74_0_68_DEFERRED_IDLE_BACKOFF',
            'SHARPEMU_V74_0_105_UI_BINK_DIRECT_YUV')
        Agc=@(
            'SHARPEMU_V74_0_71_DEDICATED_WAIT_DRAIN',
            'SHARPEMU_V74_0_72_AGC_GATE_OWNER_WAIT_DRAIN')
        Nihav=@(
            '[V74.0.100.1][TITLE_LOOP_RESERVOIR]',
            'SHARPEMU_V74_0_105_UI_BINK_DIRECT_YUV',
            'SHARPEMU_V74_0_109_DIRECT_YUV_CHROMA_REPAIR',
            'SHARPEMU_V74_0_110_DIRECT_YUV_REFERENCE_COLOR')
        Playback=@(
            'SHARPEMU_V74_0_109_UI_BINK_REALTIME_RESERVOIR')
    }

    foreach($key in $requirements.Keys) {
        $path=$paths[$key]
        if(-not(Test-Path -LiteralPath $path)) {
            throw "$script:Tag performance source missing: $key path=$path"
        }
        $text=[IO.File]::ReadAllText($path)
        foreach($marker in $requirements[$key]) {
            if(-not$text.Contains($marker)) {
                throw "$script:Tag performance prerequisite missing: $key marker=$marker"
            }
        }
        Write-Tag "PerfMarkerGuard=$key PASS sha=$(Get-Sha $path)"
    }
}

function Get-PerfSnapshot {
    $paths=Get-PerfPaths
    $snapshot=[ordered]@{}
    foreach($key in $paths.Keys) {
        $snapshot[$key]=Get-Sha $paths[$key]
    }
    $snapshot
}

function Assert-PerfSnapshotUnchanged($Before) {
    $after=Get-PerfSnapshot
    foreach($key in $Before.Keys) {
        if([string]$Before[$key] -ne [string]$after[$key]) {
            throw "$script:Tag PERFORMANCE SOURCE CHANGED unexpectedly: $key before=$($Before[$key]) after=$($after[$key])"
        }
    }
    Write-Tag 'PerformanceSourceHashGuard=PASS all guarded performance files unchanged'
}

function Get-LatestDotnetSdkRoot {
    $rows=@(& dotnet --list-sdks 2>$null)
    if($LASTEXITCODE -ne 0 -or $rows.Count -eq 0) {
        throw "$script:Tag dotnet --list-sdks failed"
    }
    $parsed=@()
    foreach($row in $rows) {
        if($row -match '^\s*([0-9][^\s]*)\s+\[(.+)\]\s*$') {
            $parsed += [pscustomobject]@{
                Version=$matches[1]
                Base=$matches[2]
            }
        }
    }
    $selected=$parsed |
        Sort-Object {
            try { [version]($_.Version.Split('-')[0]) }
            catch { [version]'0.0' }
        } -Descending |
        Select-Object -First 1
    if($null -eq $selected) {
        throw "$script:Tag could not resolve .NET SDK"
    }
    Join-Path $selected.Base $selected.Version
}

function Invoke-SyntaxProbe([string]$Path,[string]$Label) {
    $sdk=Get-LatestDotnetSdkRoot
    $csc=Join-Path $sdk 'Roslyn\bincore\csc.dll'
    if(-not(Test-Path -LiteralPath $csc)) {
        throw "$script:Tag csc.dll missing: $csc"
    }
    $dotnet=(Get-Command dotnet -CommandType Application -ErrorAction Stop).Source
    $output=@(
        & $dotnet $csc /nologo /noconfig /nostdlib /target:library /langversion:preview $Path 2>&1 |
        ForEach-Object { $_ | Out-String }
    )
    $syntaxIds=@(
        'CS1002','CS1003','CS1009','CS1010','CS1011','CS1012',
        'CS1022','CS1024','CS1031','CS1039','CS1040',
        'CS1513','CS1514','CS1519','CS1525','CS1733',
        'CS8076','CS8086','CS8124','CS8803')
    $syntax=[string[]]@()
    foreach($line in $output) {
        foreach($id in $syntaxIds) {
            if($line -match ("\berror\s+"+[regex]::Escape($id)+"\b")) {
                $syntax += $line.Trim()
                break
            }
        }
    }
    if($syntax.Count -ne 0) {
        throw "$script:Tag C# syntax failed ($Label): $($syntax -join ' | ')"
    }
    Write-Tag "SyntaxProbe=$Label PASSED sdk=$sdk"
}

function Assert-CurrentMediaStructure {
    $repo=Get-RepositoryRoot
    $hostMovieBridge=Join-Path $repo $script:RelativeHostMovieBridge
    if(-not(Test-Path -LiteralPath $hostMovieBridge)) {
        throw "$script:Tag HostMovieBridge missing: $hostMovieBridge"
    }

    $sha=Get-Sha $hostMovieBridge
    $text=Normalize-Lf([IO.File]::ReadAllText($hostMovieBridge))
    $shape=Get-HunkState $text

    Write-Tag "CurrentHostMovieBridgeSHA=$sha"
    Write-Tag "KnownObservedHostMovieBridgeSHA=$script:KnownHostMovieBridgeSha"
    Write-Tag "HybridHunkState=$($shape.State) old=$($shape.OldCount) new=$($shape.NewCount)"

    foreach($marker in @(
        'SHARPEMU_V74_0_79_INTERNAL_TITLE_MENU_LOOP',
        'SHARPEMU_V74_0_82_TITLE_LOOP_NO_HOST_AUDIO_PROBE',
        'SHARPEMU_V74_0_84_1_DEMONS_UI_BINK_INTERNAL_COMPOSITOR',
        'IsDemonSoulsUiBinkCompositePathV740841')) {
        if(-not$text.Contains($marker)) {
            throw "$script:Tag historical NIHAV/UI prerequisite missing: $marker"
        }
    }

    if($shape.State -eq 'invalid') {
        throw "$script:Tag HostMovieBridge is not structurally compatible with this SAFE restore"
    }

    if($sha -eq $script:KnownHostMovieBridgeSha) {
        Write-Tag 'HostMovieBridgeCompatibility=exact-observed-current'
    } else {
        Write-Tag 'HostMovieBridgeCompatibility=structural-compatible hash-drift-accepted'
    }

    [pscustomobject]@{
        Path=$hostMovieBridge
        Sha=$sha
        State=$shape.State
    }
}

function Resolve-RadVideo64 {
    $configured=
        [Environment]::GetEnvironmentVariable(
            'SHARPEMU_RADVIDEO64',
            'Process')
    if($configured -and(Test-Path -LiteralPath $configured)) {
        return (Resolve-Path -LiteralPath $configured).Path
    }

    $candidate=
        Join-Path ${env:ProgramFiles(x86)} 'RADVideo\radvideo64.exe'
    if(Test-Path -LiteralPath $candidate) {
        return (Resolve-Path -LiteralPath $candidate).Path
    }
    $null
}

function Set-TestEnvironment {
    $rad=Resolve-RadVideo64
    if($null -eq $rad) {
        throw "$script:Tag RADVideo64 not found"
    }

    $env:SHARPEMU_RADVIDEO64=$rad
    $env:SHARPEMU_BINK_MODE='rad'
    $env:SHARPEMU_BINK_NATIVE_PREFER='0'

    # Restore the older hybrid ownership explicitly.
    $env:SHARPEMU_DS_UI_BINK_RAD_INTERACTIVE='0'
    $env:SHARPEMU_DS_UI_BINK_INTERNAL='1'

    # Keep the later direct-YUV/decoder performance path available.
    $env:SHARPEMU_DS_UI_BINK_DIRECT_YUV='1'

    # Keep all later RAD main-menu capture/composite experiments dormant.
    $env:SHARPEMU_DS_RAD_MAIN_MENU_CAPTURE_COMPOSITE='0'
    $env:SHARPEMU_DS_RAD_MAIN_MENU_CAPTURE_EXPERIMENTAL='0'

    $env:SHARPEMU_LOG_AUDIO_OUT2='1'
    $env:SHARPEMU_LOG_AMPR_READS='1'

    Write-Tag (
        "RAD=$rad ownership=rad-one-shots+nihav-ui " +
        "ui_rad_interactive=0 ui_internal=1 direct_yuv=1")
}
