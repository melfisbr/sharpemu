param()
. (Join-Path $PSScriptRoot 'common.ps1')

$state=Read-RuntimeState
Get-Process SharpEmu -ErrorAction SilentlyContinue|Stop-Process -Force

foreach($dir in @(Get-DeployDirs)){
    $adapterPath=Join-Path $dir 'SharpEmu.BinkNative.dll'
    if(Test-Path -LiteralPath $adapterPath){
        Remove-Item -LiteralPath $adapterPath -Force
        Write-Tag "RemovedAdapter=$adapterPath"
    }
}

if($null -ne $state -and
   $state.PSObject.Properties.Name -contains 'runtime_deployed_paths'){
    foreach($path in @($state.runtime_deployed_paths)){
        if([string]::IsNullOrWhiteSpace([string]$path)){
            continue
        }
        if(Test-Path -LiteralPath $path -PathType Leaf){
            $canRemove=$true
            if($state.PSObject.Properties.Name -contains 'runtime_sha256' -and
               -not[string]::IsNullOrWhiteSpace([string]$state.runtime_sha256)){
                $canRemove=(Get-Sha $path) -eq ([string]$state.runtime_sha256).ToUpperInvariant()
            }
            if($canRemove){
                Remove-Item -LiteralPath $path -Force
                Write-Tag "RemovedDeployedRuntime=$path"
            }else{
                Write-Tag "PreservedRuntimeHashMismatch=$path"
            }
        }
    }
}

Remove-Item -LiteralPath (Get-StatePath) -Force -ErrorAction SilentlyContinue
Write-Tag 'REMOVE ADAPTER PASSED. SharpEmu source repository was never modified.'
