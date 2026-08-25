param()
. (Join-Path $PSScriptRoot 'common.ps1');$ptr=Join-Path (Get-PatchesRoot) $script:LastBackupName
$b=(Get-Content $ptr -Raw).Trim();Get-Process SharpEmu -ErrorAction SilentlyContinue|Stop-Process -Force
Copy-Item (Join-Path $b 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs') (Get-Presenter) -Force
Copy-Item (Join-Path $b 'src\SharpEmu.CLI\DemonsSoulsGpuQueueEnvelopeV74011224.cs') (Get-Envelope) -Force
Save-State 6 'ROLLED_BACK' @{backup=$b};Write-Tag "ROLLBACK PASSED backup=$b"
