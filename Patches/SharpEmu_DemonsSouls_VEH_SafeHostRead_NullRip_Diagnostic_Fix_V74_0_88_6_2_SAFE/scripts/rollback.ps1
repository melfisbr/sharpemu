. "$PSScriptRoot\common.ps1"
$p=Paths
$last=Join-Path (PackageRoot) 'LAST_BACKUP.txt'
if(-not(Test-Path -LiteralPath $last)){
    Write-Host "$script:Tag [ERROR] LAST_BACKUP.txt not found." -ForegroundColor Red
    exit 1
}
$vals=@{}
foreach($line in Get-Content -LiteralPath $last){
    $parts=$line.Split('=',2)
    if($parts.Count -eq 2){$vals[$parts[0]]=$parts[1]}
}
if(-not $vals.ContainsKey('Source') -or -not $vals.ContainsKey('Backup')){
    Write-Host "$script:Tag [ERROR] LAST_BACKUP.txt malformed." -ForegroundColor Red
    exit 2
}
Copy-Item -LiteralPath $vals['Backup'] -Destination $vals['Source'] -Force
Write-Host "$script:Tag ROLLBACK COMPLETED. Source=$($vals['Source'])" -ForegroundColor Yellow
