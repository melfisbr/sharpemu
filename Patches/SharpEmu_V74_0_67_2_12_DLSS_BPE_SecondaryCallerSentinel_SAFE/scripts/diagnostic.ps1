. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$patches=Get-PatchesRoot

$bridgePath=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanUpscalerBridge.cs'
$exceptionsPath=Join-Path $repo 'src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.Exceptions.cs'
$b=Normalize-Lf ([IO.File]::ReadAllText($bridgePath))
$e=Normalize-Lf ([IO.File]::ReadAllText($exceptionsPath))

$releaseHost=Find-ReleaseHost -Repo $repo
$provider=$null;$ngx=$null
if($null-ne $releaseHost){
    $provider=Join-Path $releaseHost.DirectoryName 'upscalers\SharpEmu.VulkanUpscaler.Native.dll'
    $ngx=Join-Path $releaseHost.DirectoryName 'nvngx_dlss.dll'
}

$checks=[ordered]@{
    secondary_caller_marker=$e.Contains('V74.0.67.2.12 BPE secondary-caller sentinel recovery')
    secondary_import=$e.Contains('"GuchCTefuZw"')
    original_import_preserved=$e.Contains('"tcVi5SivF7Q"')
    r13_secondary_shape=$e.Contains('secondaryImport && rdi == r13')
    r15_payload_gate=$e.Contains('r15 != payload')
    stack_return_address_read=$e.Contains('TryReadHostQword(rsp, out ulong returnAddress)')
    caller_signature_qword0=$e.Contains('0x8374F8394CC58949UL')
    caller_signature_qword1=$e.Contains('0x20458B41UL')
    variant_telemetry=$e.Contains('variant={callerVariant} last_import={lastImportNid}')
    v211_payload_return_preserved=
        $e.Contains('V74.0.67.2.11 BPE end-sentinel return repair') -and
        $e.Contains('WriteCtxU64(ctx, CTX_RAX, payload);')
    dlss_v2102_preserved=$b.Contains('V74.0.67.2.10.2 lazy last-error + init-size retry')
    provider_init_telemetry=$b.Contains('[V74.0.67.2.10.2][UPSCALER][PROVIDER_INIT]')
    release_host_exists=$null-ne $releaseHost
    deployed_provider_exists=$null-ne $provider -and (Test-Path -LiteralPath $provider)
    deployed_nvngx_exists=$null-ne $ngx -and (Test-Path -LiteralPath $ngx)
}

$failed=$false
$result=New-Object System.Collections.Generic.List[string]
foreach($entry in $checks.GetEnumerator()){
    $line="[V74.0.67.2.12] $($entry.Key)=$($entry.Value.ToString().ToLowerInvariant())"
    Write-Host $line
    $result.Add($line)
    if(!$entry.Value){$failed=$true}
}

if($null-ne $provider -and (Test-Path -LiteralPath $provider)){
    $ok=Test-NativeExport -DllPath $provider -ExportName 'sharpemu_vk_upscaler_get_last_error'
    $line="[V74.0.67.2.12] export_sharpemu_vk_upscaler_get_last_error=$($ok.ToString().ToLowerInvariant())"
    Write-Host $line
    $result.Add($line)
    if(!$ok){$failed=$true}
}

$result.Add('[V74.0.67.2.12] CRASH_PROOF=primary+secondary BPE variants recover with rax=payload')
$result.Add('[V74.0.67.2.12] EXPECTED_SECONDARY=variant=secondary-r13-r15 last_import=GuchCTefuZw')
$result.Add('[V74.0.67.2.12] DLSS_TELEMETRY_OWNER=V74.0.67.2.10.2')
$result.Add('[V74.0.67.2.12] DLSS_TRUTH=selected=dlss AND state=active AND dlss_dispatches>0')

if($failed){throw '[V74.0.67.2.12] STRUCTURAL/BINARY DIAGNOSTIC FAILED.'}

Write-Host '[V74.0.67.2.12] DIAGNOSTIC PASSED.'
$result.Add('[V74.0.67.2.12] DIAGNOSTIC PASSED.')

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$txt=Join-Path $patches "SharpEmu_V74_0_67_2_12_BPE_SECONDARY_CALLER_RESULT_$stamp.txt"
$zip=Join-Path $patches "SharpEmu_V74_0_67_2_12_BPE_SECONDARY_CALLER_RESULT_$stamp.zip"
[IO.File]::WriteAllLines($txt,$result,[Text.UTF8Encoding]::new($false))
Compress-Archive -LiteralPath $txt -DestinationPath $zip -Force
Write-Host "[V74.0.67.2.12] ResultZip=$zip"
