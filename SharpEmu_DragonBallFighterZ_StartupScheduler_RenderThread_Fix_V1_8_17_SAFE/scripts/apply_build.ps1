. (Join-Path $PSScriptRoot "common.ps1")
& (Join-Path $PSScriptRoot "precheck.ps1")
$repo=Find-RepoRoot
$main=Join-Path $repo "src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.cs"
$worker=Join-Path $repo "src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.NativeWorker.cs"
$mt=Get-Content -LiteralPath $main -Raw
$wt=Get-Content -LiteralPath $worker -Raw

$backup=Join-Path $repo (".sharpemu-hotfix-backup\DBFZ_StartupScheduler_V1_8_17_"+(Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force -Path $backup|Out-Null
Copy-Item -LiteralPath $main -Destination (Join-Path $backup "DirectExecutionBackend.cs") -Force
Copy-Item -LiteralPath $worker -Destination (Join-Path $backup "DirectExecutionBackend.NativeWorker.cs") -Force

try {
    if(-not $mt.Contains('SHARPEMU_DB_FZ_EXEC_SETUP_CACHE_V1_8_17')) {
        $fieldAnchor="`tprivate readonly List<nint> _importHandlerTrampolines = new List<nint>();"
        $fi=$mt.IndexOf($fieldAnchor,[StringComparison]::Ordinal)
        if($fi -lt 0){throw "Import trampoline field anchor not found."}
        $insertAt=$fi+$fieldAnchor.Length
        $fields=@'

	// SHARPEMU_DB_FZ_EXEC_SETUP_CACHE_V1_8_17
	// Module initializers re-enter TryExecute with the same merged import table.
	// Import trampolines and TLS pattern patches are process-image setup, not
	// per-initializer state. Cache them until the table shape changes.
	private bool _executionSetupPrepared;
	private int _preparedImportStubCount = -1;
	private int _preparedRuntimeSymbolCount = -1;
	private ulong _preparedImportStubFingerprint;

	private static ulong ComputeImportSetupFingerprint(
		IReadOnlyDictionary<ulong, string> importStubs)
	{
		const ulong offset = 14695981039346656037UL;
		const ulong prime = 1099511628211UL;
		ulong hash = offset;
		foreach (var pair in importStubs)
		{
			hash ^= pair.Key;
			hash *= prime;
			hash ^= StableHash64(pair.Value);
			hash *= prime;
		}
		return hash;
	}
'@
        $mt=$mt.Insert($insertAt,$fields)

        $start=$mt.IndexOf("`t`t`tif (!SetupImportStubs(importStubs))",[StringComparison]::Ordinal)
        if($start -lt 0){throw "TryExecute SetupImportStubs block start not found."}
        $endToken="`t`t`tPatchTlsPatterns();"
        $end=$mt.IndexOf($endToken,$start,[StringComparison]::Ordinal)
        if($end -lt 0){throw "TryExecute PatchTlsPatterns end anchor not found."}
        $end += $endToken.Length

        $replacement=@'
			var importSetupFingerprint = ComputeImportSetupFingerprint(importStubs);
			var canReuseExecutionSetup =
				_executionSetupPrepared &&
				_preparedImportStubCount == importStubs.Count &&
				_preparedRuntimeSymbolCount == runtimeSymbols.Count &&
				_preparedImportStubFingerprint == importSetupFingerprint;

			if (!canReuseExecutionSetup)
			{
				if (!SetupImportStubs(importStubs))
				{
					if (string.IsNullOrEmpty(LastError))
					{
						LastError = "SetupImportStubs failed";
					}
					result = OrbisGen2Result.ORBIS_GEN2_ERROR_MEMORY_FAULT;
					return false;
				}

				CreateTlsHandler();
				PatchTlsPatterns();

				_preparedImportStubCount = importStubs.Count;
				_preparedRuntimeSymbolCount = runtimeSymbols.Count;
				_preparedImportStubFingerprint = importSetupFingerprint;
				_executionSetupPrepared = true;
				Console.Error.WriteLine(
					$"[LOADER][INFO] exec_setup_cache.v1817 primed imports={importStubs.Count} symbols={runtimeSymbols.Count} fp=0x{importSetupFingerprint:X16}");
			}
			else
			{
				Console.Error.WriteLine(
					$"[LOADER][INFO] exec_setup_cache.v1817 hit imports={importStubs.Count} symbols={runtimeSymbols.Count} fp=0x{importSetupFingerprint:X16}");
			}
'@
        $mt=$mt.Remove($start,$end-$start).Insert($start,$replacement)

        # Do not pre-create all 16 workers during startup. Eight covers the
        # title's early TaskGraph/Pool fan-out while additional workers may be
        # created lazily up to the new concurrency cap.
        $oldPre='PrewarmNativeGuestWorkers(Math.Max(NativeWorkerMaxConcurrent, 4));'
        $newPre='PrewarmNativeGuestWorkers(Math.Min(NativeWorkerMaxConcurrent, 8));'
        if(-not $mt.Contains($oldPre)){throw "Native worker prewarm anchor missing."}
        $mt=$mt.Replace($oldPre,$newPre)

        Set-Content -LiteralPath $main -Value $mt -Encoding utf8
        Write-Host "[DBFZ-BOOT-1817] Installed import/TLS setup cache and bounded 8-worker prewarm."
    } else {
        Write-Host "[DBFZ-BOOT-1817] Execution setup cache already present."
    }

    $wt=Get-Content -LiteralPath $worker -Raw
    $rx=[regex]'NativeWorkerMaxConcurrent\s*=\s*2\s*;'
    $matches=$rx.Matches($wt)
    if($matches.Count -eq 1) {
        $wt=$rx.Replace($wt,'NativeWorkerMaxConcurrent = 16;',1)
        Set-Content -LiteralPath $worker -Value $wt -Encoding utf8
        Write-Host "[DBFZ-BOOT-1817] NativeWorkerMaxConcurrent 2 -> 16."
    } elseif($wt -match 'NativeWorkerMaxConcurrent\s*=\s*16\s*;') {
        Write-Host "[DBFZ-BOOT-1817] NativeWorkerMaxConcurrent already 16."
    } else {
        throw "Could not safely patch NativeWorkerMaxConcurrent."
    }

    Push-Location $repo
    try {
        dotnet build .\src\SharpEmu.CLI\SharpEmu.CLI.csproj -c Debug -r win-x64 --nologo
        if($LASTEXITCODE -ne 0){throw "dotnet build failed with exit code $LASTEXITCODE"}
    } finally {Pop-Location}
} catch {
    Copy-Item -LiteralPath (Join-Path $backup "DirectExecutionBackend.cs") -Destination $main -Force
    Copy-Item -LiteralPath (Join-Path $backup "DirectExecutionBackend.NativeWorker.cs") -Destination $worker -Force
    Write-Host "[DBFZ-BOOT-1817] Source restored after patch/build failure."
    throw
}
Write-Host "[DBFZ-BOOT-1817] BUILD PASSED. Backup: $backup"
