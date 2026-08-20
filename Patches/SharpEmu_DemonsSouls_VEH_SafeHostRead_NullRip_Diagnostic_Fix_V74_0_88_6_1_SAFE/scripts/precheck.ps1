. "$PSScriptRoot\common.ps1"
$p=Paths

try{
    $read=Locate-TryReadHostQword
    $handler=Locate-VectoredHandler
}
catch{
    Export-MethodDiagnostic $_.Exception.Message|Out-Null
    Write-Host "$script:Tag [ERROR] STRUCTURAL PRECHECK FAILED: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}

Write-Host "$script:Tag RepositoryRoot=$($p.Repo)"
Write-Host "$script:Tag TryReadHostQwordSource=$($read.File)"
Write-Host "$script:Tag TryReadHostQwordSHA256=$(Sha $read.File)"
Write-Host "$script:Tag VectoredHandlerSource=$($handler.File)"
Write-Host "$script:Tag VectoredHandlerSHA256=$(Sha $handler.File)"

$body=$read.Body
$checks=[ordered]@{
    direct_backend_partial_files=(@(Find-DirectBackendFiles).Count -gt 1)
    try_read_signature=$true
    vectored_handler_signature=$true
    current_read_uses_marshal=$body.Contains('Marshal.ReadInt64')
    virtual_query_available=(@(Find-DirectBackendFiles|Where-Object{(NL([IO.File]::ReadAllText($_.FullName))).Contains('VirtualQuery(')}).Count -gt 0)
    memory_info_type_available=(@(Find-DirectBackendFiles|Where-Object{(NL([IO.File]::ReadAllText($_.FullName))).Contains('MEMORY_BASIC_INFORMATION64')}).Count -gt 0)
}

$issues=0
foreach($entry in $checks.GetEnumerator()){
    Write-Host "$($entry.Key)=$($entry.Value)"
    if(-not $entry.Value){$issues++}
}

if($read.Text.Contains('SHARPEMU_V74_0_88_6_1_VEH_SAFE_HOST_QWORD')){
    Write-Host "$script:Tag State=AlreadyApplied Ready=0 Applied=1" -ForegroundColor Yellow
    exit 10
}

if($issues -gt 0){
    Export-MethodDiagnostic "precheck issues=$issues"|Out-Null
    Write-Host "$script:Tag [ERROR] PRECHECK FAILED issues=$issues" -ForegroundColor Red
    exit 3
}

Write-Host "$script:Tag Runtime finding: current crash is NOT Vulkan/Bink; zero host-movie uploads occurred." -ForegroundColor Cyan
Write-Host "$script:Tag Runtime finding: guest Core.Res.Decompressor reached execute AV with RIP=0x0; then VectoredHandler -> TryReadHostQword -> Marshal.ReadInt64 raised a fatal managed AccessViolationException." -ForegroundColor Cyan
Write-Host "$script:Tag Repair: validate the complete host qword with VirtualQuery before Marshal.ReadInt64, preserving existing VEH behavior for the original guest fault." -ForegroundColor Cyan
Write-Host "$script:Tag State=Ready Ready=1 Applied=0" -ForegroundColor Green
exit 0
