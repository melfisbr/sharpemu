. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$agcPath=Join-Path $repo 'src\SharpEmu.Libs\Agc\AgcExports.cs'
$a=Normalize-Lf ([IO.File]::ReadAllText($agcPath))

$marker='V74.0.67.2.15 effective large-array TTL'
if($a.Contains($marker)){
    Write-Host '[V74.0.67.2.15] RAM TTL patch already applied.'
    return
}

foreach($required in @(
    'V74.0.67.2.13 large-array sparse-content reuse key',
    '_v74064LargeArraySnapshotTtlMs',
    'SHARPEMU_LARGE_ARRAY_SNAPSHOT_REUSE_MS',
    'TryGetLargeArraySnapshotV74064',
    'StoreLargeArraySnapshotV74064',
    '[V74.0.64][ARRAY_CACHE_OWNER]'))
{
    if(!$a.Contains($required)){
        throw "[V74.0.67.2.15] Required accumulated RAM marker missing: $required"
    }
}

$token='_v74064LargeArraySnapshotTtlMs'
$first=$a.IndexOf($token,[StringComparison]::Ordinal)
if($first-lt 0){throw '[V74.0.67.2.15] TTL field token not found.'}

$lineStart=$a.LastIndexOf("`n",$first)
if($lineStart-lt 0){$lineStart=0}else{$lineStart++}

$semicolon=$a.IndexOf(';',$first)
if($semicolon-lt 0 -or $semicolon-$first-gt 4096){
    throw '[V74.0.67.2.15] Could not safely isolate TTL field declaration.'
}

$declaration=$a.Substring($lineStart,$semicolon-$lineStart+1)
$declMatch=[regex]::Match(
    $declaration,
    '(?s)private\s+static\s+(?:readonly\s+)?(?<type>int|long)\s+_v74064LargeArraySnapshotTtlMs\b')
if(!$declMatch.Success){
    throw "[V74.0.67.2.15] Unexpected TTL field declaration shape: $declaration"
}

$fieldType=$declMatch.Groups['type'].Value
$after=$a.Substring($semicolon+1)
$laterCount=Count-Ordinal -Text $after -Needle $token
if($laterCount-lt 1){
    throw "[V74.0.67.2.15] No TTL consumers found after declaration; laterCount=$laterCount"
}

$after=$after.Replace($token,'V74067215LargeArraySnapshotTtlMs')

if($fieldType-eq 'int'){
    $helper=@'

    // V74.0.67.2.15 effective large-array TTL.
    // V74.0.64 capped the environment-derived value at 30 seconds.
    // Re-read the existing public knob here with a 120-second upper bound.
    // The cache remains bounded by the existing entry-count limit.
    private static int V74067215LargeArraySnapshotTtlMs
    {
        get
        {
            var configured = Environment.GetEnvironmentVariable(
                "SHARPEMU_LARGE_ARRAY_SNAPSHOT_REUSE_MS");
            if (int.TryParse(configured, out var requested))
            {
                return Math.Clamp(requested, 1000, 120000);
            }

            return Math.Clamp(_v74064LargeArraySnapshotTtlMs, 1000, 120000);
        }
    }
'@
}else{
    $helper=@'

    // V74.0.67.2.15 effective large-array TTL.
    // V74.0.64 capped the environment-derived value at 30 seconds.
    // Re-read the existing public knob here with a 120-second upper bound.
    // The cache remains bounded by the existing entry-count limit.
    private static long V74067215LargeArraySnapshotTtlMs
    {
        get
        {
            var configured = Environment.GetEnvironmentVariable(
                "SHARPEMU_LARGE_ARRAY_SNAPSHOT_REUSE_MS");
            if (long.TryParse(configured, out var requested))
            {
                return Math.Clamp(requested, 1000L, 120000L);
            }

            return Math.Clamp(_v74064LargeArraySnapshotTtlMs, 1000L, 120000L);
        }
    }
'@
}

$a=$a.Substring(0,$semicolon+1)+$helper+$after

if(!$a.Contains($marker)){throw '[V74.0.67.2.15] Effective-TTL marker was not inserted.'}
if(!$a.Contains('V74067215LargeArraySnapshotTtlMs')){
    throw '[V74.0.67.2.15] Effective-TTL property missing after transformation.'
}

$tryGetStart=$a.IndexOf('TryGetLargeArraySnapshotV74064',[StringComparison]::Ordinal)
$storeStart=$a.IndexOf('StoreLargeArraySnapshotV74064',[StringComparison]::Ordinal)
if($tryGetStart-lt 0 -or $storeStart-le $tryGetStart){
    throw '[V74.0.67.2.15] Unable to isolate V74.0.64 cache lookup region.'
}
$lookupRegion=$a.Substring($tryGetStart,$storeStart-$tryGetStart)
if(!$lookupRegion.Contains('V74067215LargeArraySnapshotTtlMs')){
    throw '[V74.0.67.2.15] Cache lookup still does not use effective TTL.'
}

[IO.File]::WriteAllText(
    $agcPath,
    (Restore-Newlines $a),
    [Text.UTF8Encoding]::new($false))

Write-Host "[V74.0.67.2.15] RAM TTL PATCH APPLIED. source_field_type=$fieldType redirected_consumers=$laterCount"
Write-Host '[V74.0.67.2.15] RAM TTL range=1000..120000 ms; cache-entry bound remains V74.0.64.'
