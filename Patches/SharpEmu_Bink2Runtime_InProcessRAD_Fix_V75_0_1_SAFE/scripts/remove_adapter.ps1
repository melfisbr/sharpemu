param()
. (Join-Path $PSScriptRoot 'common.ps1')
Get-Process SharpEmu -ErrorAction SilentlyContinue|Stop-Process -Force
foreach($dir in @(Get-DeployDirs)){
    $path=Join-Path $dir 'SharpEmu.BinkNative.dll'
    if(Test-Path -LiteralPath $path){
        Remove-Item -LiteralPath $path -Force
        Write-Tag "Removed=$path"
    }
}
Remove-Item -LiteralPath (Get-StatePath) -Force -ErrorAction SilentlyContinue
Write-Tag 'REMOVE ADAPTER PASSED. Source repository was never modified.'
