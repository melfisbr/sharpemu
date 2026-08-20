. "$PSScriptRoot\common.ps1"
$p=Paths

try{
    Assert-V740883 $p.Repo
}
catch{
    Write-Host "$script:Tag [ERROR] V74.0.88.3 source baseline missing: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}

$presenter=NL([IO.File]::ReadAllText($p.Presenter))

Write-Host "$script:Tag RepositoryRoot=$($p.Repo)"
Write-Host "$script:Tag PresenterSHA256=$(Sha $p.Presenter)"
Write-Host "$script:Tag v88_3_source_baseline=True"

if($presenter.Contains('SHARPEMU_V74_0_88_5_STABLE_HOST_PLANE_FORMAT')){
    Write-Host "$script:Tag State=AlreadyApplied Ready=0 Applied=1" -ForegroundColor Yellow
    exit 10
}

$checks=[ordered]@{
    v88_uint_contract=$presenter.Contains('SHARPEMU_V74_0_88_UI_BINK_UINT_PLANE_CONTRACT')
    v88_dynamic_luma_format=$presenter.Contains('GetTextureFormat(1, _v74088HostMovieLumaNumberType)')
    v88_dynamic_chroma_format=$presenter.Contains('GetTextureFormat(3, _v74088HostMovieChromaNumberType)')
    v88_luma_lifetime_condition=$presenter.Contains('_v74088CreatedHostMovieLumaNumberType == _v74088HostMovieLumaNumberType')
    v88_chroma_lifetime_condition=$presenter.Contains('_v74088CreatedHostMovieChromaNumberType == _v74088HostMovieChromaNumberType')
    record_texture_uploads=$presenter.Contains('private void RecordTextureUploads(')
    copy_buffer_to_image=$presenter.Contains('_vk.CmdCopyBufferToImage(')
}
$issues=0
foreach($entry in $checks.GetEnumerator()){
    Write-Host "$($entry.Key)=$($entry.Value)"
    if(-not $entry.Value){$issues++}
}
if($issues -gt 0){
    Write-Host "$script:Tag PRECHECK FAILED issues=$issues" -ForegroundColor Red
    exit 3
}

Write-Host "$script:Tag Crash finding: runtime exited 0xC0000005 inside Vk.CmdCopyBufferToImage -> RecordTextureUploads before main_menu.bk2 attached." -ForegroundColor Cyan
Write-Host "$script:Tag Lifetime finding: V88 made host movie VkImage format depend on guest NumberType, adding a new destroy/recreate trigger while translated draws can retain TextureResource.Image." -ForegroundColor Cyan
Write-Host "$script:Tag Repair: keep n4 descriptor discovery, but keep host converted Y/UV images stable as R8Unorm/R8G8Unorm for the active movie lifetime." -ForegroundColor Cyan
Write-Host "$script:Tag State=Ready Ready=1 Applied=0" -ForegroundColor Green
exit 0
