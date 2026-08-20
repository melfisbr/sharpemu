. "$PSScriptRoot\common.ps1"
$p=Paths

try{
    $assert=Assert-V740886
}
catch{
    Write-Host "$script:Tag [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$read=Locate-TryReadHostQword
$handler=Locate-VectoredHandler
$body=$read.Body

$qIndex=$body.IndexOf('VirtualQuery(')
$mIndex=$body.IndexOf('Marshal.ReadInt64')
$virtualQueryBeforeRead=($qIndex -ge 0 -and $mIndex -ge 0 -and $qIndex -lt $mIndex)

$safeHostQwordMarker=$read.Text.Contains('SHARPEMU_V74_0_88_6_2_VEH_SAFE_HOST_QWORD')
$unsafeMethodDeclaration=[regex]::IsMatch($read.Text,'(?m)^[ \t]*private[ \t]+unsafe[ \t]+static[ \t]+bool[ \t]+TryReadHostQword[ \t]*\(')
$rejectTrace=$read.Text.Contains('[V74.0.88.6.2][VEH_SAFE_READ_REJECT]')
$commitCheck=$body.Contains('MemCommitV740886')
$noAccessCheck=$body.Contains('PageNoAccessV740886')
$pageGuardCheck=$body.Contains('PageGuardV740886')
$readableProtectCheck=$body.Contains('readableProtectV740886')
$qwordBoundaryCheck=$body.Contains('regionEndV740886 - sizeof(ulong)')
$vectoredHandlerPreserved=(-not $handler.Text.Contains('SHARPEMU_V74_0_88_6_2_NULL_RIP_SKIP'))
$v885PresenterPreserved=(Test-Path -LiteralPath $p.Presenter)
$v883HostMoviePreserved=(Test-Path -LiteralPath $p.HostMovie)
$v88InWindowImePreserved=(Test-Path -LiteralPath $p.ImeOverlay)
$buildArtifactExists=(Test-Path -LiteralPath $p.Exe)

Write-Host "$script:Tag DIAGNOSTIC START" -ForegroundColor Cyan
Write-Host "safe_host_qword_marker=$safeHostQwordMarker"
Write-Host "unsafe_method_declaration=$unsafeMethodDeclaration"
Write-Host "reject_trace=$rejectTrace"
Write-Host "virtual_query_before_read=$virtualQueryBeforeRead"
Write-Host "commit_check=$commitCheck"
Write-Host "noaccess_guard_check=$noAccessCheck"
Write-Host "page_guard_check=$pageGuardCheck"
Write-Host "readable_protection_check=$readableProtectCheck"
Write-Host "qword_boundary_check=$qwordBoundaryCheck"
Write-Host "vectored_handler_preserved=$vectoredHandlerPreserved"
Write-Host "v88_5_presenter_preserved=$v885PresenterPreserved"
Write-Host "v88_3_hostmovie_preserved=$v883HostMoviePreserved"
Write-Host "v88_inwindow_ime_preserved=$v88InWindowImePreserved"
Write-Host "build_artifact_exists=$buildArtifactExists"
Write-Host "$script:Tag TryReadHostQwordSource=$($read.File)"
Write-Host "$script:Tag VectoredHandlerSource=$($handler.File)"

$failed=@()
if(-not $safeHostQwordMarker){$failed+='safe_host_qword_marker'}
if(-not $unsafeMethodDeclaration){$failed+='unsafe_method_declaration'}
if(-not $rejectTrace){$failed+='reject_trace'}
if(-not $virtualQueryBeforeRead){$failed+='virtual_query_before_read'}
if(-not $commitCheck){$failed+='commit_check'}
if(-not $noAccessCheck){$failed+='noaccess_guard_check'}
if(-not $pageGuardCheck){$failed+='page_guard_check'}
if(-not $readableProtectCheck){$failed+='readable_protection_check'}
if(-not $qwordBoundaryCheck){$failed+='qword_boundary_check'}
if(-not $vectoredHandlerPreserved){$failed+='vectored_handler_preserved'}
if(-not $buildArtifactExists){$failed+='build_artifact_exists'}

if($failed.Count -gt 0){
    Write-Host "$script:Tag [ERROR] DIAGNOSTIC FAILED: $($failed -join ', ')" -ForegroundColor Red
    exit 1
}

Write-Host "$script:Tag DIAGNOSTIC PASSED." -ForegroundColor Green
