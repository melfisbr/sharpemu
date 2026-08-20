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

Write-Host "$script:Tag DIAGNOSTIC START" -ForegroundColor Cyan
Write-Host "safe_host_qword_marker=$($read.Text.Contains('SHARPEMU_V74_0_88_6_VEH_SAFE_HOST_QWORD'))"
Write-Host "reject_trace=$($read.Text.Contains('[V74.0.88.6][VEH_SAFE_READ_REJECT]'))"
Write-Host "virtual_query_before_read=$($body.IndexOf('VirtualQuery(') -ge 0 -and $body.IndexOf('VirtualQuery(') -lt $body.IndexOf('Marshal.ReadInt64'))"
Write-Host "commit_check=$($body.Contains('MemCommitV740886'))"
Write-Host "noaccess_guard_check=$($body.Contains('PageNoAccessV740886'))"
Write-Host "page_guard_check=$($body.Contains('PageGuardV740886'))"
Write-Host "qword_boundary_check=$($body.Contains('regionEndV740886 - sizeof(ulong)'))"
Write-Host "vectored_handler_preserved=$(-not $handler.Text.Contains('SHARPEMU_V74_0_88_6_NULL_RIP_SKIP'))"
Write-Host "v88_5_presenter_preserved=$(Test-Path -LiteralPath $p.Presenter)"
Write-Host "v88_3_hostmovie_preserved=$(Test-Path -LiteralPath $p.HostMovie)"
Write-Host "v88_inwindow_ime_preserved=$(Test-Path -LiteralPath $p.ImeOverlay)"
Write-Host "build_artifact_exists=$(Test-Path -LiteralPath $p.Exe)"
Write-Host "$script:Tag TryReadHostQwordSource=$($read.File)"
Write-Host "$script:Tag VectoredHandlerSource=$($handler.File)"
Write-Host "$script:Tag DIAGNOSTIC PASSED." -ForegroundColor Green
