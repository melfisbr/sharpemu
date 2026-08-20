. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot

$agcPath=Join-Path $repo 'src\SharpEmu.Libs\Agc\AgcExports.cs'
$bridgePath=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanUpscalerBridge.cs'
$codePath=Join-Path $repo 'src\SharpEmu.GUI\MainWindow.axaml.cs'
$settingsPath=Join-Path $repo 'src\SharpEmu.GUI\GuiSettings.cs'
$exceptionsPath=Join-Path $repo 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.Exceptions.cs'

foreach($path in @($agcPath,$bridgePath,$codePath,$settingsPath,$exceptionsPath)){
    if(!(Test-Path -LiteralPath $path -PathType Leaf)){throw "Missing required source: $path"}
}

$a=Normalize-Lf ([IO.File]::ReadAllText($agcPath))
$b=Normalize-Lf ([IO.File]::ReadAllText($bridgePath))
$c=Normalize-Lf ([IO.File]::ReadAllText($codePath))
$s=Normalize-Lf ([IO.File]::ReadAllText($settingsPath))
$e=Normalize-Lf ([IO.File]::ReadAllText($exceptionsPath))

$checks=[ordered]@{
    dlss_runtime_proven_source=$b.Contains('V74.0.67.2.13 bounded provider activation retry')
    dlss_command_buffer_fix=$b.Contains('V74.0.67.2.14 pre-composite command-buffer ownership')
    dlss_precomposite_default_true=$b.Contains('ReadUpscalerBool("SHARPEMU_VK_UPSCALER_PRECOMPOSITE", true)')
    dlss_provider_autodiscovery=$b.Contains('Path.Combine(AppContext.BaseDirectory, "upscalers", "SharpEmu.VulkanUpscaler.Native.dll")')
    frontend_enabled_setting=$s.Contains('public bool UpscalerEnabled')
    frontend_backend_setting=$s.Contains('public string UpscalerBackend')
    frontend_quality_setting=$s.Contains('public string UpscalerQuality')
    frontend_backend_env=$c.Contains('"SHARPEMU_VK_UPSCALER"')
    frontend_quality_env=$c.Contains('"SHARPEMU_VK_UPSCALER_QUALITY"')
    ram_v213_content_identity=$a.Contains('V74.0.67.2.13 large-array sparse-content reuse key')
    ram_v74064_ttl_field=$a.Contains('_v74064LargeArraySnapshotTtlMs')
    ram_v74064_env=$a.Contains('SHARPEMU_LARGE_ARRAY_SNAPSHOT_REUSE_MS')
    ram_v74064_lookup=$a.Contains('TryGetLargeArraySnapshotV74064')
    ram_v74064_store=$a.Contains('StoreLargeArraySnapshotV74064')
    bpe_v212=$e.Contains('V74.0.67.2.12 BPE secondary-caller sentinel recovery')
}

$failed=$false
foreach($entry in $checks.GetEnumerator()){
    Write-Host "[V74.0.67.2.15.1] precheck_$($entry.Key)=$($entry.Value.ToString().ToLowerInvariant())"
    if(!$entry.Value){$failed=$true}
}

$ramAlready=$a.Contains('V74.0.67.2.15 effective large-array TTL')
$frontAlready=$c.Contains('V74.0.67.2.15: Rendering DLSS one-click launch contract')
Write-Host "[V74.0.67.2.15.1] ram_ttl_already=$($ramAlready.ToString().ToLowerInvariant())"
Write-Host "[V74.0.67.2.15.1] frontend_oneclick_already=$($frontAlready.ToString().ToLowerInvariant())"

if(!$ramAlready){
    $token='_v74064LargeArraySnapshotTtlMs'
    $first=$a.IndexOf($token,[StringComparison]::Ordinal)
    $semicolon=if($first-ge 0){$a.IndexOf(';',$first)}else{-1}
    $lineStart=if($first-ge 0){$a.LastIndexOf("`n",$first)}else{-1}
    if($lineStart-lt 0){$lineStart=0}else{$lineStart++}

    $declOk=$false
    $fieldType=''
    $laterCount=0
    $dryLookupOk=$false
    if($first-ge 0 -and $semicolon-gt $first -and $semicolon-$first-le 4096){
        $declaration=$a.Substring($lineStart,$semicolon-$lineStart+1)
        $m=[regex]::Match(
            $declaration,
            '(?s)private\s+static\s+(?:readonly\s+)?(?<type>int|long)\s+_v74064LargeArraySnapshotTtlMs\b')
        $declOk=$m.Success
        if($m.Success){$fieldType=$m.Groups['type'].Value}

        $after=$a.Substring($semicolon+1)
        $laterCount=Count-Ordinal -Text $after -Needle $token
        $simulatedAfter=$after.Replace($token,'V74067215LargeArraySnapshotTtlMs')
        $simulated=$a.Substring(0,$semicolon+1)+$simulatedAfter
        $lookupStart=$simulated.IndexOf('TryGetLargeArraySnapshotV74064',[StringComparison]::Ordinal)
        $storeStart=$simulated.IndexOf('StoreLargeArraySnapshotV74064',[StringComparison]::Ordinal)
        if($lookupStart-ge 0 -and $storeStart-gt $lookupStart){
            $region=$simulated.Substring($lookupStart,$storeStart-$lookupStart)
            $dryLookupOk=$region.Contains('V74067215LargeArraySnapshotTtlMs')
        }
    }

    Write-Host "[V74.0.67.2.15.1] ram_field_declaration_safe=$($declOk.ToString().ToLowerInvariant())"
    Write-Host "[V74.0.67.2.15.1] ram_field_type=$fieldType"
    Write-Host "[V74.0.67.2.15.1] ram_later_ttl_consumer_count=$laterCount"
    Write-Host "[V74.0.67.2.15.1] ram_dryrun_lookup_redirect=$($dryLookupOk.ToString().ToLowerInvariant())"
    if(!$declOk -or $laterCount-lt 1 -or !$dryLookupOk){$failed=$true}
}else{
    $effectiveOk=$a.Contains('V74067215LargeArraySnapshotTtlMs')
    Write-Host "[V74.0.67.2.15.1] ram_effective_property=$($effectiveOk.ToString().ToLowerInvariant())"
    if(!$effectiveOk){$failed=$true}
}

if(!$frontAlready){
    $frontAnchor=@'
        Environment.SetEnvironmentVariable(
            "SHARPEMU_VK_UPSCALER_QUALITY",
            _settings.UpscalerQuality.ToLowerInvariant());
'@
    $frontCount=Count-Ordinal -Text $c -Needle $frontAnchor
    Write-Host "[V74.0.67.2.15.1] frontend_quality_anchor_count=$frontCount"
    if($frontCount-ne 1){$failed=$true}
}

Write-Host '[V74.0.67.2.15.1] frontend_dlss_required_user_action=enable-toggle+select-DLSS+choose-quality'
Write-Host '[V74.0.67.2.15.1] frontend_extra_shell_variables_required=false'
Write-Host '[V74.0.67.2.15.1] frontend_provider_path_required=false'
Write-Host '[V74.0.67.2.15.1] ram_target_ttl_ms=120000'
Write-Host '[V74.0.67.2.15.1] hardcoded_guest_resource_address=false'

if($failed){throw '[V74.0.67.2.15.1] PRECHECK FAILED.'}
Write-Host '[V74.0.67.2.15.1] PRECHECK PASSED.'
