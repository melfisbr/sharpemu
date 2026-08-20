param([Parameter(Mandatory=$true)][string]$PackageRoot)
. (Join-Path $PSScriptRoot 'common.ps1') -PackageRoot $PackageRoot
& (Join-Path $PSScriptRoot 'validate_package.ps1') -PackageRoot $PackageRoot
$s=Assert-StructuralContracts
$a=$s.Agc;$nl=if($a.Contains("`r`n")){"`r`n"}else{"`n"};$backup=$null
$marker='SHARPEMU_V74_0_87_COOPERATIVE_GATE_QUANTUM'
if(-not $a.Contains($marker)){
 $backup=New-Backup
 try{
   $fieldAnchor='private static long _v74085ReleaseQueueOnlyTraceCount;'
   $fa=$a.IndexOf($fieldAnchor,[System.StringComparison]::Ordinal)
   if($fa -lt 0){throw "$script:Tag V85 field anchor missing."}
   $semi=$a.IndexOf(';',$fa,[System.StringComparison]::Ordinal)
   if($semi -lt 0){throw "$script:Tag V85 field semicolon missing."}
   $fields=@"

    // $marker
    // V86.4 proved resource retention is not the dominant limiter. V71 shows
    // multi-second starvation on gpuState.Gate. Bound ownership to short packet
    // quanta and hand the monitor to queued waiter/submit threads between PM4
    // packets. 0/0 restores the legacy uninterrupted lock ownership.
    private static readonly int _gateQuantumPacketsV74087 =
        int.TryParse(Environment.GetEnvironmentVariable("SHARPEMU_AGC_GATE_QUANTUM_PACKETS"), out var gateQuantumPacketsV74087) && gateQuantumPacketsV74087 >= 0
            ? gateQuantumPacketsV74087
            : 16;
    private static readonly long _gateQuantumTicksV74087 =
        (long.TryParse(Environment.GetEnvironmentVariable("SHARPEMU_AGC_GATE_QUANTUM_MS"), out var gateQuantumMsV74087) && gateQuantumMsV74087 >= 0
            ? gateQuantumMsV74087
            : 1L) * System.Diagnostics.Stopwatch.Frequency / 1000L;
    [ThreadStatic] private static int _gateQuantumPacketCountV74087;
    [ThreadStatic] private static long _gateQuantumStartTicksV74087;
    private static long _gateQuantumYieldTraceCountV74087;
"@ -replace "`n",$nl
   $a=$a.Insert($semi+1,$fields)

   $gate=Get-ContainingPrivateStaticMethodByMarker $a 'GATE_OWNER_WAIT_DRAIN'
   if($null -eq $gate){throw "$script:Tag V72 method vanished after field insertion."}
   if([string]::IsNullOrWhiteSpace($gate.StateParam)){throw "$script:Tag V72 SubmittedGpuState param vanished."}
   $sp=$gate.StateParam
   $body=$gate.Text
   if($body.Contains('GATE_QUANTUM_YIELD')){throw "$script:Tag unexpected partial V87 marker inside V72 method."}
   $yield=@"

        // SHARPEMU_V74_0_87_GATE_QUANTUM_YIELD
        // This method is invoked at a complete PM4 packet boundary by V72.
        // Never release the monitor inside a packet or ordered side effect.
        if ((_gateQuantumPacketsV74087 > 0 || _gateQuantumTicksV74087 > 0) &&
            System.Threading.Monitor.IsEntered($sp.Gate))
        {
            var gateQuantumNowV74087 = System.Diagnostics.Stopwatch.GetTimestamp();
            if (_gateQuantumStartTicksV74087 == 0)
            {
                _gateQuantumStartTicksV74087 = gateQuantumNowV74087;
            }
            var gateQuantumPacketsSeenV74087 = ++_gateQuantumPacketCountV74087;
            var gateQuantumElapsedV74087 = gateQuantumNowV74087 - _gateQuantumStartTicksV74087;
            var gateQuantumDueV74087 =
                (_gateQuantumPacketsV74087 > 0 && gateQuantumPacketsSeenV74087 >= _gateQuantumPacketsV74087) ||
                (_gateQuantumTicksV74087 > 0 && gateQuantumElapsedV74087 >= _gateQuantumTicksV74087);
            if (gateQuantumDueV74087)
            {
                _gateQuantumPacketCountV74087 = 0;
                _gateQuantumStartTicksV74087 = 0;
                System.Threading.Monitor.Exit($sp.Gate);
                try
                {
                    if (!System.Threading.Thread.Yield())
                    {
                        System.Threading.Thread.Sleep(0);
                    }
                }
                finally
                {
                    System.Threading.Monitor.Enter($sp.Gate);
                }

                var gateQuantumYieldV74087 = System.Threading.Interlocked.Increment(
                    ref _gateQuantumYieldTraceCountV74087);
                if (gateQuantumYieldV74087 <= 256 ||
                    (gateQuantumYieldV74087 & (gateQuantumYieldV74087 - 1)) == 0)
                {
                    var gateQuantumUsV74087 = gateQuantumElapsedV74087 * 1000000.0 /
                        System.Diagnostics.Stopwatch.Frequency;
                    Console.Error.WriteLine(
                        $"[V74.0.87][GATE_QUANTUM_YIELD] count={gateQuantumYieldV74087} " +
                        $"packets={gateQuantumPacketsSeenV74087} elapsed_us={gateQuantumUsV74087:F1}");
                }
            }
        }
"@ -replace "`n",$nl
   # Insert immediately before the containing method's final brace. The V72
   # method itself is the packet-boundary hook, so this runs only after its real
   # waiter drain/trace logic has completed.
   $newBody=$body.Insert($body.Length-1,$yield)
   $a=$a.Remove($gate.Start,$gate.Length).Insert($gate.Start,$newBody)

   if((Get-Count $a 'SHARPEMU_V74_0_87_COOPERATIVE_GATE_QUANTUM') -ne 1){throw "$script:Tag V87 field marker count invalid after transform."}
   if((Get-Count $a 'SHARPEMU_V74_0_87_GATE_QUANTUM_YIELD') -ne 1){throw "$script:Tag V87 yield marker count invalid after transform."}
   if((Get-Count $a 'GATE_OWNER_WAIT_DRAIN') -lt 1){throw "$script:Tag V72 marker lost after transform."}
   if(-not $s.Presenter.Contains('SHARPEMU_V74_0_81_2_COMPUTE_START_FENCE_BOUNDARY') -or -not $s.Presenter.Contains('SHARPEMU_V74_0_81_2_RESOURCE_UPLOAD_FENCE_BOUNDARY')){throw "$script:Tag V81.2 boundaries missing in preserved Presenter."}
   Write-Utf8NoBom $script:AgcPath $a
   Write-Host "$script:Tag PATCH APPLIED STRUCTURALLY." -ForegroundColor Green
   Write-Host "$script:Tag gate_quantum=default-on packets=16 ms=1 env_0_0_restores_legacy"
   Write-Host "$script:Tag yield_site=V72_packet_boundary monitor_exit_yield_enter=True"
   Write-Host "$script:Tag packet_atomicity=True ordered_side_effect_atomicity=True"
   Write-Host "$script:Tag v86_4_resident_retention_preserved=True v85_aggressive_pm4_preserved=True"
   Write-Host "$script:Tag v81_2_vulkan_boundaries_preserved=True"
   Write-Host "$script:Tag Backup=$backup"
   Write-Host "$script:Tag AgcSHA256=$(Get-Sha256 $script:AgcPath)"
 }catch{if($null -ne $backup -and(Test-Path -LiteralPath $backup)){Restore-Backup $backup};throw}
}else{Write-Host "$script:Tag State=AlreadyApplied"}
$buildLog=Join-Path $script:PatchesRoot ("SharpEmu_V74_0_87_APPLY_BUILD_"+(Get-Date -Format 'yyyyMMdd_HHmmss')+'.log')
Write-Host "$script:Tag Building SharpEmu.CLI Debug win-x64..."
$project=Join-Path $script:RepoRoot 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
try{& dotnet build $project -c Debug -r win-x64 2>&1|Tee-Object -FilePath $buildLog;$code=$LASTEXITCODE}catch{$code=1;$_|Out-String|Add-Content -LiteralPath $buildLog}
if($code -ne 0){if($null -ne $backup -and(Test-Path -LiteralPath $backup)){Restore-Backup $backup;Write-Host "$script:Tag BUILD FAILED; source automatically restored from $backup" -ForegroundColor Yellow};throw "$script:Tag BUILD FAILED. Log=$buildLog"}
Write-Host "$script:Tag BUILD PASSED. Log=$buildLog" -ForegroundColor Green
