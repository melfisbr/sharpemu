$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$PackageRoot = Split-Path -Parent $PSScriptRoot
$PackageTag = 'V76.0.12.1-BINK-GUEST-YUV-STORAGE-EPOCH-BUILDFIX'

$BinkRel = 'src\SharpEmu.Libs\Media\BinkGuestOwnedRuntimeV7600.cs'
$PresenterRel = 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$HelperRel = 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.BinkGuestYuvV7612.cs'
$HelperPayloadRel = 'payload\src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.BinkGuestYuvV7612.cs'
$HelperExpectedHashV7612 = '39907322573f631d4dbe8cea86810407f8b3c0f3f4cd3ae88ddb1af573dff973'

$CacheRel = 'src\SharpEmu.Libs\Gpu\Vulkan\VulkanShaderBinaryCacheV7605.cs'
$CacheV7611Hash = '09b7daedf5eab60c1979012d6cf125c9a607623e8df5072f6d487c9907ccbbd3'
$ParallelRel = 'src\SharpEmu.Libs\Agc\AgcExports.ShaderParallelV7611.cs'
$ParallelV7611Hash = 'e9b28628eb48c7c84bc61f216ac47721d98bc8e6b746afbed965d9708cc88255'
$AgcRel = 'src\SharpEmu.Libs\Agc\AgcExports.cs'

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
function Read-Text([string]$Path) {
    return [System.IO.File]::ReadAllText($Path)
}
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
    if((Get-OccurrenceCount $Text $Line) -ne 1){
        throw "Anchor invalida para $Label occurrences=$(Get-OccurrenceCount $Text $Line)"
    }
    $nl=Get-NewLine $Text
    $replacement=$Line+$nl+($Lines -join $nl)
    return $Text.Replace($Line,$replacement)
}
function Insert-BeforeLineOnce([string]$Text,[string]$Line,[string[]]$Lines,[string]$Label) {
    if((Get-OccurrenceCount $Text $Line) -ne 1){
        throw "Anchor invalida para $Label occurrences=$(Get-OccurrenceCount $Text $Line)"
    }
    $nl=Get-NewLine $Text
    $replacement=($Lines -join $nl)+$nl+$Line
    return $Text.Replace($Line,$replacement)
}

function Assert-V7611Baseline([string]$RepoRoot) {
    $cache=Get-Sha256 (Join-Path $RepoRoot $CacheRel)
    if($cache -ne $CacheV7611Hash){
        throw "V76.0.11.1 shader-cache prerequisite mismatch expected=$CacheV7611Hash actual=$cache"
    }
    $parallel=Get-Sha256 (Join-Path $RepoRoot $ParallelRel)
    if($parallel -ne $ParallelV7611Hash){
        throw "V76.0.11.1 parallel helper prerequisite mismatch expected=$ParallelV7611Hash actual=$parallel"
    }
    $agc=Read-Text (Join-Path $RepoRoot $AgcRel)
    if((Get-OccurrenceCount $agc 'TryCompileGraphicsShaderPairV7611(') -ne 1){
        throw 'V76.0.11.1 AGC parallel call prerequisite ausente/duplicado.'
    }
    foreach($rel in @($BinkRel,$PresenterRel)){
        if(-not(Test-Path -LiteralPath (Join-Path $RepoRoot $rel) -PathType Leaf)){
            throw "Source prerequisite ausente: $rel"
        }
    }
}

function Get-BinkStateV7612([string]$RepoRoot) {
    $text=Read-Text (Join-Path $RepoRoot $BinkRel)
    $markers=@(
        'private static long _sessionEpoch;',
        'internal static bool YuvSessionEpochEnabled =>',
        'internal static long ActiveSessionEpoch =>',
        'Interlocked.Increment(ref _sessionEpoch);'
    )
    $present=0
    foreach($m in $markers){ if($text.IndexOf($m,[System.StringComparison]::Ordinal) -ge 0){$present++} }
    if($present -eq $markers.Count){ return 'Applied' }
    if($present -ne 0){ throw "Bink V76.0.12.1 parcialmente aplicado markers=$present/$($markers.Count)" }

    foreach($anchor in @(
        '    private static long _closeSerial;',
        '    internal static int ActiveGuestMovieCount => OpenGuestMovieFds.Count;',
        '        Volatile.Write(ref _lastActiveMoviePath, path);'
    )){
        if((Get-OccurrenceCount $text $anchor) -ne 1){
            throw "Anchor Bink V76.0.12.1 invalida: $anchor occurrences=$(Get-OccurrenceCount $text $anchor)"
        }
    }
    return 'ReadySemanticInsert'
}

function Apply-BinkPatchV7612([string]$RepoRoot) {
    $path=Join-Path $RepoRoot $BinkRel
    $text=Read-Text $path
    if($text.IndexOf('internal static bool YuvSessionEpochEnabled =>',[System.StringComparison]::Ordinal) -ge 0){
        Write-Host '  = bink-session-epoch-v7612 already'
        return
    }
    $text=Insert-AfterLineOnce $text '    private static long _closeSerial;' @(
        '    private static long _sessionEpoch;'
    ) 'bink-session-epoch-field'
    $text=Insert-BeforeLineOnce $text '    internal static int ActiveGuestMovieCount => OpenGuestMovieFds.Count;' @(
        '    // V76.0.12: final guest Y/UV producers are scoped to one movie session.',
        '    internal static bool YuvSessionEpochEnabled =>',
        '        ExactYuvProducerEnabled &&',
        '        !string.Equals(',
        '            Environment.GetEnvironmentVariable(',
        '                "SHARPEMU_BINK_YUV_SESSION_EPOCH"),',
        '            "0",',
        '            StringComparison.Ordinal);',
        '',
        '    internal static long ActiveSessionEpoch =>',
        '        IsGuestMovieActive ? Volatile.Read(ref _sessionEpoch) : 0;',
        ''
    ) 'bink-session-epoch-properties'
    $text=Insert-AfterLineOnce $text '        Volatile.Write(ref _lastActiveMoviePath, path);' @(
        '        if (OpenGuestMovieFds.Count == 1)',
        '        {',
        '            Interlocked.Increment(ref _sessionEpoch);',
        '        }'
    ) 'bink-session-epoch-begin'
    Write-Text $path $text
    Write-Host '  * bink-session-epoch-v7612'
}

function Get-PresenterStateV7612([string]$RepoRoot) {
    $text=Read-Text (Join-Path $RepoRoot $PresenterRel)
    $checks=@(
        '!IsCurrentGuestBinkYuvProducerV7612(candidate) ||',
        '? new byte[] { 0 }',
        '!ShouldSuppressGuestBinkStorageCpuUploadV7612(texture) &&',
        'MarkGuestBinkYuvProducerV7612(texture);'
    )
    $present=0
    foreach($m in $checks){if($text.IndexOf($m,[System.StringComparison]::Ordinal) -ge 0){$present++}}
    if($present -eq $checks.Count){return 'Applied'}
    if($present -ne 0){throw "Presenter V76.0.12.1 parcialmente aplicado markers=$present/$($checks.Count)"}

    foreach($anchor in @(
        '                if (!candidate.Initialized ||',
        '                ? new byte[] { 16 }',
        '            if (!guestImage.Initialized &&',
        '                    // Once the real Bink storage producer has written this'
    )){
        if((Get-OccurrenceCount $text $anchor) -ne 1){
            throw "Anchor presenter V76.0.12.1 invalida: $anchor occurrences=$(Get-OccurrenceCount $text $anchor)"
        }
    }
    return 'ReadySemanticInsert'
}

function Apply-PresenterPatchV7612([string]$RepoRoot) {
    $path=Join-Path $RepoRoot $PresenterRel
    $text=Read-Text $path
    if($text.IndexOf('!IsCurrentGuestBinkYuvProducerV7612(candidate) ||',[System.StringComparison]::Ordinal) -lt 0){
        $text=Insert-AfterLineOnce $text '                if (!candidate.Initialized ||' @(
            '                    !IsCurrentGuestBinkYuvProducerV7612(candidate) ||'
        ) 'bink-yuv-exact-producer-epoch-guard'
        Write-Host '  * bink-yuv-exact-producer-epoch-guard'
    }
    if($text.IndexOf('? new byte[] { 0 }',[System.StringComparison]::Ordinal) -lt 0){
        if((Get-OccurrenceCount $text '                ? new byte[] { 16 }') -ne 1){
            throw 'Neutral Y=16 anchor ausente/ambiguo.'
        }
        $text=$text.Replace('                ? new byte[] { 16 }','                ? new byte[] { 0 }')
        Write-Host '  * bink-yuv-full-range-neutral-black'
    }
    if($text.IndexOf('!ShouldSuppressGuestBinkStorageCpuUploadV7612(texture) &&',[System.StringComparison]::Ordinal) -lt 0){
        $text=Insert-BeforeLineOnce $text '            if (!guestImage.Initialized &&' @(
            '            if (!ShouldSuppressGuestBinkStorageCpuUploadV7612(texture) &&'
        ) 'bink-yuv-storage-cpu-upload-suppress'
        # The insertion creates a nested "if" token; fold it into one condition.
        $nl=Get-NewLine $text
        $text=$text.Replace(
            '            if (!ShouldSuppressGuestBinkStorageCpuUploadV7612(texture) &&'+$nl+
            '            if (!guestImage.Initialized &&',
            '            if (!ShouldSuppressGuestBinkStorageCpuUploadV7612(texture) &&'+$nl+
            '                !guestImage.Initialized &&')
        Write-Host '  * bink-yuv-storage-cpu-upload-suppress'
    }
    if($text.IndexOf('MarkGuestBinkYuvProducerV7612(texture);',[System.StringComparison]::Ordinal) -lt 0){
        $text=Insert-BeforeLineOnce $text '                    // Once the real Bink storage producer has written this' @(
            '                    if (IsFinalGuestBinkYuvStorageV7602(texture) &&',
            '                        guestImage.Initialized &&',
            '                        !guestImage.SampledCacheOnly)',
            '                    {',
            '                        MarkGuestBinkYuvProducerV7612(texture);',
            '                    }',
            ''
        ) 'bink-yuv-producer-stamp'
        Write-Host '  * bink-yuv-producer-stamp'
    }
    Write-Text $path $text
}

function Assert-V7612Installed([string]$RepoRoot) {
    Assert-V7611Baseline $RepoRoot
    if((Get-BinkStateV7612 $RepoRoot) -ne 'Applied'){throw 'Bink runtime V76.0.12.1 incompleto.'}
    if((Get-PresenterStateV7612 $RepoRoot) -ne 'Applied'){throw 'Presenter V76.0.12.1 incompleto.'}
    $helper=Get-Sha256 (Join-Path $RepoRoot $HelperRel)
    if($helper -ne $HelperExpectedHashV7612){throw "Bink YUV helper V76.0.12.1 mismatch expected=$HelperExpectedHashV7612 actual=$helper"}
}
