$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$PackageRoot = Split-Path -Parent $PSScriptRoot
$PackageTag = 'V76.0.13.2-BINK-GUEST-AV-CLOCK-HANDOFF-STATE-VERIFY-FIX'

$BinkRel = 'src\SharpEmu.Libs\Media\BinkGuestOwnedRuntimeV7600.cs'
$PresenterRel = 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$YuvHelperRel = 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.BinkGuestYuvV7612.cs'
$YuvHelperExpectedHashV7612 = 'cb264d09b0bb665e1bad0cf54d0d74efab14b92205871e0c671c447c81d9b0b0'
$AvHelperRel = 'src\SharpEmu.Libs\Media\BinkGuestAvClockV7613.cs'
$AvHelperPayloadRel = 'payload\src\SharpEmu.Libs\Media\BinkGuestAvClockV7613.cs'
$AvHelperExpectedHashV7613 = '07dfdacd9c6f5855275318a161db4968f56b06e4336e62d6c594fdcc4673585f'

function Get-RepoRoot([string]$Preferred) {
    if(Test-Path -LiteralPath (Join-Path $Preferred 'src\SharpEmu.CLI\SharpEmu.CLI.csproj')){
        return (Resolve-Path -LiteralPath $Preferred).Path
    }
    throw "RepositoryRoot invalido: $Preferred"
}
function Get-PatchesRoot([string]$Preferred) {
    if(-not(Test-Path -LiteralPath $Preferred)){
        New-Item -ItemType Directory -Path $Preferred -Force | Out-Null
    }
    return (Resolve-Path -LiteralPath $Preferred).Path
}
function Get-Sha256([string]$Path) {
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){ return '' }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Read-Text([string]$Path) { return [System.IO.File]::ReadAllText($Path) }
function Write-Text([string]$Path,[string]$Text) {
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path,$Text,$utf8)
}
function Get-NewLine([string]$Text) {
    if($Text.Contains("`r`n")){ return "`r`n" }
    return "`n"
}
function Get-OccurrenceCount([string]$Text,[string]$Needle) {
    if([string]::IsNullOrEmpty($Needle)){ return 0 }
    $count=0; $start=0
    while($start -le $Text.Length-$Needle.Length){
        $idx=$Text.IndexOf($Needle,$start,[System.StringComparison]::Ordinal)
        if($idx -lt 0){ break }
        $count++; $start=$idx+$Needle.Length
    }
    return $count
}
function Insert-AfterLineOnce([string]$Text,[string]$Line,[string[]]$Lines,[string]$Label) {
    $count=Get-OccurrenceCount $Text $Line
    if($count -ne 1){ throw "Anchor invalida para $Label occurrences=$count" }
    $nl=Get-NewLine $Text
    return $Text.Replace($Line,$Line+$nl+($Lines -join $nl))
}
function Insert-BeforeLineOnce([string]$Text,[string]$Line,[string[]]$Lines,[string]$Label) {
    $count=Get-OccurrenceCount $Text $Line
    if($count -ne 1){ throw "Anchor invalida para $Label occurrences=$count" }
    $nl=Get-NewLine $Text
    return $Text.Replace($Line,($Lines -join $nl)+$nl+$Line)
}

function Assert-V7612Baseline([string]$RepoRoot) {
    foreach($rel in @($BinkRel,$PresenterRel,$YuvHelperRel)){
        if(-not(Test-Path -LiteralPath (Join-Path $RepoRoot $rel) -PathType Leaf)){
            throw "V76.0.12.3 prerequisite ausente: $rel"
        }
    }
    $yuvHash=Get-Sha256 (Join-Path $RepoRoot $YuvHelperRel)
    if($yuvHash -ne $YuvHelperExpectedHashV7612){
        throw "V76.0.12.3 YUV helper mismatch expected=$YuvHelperExpectedHashV7612 actual=$yuvHash"
    }
    $bink=Read-Text (Join-Path $RepoRoot $BinkRel)
    # V76.0.13.2: validate the V76.0.12.3 session-epoch semantics, not
    # diagnostic log wording.  V76.0.12.3 BUILD+VERIFY may preserve older
    # SESSION log labels while the ownership/epoch implementation is valid.
    foreach($contract in @(
        'private static long _sessionEpoch;',
        'internal static bool YuvSessionEpochEnabled =>',
        'internal static long ActiveSessionEpoch =>',
        '            Interlocked.Increment(ref _sessionEpoch);'
    )){
        if($bink.IndexOf($contract,[System.StringComparison]::Ordinal) -lt 0){
            throw "V76.0.12.3 Bink semantic prerequisite ausente: $contract"
        }
    }
    $presenter=Read-Text (Join-Path $RepoRoot $PresenterRel)
    foreach($contract in @(
        '!IsCurrentGuestBinkYuvProducerV7612(candidate) ||',
        '? new byte[] { 0 }',
        '!ShouldSuppressGuestBinkStorageCpuUploadV7612(texture) &&',
        'MarkGuestBinkYuvProducerV7612(texture);'
    )){
        if($presenter.IndexOf($contract,[System.StringComparison]::Ordinal) -lt 0){
            throw "V76.0.12.3 presenter prerequisite contract ausente: $contract"
        }
    }
}

function Get-AvHelperStateV7613([string]$RepoRoot) {
    $path=Join-Path $RepoRoot $AvHelperRel
    $hash=Get-Sha256 $path
    if([string]::IsNullOrWhiteSpace($hash)){ return 'ReadyCopy' }
    if($hash -eq $AvHelperExpectedHashV7613){ return 'Applied' }
    throw "V76.0.13.2 A/V helper divergente actual=$hash"
}

function Get-BinkStateV7613([string]$RepoRoot) {
    $text=Read-Text (Join-Path $RepoRoot $BinkRel)
    # V76.0.13.2: the apply emits BeginSession as a multiline call using
    # Volatile.Read(ref _sessionEpoch).  Check call semantics rather than the
    # obsolete one-line prototype that the package itself never writes.
    $markers=@(
        'BinkGuestAvClockV7613.BeginSession(',
        'BinkGuestAvClockV7613.EndSession('
    )
    $present=0
    foreach($m in $markers){if($text.IndexOf($m,[System.StringComparison]::Ordinal) -ge 0){$present++}}
    if($present -eq $markers.Count){return 'Applied'}
    if($present -ne 0){throw "V76.0.13.2 Bink runtime parcialmente aplicado markers=$present/$($markers.Count)"}
    foreach($anchor in @(
        '        var serial = Interlocked.Increment(ref _openSerial);',
        '            Volatile.Write(ref _lastActiveMoviePath, null);'
    )){
        if((Get-OccurrenceCount $text $anchor) -ne 1){
            throw "Anchor Bink V76.0.13.2 invalida: $anchor occurrences=$(Get-OccurrenceCount $text $anchor)"
        }
    }
    foreach($contract in @(
        'internal static long ActiveSessionEpoch =>',
        '            Interlocked.Increment(ref _sessionEpoch);'
    )){
        if($text.IndexOf($contract,[System.StringComparison]::Ordinal) -lt 0){
            throw "V76.0.13.2 Bink epoch semantic context ausente: $contract"
        }
    }
    return 'ReadySemanticInsert'
}

function Apply-BinkPatchV7613([string]$RepoRoot) {
    $path=Join-Path $RepoRoot $BinkRel
    $text=Read-Text $path
    if($text.IndexOf('BinkGuestAvClockV7613.BeginSession(',[System.StringComparison]::Ordinal) -lt 0){
        $text=Insert-AfterLineOnce $text '            Interlocked.Increment(ref _sessionEpoch);' @(
            '            BinkGuestAvClockV7613.BeginSession(',
            '                Volatile.Read(ref _sessionEpoch),',
            '                path);'
        ) 'bink-av-clock-session-begin'
        Write-Host '  * bink-av-clock-session-begin-v7613'
    }
    if($text.IndexOf('BinkGuestAvClockV7613.EndSession(',[System.StringComparison]::Ordinal) -lt 0){
        $text=Insert-AfterLineOnce $text '            Volatile.Write(ref _lastActiveMoviePath, null);' @(
            '            BinkGuestAvClockV7613.EndSession(',
            '                Volatile.Read(ref _sessionEpoch),',
            '                path);'
        ) 'bink-av-clock-session-end'
        Write-Host '  * bink-av-clock-session-end-v7613'
    }
    Write-Text $path $text
}

function Get-PresenterStateV7613([string]$RepoRoot) {
    $text=Read-Text (Join-Path $RepoRoot $PresenterRel)
    $markers=@(
        'public bool UsesGuestBinkYuvV7613;',
        'BinkGuestAvClockV7613.ShouldHoldFirstVisual(',
        'resources.GuestBinkProducerGenerationV7613 = Math.Max(',
        'BinkGuestAvClockV7613.NotifyPresentedFrame('
    )
    $present=0
    foreach($m in $markers){if($text.IndexOf($m,[System.StringComparison]::Ordinal) -ge 0){$present++}}
    if($present -eq $markers.Count){return 'Applied'}
    if($present -ne 0){throw "V76.0.13.2 presenter parcialmente aplicado markers=$present/$($markers.Count)"}
    foreach($anchor in @(
        '            public TextureResource[] Textures = [];',
        '                    var feedbackTarget =',
        '            if (IsFinalGuestBinkYuvPlaneV7602(texture))',
        '            CheckSwapchainResult(presentResult, "vkQueuePresentKHR");'
    )){
        if((Get-OccurrenceCount $text $anchor) -ne 1){
            throw "Anchor presenter V76.0.13.2 invalida: $anchor occurrences=$(Get-OccurrenceCount $text $anchor)"
        }
    }
    $nl=Get-NewLine $text
    $exactPrefix=@(
        '                if (TryResolveExactGuestBinkYuvProducerV7602(',
        '                        texture,',
        '                        vkFormat,',
        '                        out var binkYuvProducerV7602) &&',
        '                    TryGetOrCreateGuestImageView('
    ) -join $nl
    if((Get-OccurrenceCount $text $exactPrefix) -ne 1){
        throw "Anchor exact YUV producer V76.0.13.2 invalida occurrences=$(Get-OccurrenceCount $text $exactPrefix)"
    }
    return 'ReadySemanticInsert'
}

function Apply-PresenterPatchV7613([string]$RepoRoot) {
    $path=Join-Path $RepoRoot $PresenterRel
    $text=Read-Text $path
    $nl=Get-NewLine $text

    if($text.IndexOf('public bool UsesGuestBinkYuvV7613;',[System.StringComparison]::Ordinal) -lt 0){
        $text=Insert-AfterLineOnce $text '            public TextureResource[] Textures = [];' @(
            '            // V76.0.13: presentation-side A/V telemetry only for draws that',
            '            // actually bound a current-session guest Bink Y/UV producer.',
            '            public bool UsesGuestBinkYuvV7613;',
            '            public long GuestBinkEpochV7613;',
            '            public long GuestBinkProducerGenerationV7613;'
        ) 'bink-av-resource-fields'
        Write-Host '  * bink-av-resource-fields-v7613'
    }

    if($text.IndexOf('resources.GuestBinkProducerGenerationV7613 = Math.Max(',[System.StringComparison]::Ordinal) -lt 0){
        $text=Insert-BeforeLineOnce $text '                    var feedbackTarget =' @(
            '                    if (IsFinalGuestBinkYuvPlaneV7602(texture) &&',
            '                        resolved.Address == texture.Address &&',
            '                        resolved.GuestImage is { } guestBinkImageV7613)',
            '                    {',
            '                        resources.UsesGuestBinkYuvV7613 = true;',
            '                        resources.GuestBinkEpochV7613 =',
            '                            BinkGuestOwnedRuntimeV7600.ActiveSessionEpoch;',
            '                        resources.GuestBinkProducerGenerationV7613 = Math.Max(',
            '                            resources.GuestBinkProducerGenerationV7613,',
            '                            guestBinkImageV7613.ContentGeneration);',
            '                    }',
            ''
        ) 'bink-av-resource-stamp'
        Write-Host '  * bink-av-resource-stamp-v7613'
    }

    if($text.IndexOf('BinkGuestAvClockV7613.ShouldHoldFirstVisual(',[System.StringComparison]::Ordinal) -lt 0){
        $old=@(
            '                if (TryResolveExactGuestBinkYuvProducerV7602(',
            '                        texture,',
            '                        vkFormat,',
            '                        out var binkYuvProducerV7602) &&',
            '                    TryGetOrCreateGuestImageView('
        ) -join $nl
        $new=@(
            '                var binkYuvHandoffHeldV7613 = false;',
            '                if (TryResolveExactGuestBinkYuvProducerV7602(',
            '                        texture,',
            '                        vkFormat,',
            '                        out var binkYuvProducerV7602))',
            '                {',
            '                    binkYuvHandoffHeldV7613 =',
            '                        BinkGuestAvClockV7613.ShouldHoldFirstVisual(',
            '                            BinkGuestOwnedRuntimeV7600.ActiveSessionEpoch);',
            '                }',
            '',
            '                if (!binkYuvHandoffHeldV7613 &&',
            '                    binkYuvProducerV7602 is not null &&',
            '                    TryGetOrCreateGuestImageView('
        ) -join $nl
        if((Get-OccurrenceCount $text $old) -ne 1){throw 'Exact YUV handoff anchor ausente/ambiguo.'}
        $text=$text.Replace($old,$new)
        $oldReason='                        "action=neutral-nonaddressed reason=storage-producer-not-ready");'
        if((Get-OccurrenceCount $text $oldReason) -ne 1){throw 'YUV wait reason anchor ausente/ambiguo.'}
        $reasonLines=@(
            '                        "action=neutral-nonaddressed reason=" +',
            '                        (binkYuvHandoffHeldV7613',
            '                            ? "av-first-frame-handoff"',
            '                            : "storage-producer-not-ready"));'
        ) -join $nl
        $text=$text.Replace($oldReason,$reasonLines)
        Write-Host '  * bink-first-visual-audio-handoff-v7613'
    }

    if($text.IndexOf('BinkGuestAvClockV7613.NotifyPresentedFrame(',[System.StringComparison]::Ordinal) -lt 0){
        $text=Insert-AfterLineOnce $text '            CheckSwapchainResult(presentResult, "vkQueuePresentKHR");' @(
            '            if (translatedResources is { UsesGuestBinkYuvV7613: true })',
            '            {',
            '                BinkGuestAvClockV7613.NotifyPresentedFrame(',
            '                    translatedResources.GuestBinkEpochV7613,',
            '                    translatedResources.GuestBinkProducerGenerationV7613);',
            '            }'
        ) 'bink-av-present-notify'
        Write-Host '  * bink-av-present-notify-v7613'
    }

    Write-Text $path $text
}

function Assert-V7613Installed([string]$RepoRoot) {
    Assert-V7612Baseline $RepoRoot
    if((Get-AvHelperStateV7613 $RepoRoot) -ne 'Applied'){throw 'V76.0.13.2 A/V helper incompleto.'}
    if((Get-BinkStateV7613 $RepoRoot) -ne 'Applied'){throw 'V76.0.13.2 Bink runtime incompleto.'}
    if((Get-PresenterStateV7613 $RepoRoot) -ne 'Applied'){throw 'V76.0.13.2 presenter incompleto.'}
}
