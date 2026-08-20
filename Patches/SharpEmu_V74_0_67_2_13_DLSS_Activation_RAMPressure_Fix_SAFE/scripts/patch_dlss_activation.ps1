. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepoRoot
$bridgePath=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanUpscalerBridge.cs'
$b=Normalize-Lf ([IO.File]::ReadAllText($bridgePath))

if($b.Contains('V74.0.67.2.13 bounded provider activation retry')){
    Write-Host '[V74.0.67.2.13] DLSS activation retry already applied.'
    return
}

function Replace-One {
    param(
        [Parameter(Mandatory=$true)][string]$Text,
        [Parameter(Mandatory=$true)][string]$Old,
        [Parameter(Mandatory=$true)][string]$New,
        [Parameter(Mandatory=$true)][string]$Label
    )
    $count=Count-Ordinal -Text $Text -Needle $Old
    if($count-ne 1){throw "[V74.0.67.2.13] Anchor '$Label' count=$count expected=1"}
    return $Text.Replace($Old,$New)
}

if(!$b.Contains('V74.0.67.2.10.2 lazy last-error + init-size retry')){
    throw '[V74.0.67.2.13] V2.10.2 provider-init instrumentation is required.'
}

$oldFields='        private string _upscalerInitFailureReason = string.Empty;'
$newFields=@'
        private string _upscalerInitFailureReason = string.Empty;

        // V74.0.67.2.13 bounded provider activation retry
        private long _upscalerInitNextRetryTick;
        private int _upscalerInitRetryCount;
        private const long V74067213ProviderRetryMs = 2000;
'@
$b=Replace-One $b $oldFields $newFields 'provider retry fields'

$oldInitResult='            public int LastInitializeResult { get; private set; }'
$newInitResult=@'
            public int LastInitializeResult { get; private set; }
            public bool IsInitialized => _initialized;
'@
$b=Replace-One $b $oldInitResult $newInitResult 'native initialized property'

$initSignature='        private bool TryInitializeUpscaler(uint requestedOutputWidth = 0, uint requestedOutputHeight = 0)'
$ensureSignature='        private bool TryEnsureUpscalerOutput('
$initStart=$b.IndexOf($initSignature,[StringComparison]::Ordinal)
$initEnd=if($initStart-ge 0){$b.IndexOf($ensureSignature,$initStart,[StringComparison]::Ordinal)}else{-1}
if($initStart-lt 0 -or $initEnd-le $initStart){throw '[V74.0.67.2.13] Cannot isolate TryInitializeUpscaler.'}
$init=$b.Substring($initStart,$initEnd-$initStart)

$oldRetry=@'
            if (_upscalerInitAttempted &&
                _nativeUpscaler is null &&
                (_upscalerInitFailedWidth != outputWidth ||
                 _upscalerInitFailedHeight != outputHeight))
            {
                Console.Error.WriteLine(
                    $"[V74.0.67.2.10.2][UPSCALER][PROVIDER_INIT] state=retry_size_change " +
                    $"previous={_upscalerInitFailedWidth}x{_upscalerInitFailedHeight} " +
                    $"requested={outputWidth}x{outputHeight} " +
                    $"previous_reason={_upscalerInitFailureReason}");
                _upscalerInitAttempted = false;
                _upscalerInitFailureReason = string.Empty;
                _upscalerOutputReset = true;
            }
'@
$newRetry=@'
            var retryNow = Environment.TickCount64;
            if (_upscalerInitAttempted &&
                !_upscalerRequiredExtensionMissing &&
                (_nativeUpscaler is null || !_nativeUpscaler.IsInitialized))
            {
                var failedSizeChanged =
                    _upscalerInitFailedWidth != outputWidth ||
                    _upscalerInitFailedHeight != outputHeight;
                var retryDelayElapsed =
                    _upscalerInitNextRetryTick == 0 ||
                    unchecked(retryNow - _upscalerInitNextRetryTick) >= 0;

                if (!failedSizeChanged && !retryDelayElapsed)
                {
                    return false;
                }

                Console.Error.WriteLine(
                    $"[V74.0.67.2.13][UPSCALER][PROVIDER_INIT] state=retry " +
                    $"attempt={_upscalerInitRetryCount + 1} " +
                    $"previous={_upscalerInitFailedWidth}x{_upscalerInitFailedHeight} " +
                    $"requested={outputWidth}x{outputHeight} " +
                    $"size_changed={(failedSizeChanged ? 1 : 0)} " +
                    $"previous_reason={_upscalerInitFailureReason}");

                _upscalerInitAttempted = false;
                _upscalerOutputReset = true;
            }
'@
if((Count-Ordinal -Text $init -Needle $oldRetry)-ne 1){throw '[V74.0.67.2.13] V2.10.2 retry anchor mismatch.'}
$init=$init.Replace($oldRetry,$newRetry)

$oldResize=@'
            if (_upscalerInitAttempted &&
                _nativeUpscaler is not null &&
                (_upscalerInitWidth != outputWidth || _upscalerInitHeight != outputHeight))
'@
$newResize=@'
            if (_upscalerInitAttempted &&
                _nativeUpscaler is { IsInitialized: true } &&
                (_upscalerInitWidth != outputWidth || _upscalerInitHeight != outputHeight))
'@
if((Count-Ordinal -Text $init -Needle $oldResize)-ne 1){throw '[V74.0.67.2.13] initialized-size-change anchor mismatch.'}
$init=$init.Replace($oldResize,$newResize)

$oldAttempted=@'
            if (_upscalerInitAttempted)
            {
                return _nativeUpscaler is not null;
            }
'@
$newAttempted=@'
            if (_upscalerInitAttempted)
            {
                return _nativeUpscaler is { IsInitialized: true };
            }
'@
if((Count-Ordinal -Text $init -Needle $oldAttempted)-ne 1){throw '[V74.0.67.2.13] attempted gate anchor mismatch.'}
$init=$init.Replace($oldAttempted,$newAttempted)

$oldNull=@'
            if (provider is null)
            {
                RecordUpscalerInitFailure(
                    outputWidth,
                    outputHeight,
                    "provider_dll_not_loaded");
                Console.Error.WriteLine(
                    $"[V74.0.67.2.10.2][UPSCALER][PROVIDER_INIT] state=failed " +
                    $"result=managed output={outputWidth}x{outputHeight} " +
                    $"last_error=provider_dll_not_loaded");
                return false;
            }
'@
$newNull=@'
            if (provider is null)
            {
                RecordUpscalerInitFailure(
                    outputWidth,
                    outputHeight,
                    "provider_dll_not_loaded");
                _upscalerInitRetryCount++;
                _upscalerInitNextRetryTick =
                    retryNow + V74067213ProviderRetryMs;
                Console.Error.WriteLine(
                    $"[V74.0.67.2.13][UPSCALER][PROVIDER_INIT] state=failed " +
                    $"attempt={_upscalerInitRetryCount} result=managed " +
                    $"output={outputWidth}x{outputHeight} " +
                    $"retry_ms={V74067213ProviderRetryMs} " +
                    $"last_error=provider_dll_not_loaded");
                return false;
            }
'@
if((Count-Ordinal -Text $init -Needle $oldNull)-ne 1){throw '[V74.0.67.2.13] provider-null anchor mismatch.'}
$init=$init.Replace($oldNull,$newNull)

$oldFail=@'
            if (!provider.Initialize(desc))
            {
                var nativeError = provider.LastError;
                if (string.IsNullOrWhiteSpace(nativeError))
                {
                    nativeError =
                        "native_provider_returned_failure_without_error_text";
                }

                RecordUpscalerInitFailure(
                    outputWidth,
                    outputHeight,
                    nativeError);

                Console.Error.WriteLine(
                    $"[V74.0.67.2.10.2][UPSCALER][PROVIDER_INIT] state=failed " +
                    $"result={provider.LastInitializeResult} " +
                    $"output={outputWidth}x{outputHeight} " +
                    $"last_error_export={(provider.HasLastErrorExport ? 1 : 0)} " +
                    $"last_error={nativeError}");

                provider.Dispose();
                _nativeUpscaler = null;
                return false;
            }
'@
$newFail=@'
            if (!provider.Initialize(desc))
            {
                var nativeError = provider.LastError;
                if (string.IsNullOrWhiteSpace(nativeError))
                {
                    nativeError =
                        "native_provider_returned_failure_without_error_text";
                }

                RecordUpscalerInitFailure(
                    outputWidth,
                    outputHeight,
                    nativeError);
                _upscalerInitRetryCount++;
                _upscalerInitNextRetryTick =
                    retryNow + V74067213ProviderRetryMs;

                Console.Error.WriteLine(
                    $"[V74.0.67.2.13][UPSCALER][PROVIDER_INIT] state=failed " +
                    $"attempt={_upscalerInitRetryCount} " +
                    $"result={provider.LastInitializeResult} " +
                    $"output={outputWidth}x{outputHeight} provider_loaded=1 " +
                    $"last_error_export={(provider.HasLastErrorExport ? 1 : 0)} " +
                    $"retry_ms={V74067213ProviderRetryMs} " +
                    $"last_error={nativeError}");

                return false;
            }
'@
if((Count-Ordinal -Text $init -Needle $oldFail)-ne 1){throw '[V74.0.67.2.13] native init failure anchor mismatch.'}
$init=$init.Replace($oldFail,$newFail)

$successAnchor=@'
            _upscalerInitFailedWidth = 0;
            _upscalerInitFailedHeight = 0;
            _upscalerInitFailureReason = string.Empty;
'@
$successNew=@'
            _upscalerInitFailedWidth = 0;
            _upscalerInitFailedHeight = 0;
            _upscalerInitFailureReason = string.Empty;
            _upscalerInitNextRetryTick = 0;
            _upscalerInitRetryCount = 0;
'@
if((Count-Ordinal -Text $init -Needle $successAnchor)-ne 1){throw '[V74.0.67.2.13] success reset anchor mismatch.'}
$init=$init.Replace($successAnchor,$successNew)

$oldActive='[V74.0.67.2.10.2][UPSCALER][PROVIDER_INIT] state=active '
if((Count-Ordinal -Text $init -Needle $oldActive)-ne 1){throw '[V74.0.67.2.13] active telemetry anchor mismatch.'}
$init=$init.Replace($oldActive,'[V74.0.67.2.13][UPSCALER][PROVIDER_INIT] state=active ')

$b=$b.Substring(0,$initStart)+$init+$b.Substring($initEnd)
[IO.File]::WriteAllText($bridgePath,(Restore-Newlines $b),[Text.UTF8Encoding]::new($false))
Write-Host '[V74.0.67.2.13] BOUNDED PROVIDER ACTIVATION RETRY APPLIED.'
