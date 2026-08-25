param()
. (Join-Path $PSScriptRoot 'common.ps1')
$patches=Get-PatchesRoot
$ptr=Join-Path $patches $script:LastBackupName
if(-not(Test-Path $ptr)){throw "$script:Tag backup pointer missing"}
$b=(Get-Content $ptr -Raw).Trim()
if(-not(Test-Path $b -PathType Container)){throw "$script:Tag backup folder missing: $b"}
Get-Process SharpEmu -ErrorAction SilentlyContinue|Stop-Process -Force
$repo=Get-RepositoryRoot
foreach($rel in @(
    'src\SharpEmu.Libs\Agc\AgcExports.cs',
    'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs',
    'src\SharpEmu.Libs\VideoOut\VulkanHostBufferPool.cs',
    'src\SharpEmu.CLI\DemonsSoulsGpuQueueEnvelopeV74011224.cs'
)){
    Copy-Item (Join-Path $b $rel) (Join-Path $repo $rel) -Force
}
Save-State 6 'ROLLED_BACK' @{backup=$b}
Write-Tag "ROLLBACK PASSED backup=$b"
