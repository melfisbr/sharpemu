. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot

$csproj=Join-Path $repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
$bridge=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanUpscalerBridge.cs'
$frontend=Join-Path $repo 'src\SharpEmu.GUI\MainWindow.axaml.cs'

foreach($path in @($csproj,$bridge,$frontend)){
    if(!(Test-Path -LiteralPath $path -PathType Leaf)){throw "Missing source: $path"}
}

$c=Normalize-Lf ([IO.File]::ReadAllText($csproj))
$b=Normalize-Lf ([IO.File]::ReadAllText($bridge))
$f=Normalize-Lf ([IO.File]::ReadAllText($frontend))

$checks=[ordered]@{
    quality_v219=$b.Contains('V74.0.67.2.19 strict requested quality profile passthrough')
    quality_strict=$b.Contains('var effectiveQuality = requestedQuality;')
    provider_autoload=$b.Contains('SharpEmu.VulkanUpscaler.Native.dll')
    frontend_backend=$f.Contains('"SHARPEMU_VK_UPSCALER"')
    frontend_quality=$f.Contains('"SHARPEMU_VK_UPSCALER_QUALITY"')
}

$failed=$false
foreach($entry in $checks.GetEnumerator()){
    Write-Host "[V74.0.67.2.20] precheck_$($entry.Key)=$($entry.Value.ToString().ToLowerInvariant())"
    if(!$entry.Value){$failed=$true}
}

$already=$c.Contains('V74.0.67.2.20 DLSS dual-config runtime deployment')
Write-Host "[V74.0.67.2.20] deployment_already=$($already.ToString().ToLowerInvariant())"

if(!$already){
    $closeCount=Count-Ordinal -Text $c -Needle '</Project>'
    Write-Host "[V74.0.67.2.20] csproj_close_project_count=$closeCount"
    if($closeCount-ne 1){$failed=$true}
}else{
    foreach($needle in @(
        '<SharpEmuDlssRuntimeRoot>',
        'Link="upscalers\SharpEmu.VulkanUpscaler.Native.dll"',
        'Link="nvngx_dlss.dll"',
        'CopyToOutputDirectory="PreserveNewest"',
        'CopyToPublishDirectory="PreserveNewest"'))
    {
        $ok=$c.Contains($needle)
        Write-Host "[V74.0.67.2.20] precheck_existing_deployment_token=$($ok.ToString().ToLowerInvariant())"
        if(!$ok){$failed=$true}
    }
}

$releaseProvider=Join-Path $repo 'artifacts\bin\Release\net10.0\win-x64\upscalers\SharpEmu.VulkanUpscaler.Native.dll'
$debugProvider=Join-Path $repo 'artifacts\bin\Debug\net10.0\win-x64\upscalers\SharpEmu.VulkanUpscaler.Native.dll'
$releaseNgx=Join-Path $repo 'artifacts\bin\Release\net10.0\win-x64\nvngx_dlss.dll'
$debugNgx=Join-Path $repo 'artifacts\bin\Debug\net10.0\win-x64\nvngx_dlss.dll'

Write-Host "[V74.0.67.2.20] before_release_provider=$((Test-Path -LiteralPath $releaseProvider).ToString().ToLowerInvariant())"
Write-Host "[V74.0.67.2.20] before_debug_provider=$((Test-Path -LiteralPath $debugProvider).ToString().ToLowerInvariant())"
Write-Host "[V74.0.67.2.20] before_release_ngx=$((Test-Path -LiteralPath $releaseNgx).ToString().ToLowerInvariant())"
Write-Host "[V74.0.67.2.20] before_debug_ngx=$((Test-Path -LiteralPath $debugNgx).ToString().ToLowerInvariant())"

Write-Host '[V74.0.67.2.20] observed_runtime_root_cause=Debug-output-provider-missing'
Write-Host '[V74.0.67.2.20] target=automatic-identical-DLSS-runtime-in-Debug-and-Release'

if($failed){throw '[V74.0.67.2.20] PRECHECK FAILED.'}
Write-Host '[V74.0.67.2.20] PRECHECK PASSED.'
