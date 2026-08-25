param()
. (Join-Path $PSScriptRoot 'common.ps1')
$repo=Get-RepositoryRoot
$pointer=Get-BackupPointer
if(-not(Test-Path -LiteralPath $pointer -PathType Leaf)){throw "$script:Tag backup pointer missing"}
$backupRoot=(Get-Content -LiteralPath $pointer -Raw).Trim()
$hostBackup=Join-Path $backupRoot 'HostMovieBridge.cs'
$hostTarget=Join-Path $repo $script:RelativeHost
if(-not(Test-Path -LiteralPath $hostBackup -PathType Leaf)){throw "$script:Tag HostMovieBridge backup missing"}
Get-Process SharpEmu -ErrorAction SilentlyContinue|Stop-Process -Force
Copy-Item -LiteralPath $hostBackup -Destination $hostTarget -Force
foreach($entry in @(
    [pscustomobject]@{Saved=(Join-Path $backupRoot 'Debug_SharpEmu.BinkNative.dll');Target=(Join-Path $repo 'artifacts\bin\Debug\net10.0\win-x64\plugins\bink2\SharpEmu.BinkNative.dll')},
    [pscustomobject]@{Saved=(Join-Path $backupRoot 'Release_SharpEmu.BinkNative.dll');Target=(Join-Path $repo 'artifacts\bin\Release\net10.0\win-x64\plugins\bink2\SharpEmu.BinkNative.dll')}
)){
    if(Test-Path -LiteralPath $entry.Saved -PathType Leaf){
        New-Item -ItemType Directory -Path (Split-Path -Parent $entry.Target) -Force|Out-Null
        Copy-Item -LiteralPath $entry.Saved -Destination $entry.Target -Force
    }
}
Remove-Item -LiteralPath (Get-StatePath) -Force -ErrorAction SilentlyContinue
Write-Tag "ROLLBACK PASSED host_sha=$(Get-Sha $hostTarget) backup=$backupRoot"
