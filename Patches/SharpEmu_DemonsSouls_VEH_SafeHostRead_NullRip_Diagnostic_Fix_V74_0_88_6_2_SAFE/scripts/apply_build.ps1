. "$PSScriptRoot\common.ps1"
$p=Paths
$pkg=PackageRoot
$patches=Patches

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'precheck.ps1')
$pre=$LASTEXITCODE
if($pre -ne 0 -and $pre -ne 10){exit $pre}

$backup=$null
$read=$null
if($pre -ne 10){
    try{
        $read=Locate-TryReadHostQword
        $stamp=Get-Date -Format yyyyMMdd_HHmmss
        $backup=Join-Path $p.Repo ('.sharpemu-hotfix-backup\VehSafeHostReadV740886_'+$stamp)
        New-Item -ItemType Directory -Force $backup|Out-Null

        $backupFile=Join-Path $backup ([IO.Path]::GetFileName($read.File))
        Copy-Item -LiteralPath $read.File -Destination $backupFile -Force
        Set-Content -LiteralPath (Join-Path $pkg 'LAST_BACKUP.txt') -Value @(
            "Source=$($read.File)"
            "Backup=$backupFile"
        ) -Encoding UTF8

        $patched=Apply-SafeHostQwordV740886 $read.Text $read.Span
        WritePreserving $read.File $patched
        $assert=Assert-V740886

        Write-Host "$script:Tag SOURCE PATCH APPLIED (safe-read body + unsafe method declaration)." -ForegroundColor Green
        Write-Host "$script:Tag PatchedFile=$($read.File)"
        Write-Host "$script:Tag PostSHA256=$(Sha $read.File)"
        Write-Host "$script:Tag Backup=$backupFile"
    }
    catch{
        if($backup -and $read){
            $backupFile=Join-Path $backup ([IO.Path]::GetFileName($read.File))
            if(Test-Path -LiteralPath $backupFile){
                Copy-Item -LiteralPath $backupFile -Destination $read.File -Force
            }
        }
        Export-MethodDiagnostic ("apply failed: "+$_.Exception.Message)|Out-Null
        Write-Host "$script:Tag [ERROR] APPLY FAILED: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "$script:Tag SAFE rollback completed." -ForegroundColor Yellow
        exit 1
    }
}

Get-Process SharpEmu -ErrorAction SilentlyContinue|Stop-Process -Force -ErrorAction SilentlyContinue

$log=Join-Path $patches ('SharpEmu_V74_0_88_6_2_VEH_SAFE_HOST_READ_BUILD_'+(Get-Date -Format yyyyMMdd_HHmmss)+'.log')
& dotnet build $p.Cli -c Debug -r win-x64 2>&1|Tee-Object -FilePath $log
$code=$LASTEXITCODE

if($code -ne 0){
    if($backup -and $read){
        $backupFile=Join-Path $backup ([IO.Path]::GetFileName($read.File))
        if(Test-Path -LiteralPath $backupFile){
            Copy-Item -LiteralPath $backupFile -Destination $read.File -Force
        }
    }
    Write-Host "$script:Tag [ERROR] BUILD FAILED; SAFE rollback completed." -ForegroundColor Red
    exit $code
}

Write-Host "$script:Tag APPLY + BUILD PASSED." -ForegroundColor Green
Write-Host "$script:Tag BuildLog=$log"
