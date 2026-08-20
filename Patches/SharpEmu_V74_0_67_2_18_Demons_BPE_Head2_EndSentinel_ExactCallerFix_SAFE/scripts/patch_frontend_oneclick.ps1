. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$codePath=Join-Path $repo 'src\SharpEmu.GUI\MainWindow.axaml.cs'
$code=Normalize-Lf ([IO.File]::ReadAllText($codePath))

$marker='V74.0.67.2.15: Rendering DLSS one-click launch contract'
if($code.Contains($marker)){
    Write-Host '[V74.0.67.2.15] Frontend one-click bridge already applied.'
    return
}

foreach($required in @(
    'V74.0.66.1.1: Rendering menu drives Vulkan upscaler selection',
    '"SHARPEMU_VK_UPSCALER"',
    '"SHARPEMU_VK_UPSCALER_QUALITY"'))
{
    if(!$code.Contains($required)){
        throw "[V74.0.67.2.15] Required frontend marker missing: $required"
    }
}

$anchor=@'
        Environment.SetEnvironmentVariable(
            "SHARPEMU_VK_UPSCALER_QUALITY",
            _settings.UpscalerQuality.ToLowerInvariant());
'@

$count=Count-Ordinal -Text $code -Needle $anchor
if($count-ne 1){
    throw "[V74.0.67.2.15] Frontend quality-env anchor count=$count expected=1"
}

$insert=@'

        // V74.0.67.2.15: Rendering DLSS one-click launch contract.
        // The backend already defaults pre-composite to enabled, but set it
        // explicitly here so normal GUI launches do not depend on shell state.
        Environment.SetEnvironmentVariable(
            "SHARPEMU_VK_UPSCALER_PRECOMPOSITE",
            _settings.UpscalerEnabled ? "1" : "0");

        // Normal frontend launches also receive the validated bounded RAM
        // defaults. The V2.15 source-side TTL property accepts up to 120 s.
        Environment.SetEnvironmentVariable(
            "SHARPEMU_LARGE_ARRAY_SNAPSHOT_CACHE_ENTRIES",
            "2");
        Environment.SetEnvironmentVariable(
            "SHARPEMU_LARGE_ARRAY_SNAPSHOT_REUSE_MS",
            "120000");
        Environment.SetEnvironmentVariable(
            "SHARPEMU_VK_DETILE_POOL_MB",
            "64");
'@

$code=$code.Replace($anchor,$anchor+$insert)

[IO.File]::WriteAllText(
    $codePath,
    (Restore-Newlines $code),
    [Text.UTF8Encoding]::new($false))

Write-Host '[V74.0.67.2.15] FRONTEND ONE-CLICK DLSS/RAM LAUNCH BRIDGE APPLIED.'
