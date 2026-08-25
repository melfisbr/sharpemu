param()
. (Join-Path $PSScriptRoot 'common.ps1')
$state=Join-Path (PatchesRoot) 'SharpEmu_V74_0_117_1_1_SCRIPT_REPAIR_STATE.txt'
if(-not(Test-Path -LiteralPath $state)){throw "$script:Tag repair state missing"}
$data=@{}
Get-Content -LiteralPath $state|ForEach-Object{
    if($_ -match '^(.*?)=(.*)$'){$data[$matches[1]]=$matches[2]}
}
$backup=$data['backup']
if([string]::IsNullOrWhiteSpace($backup)-or-not(Test-Path -LiteralPath $backup)){
    throw "$script:Tag script backup not found"
}
$o=OriginalRoot
Get-ChildItem -LiteralPath $backup -File -Filter '*.ps1'|ForEach-Object{
    $dest=Join-Path (Join-Path $o 'scripts') $_.Name
    Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
}
Parse-PowerShellTree $o
Write-Tag "SCRIPT-ONLY ROLLBACK PASSED backup=$backup"
