. "$PSScriptRoot\common.ps1"
$pkg=PackageRoot; $repo=RepoRoot; $patches=Patches; $src=ImeDialogSource; $payload=PayloadSource
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'precheck.ps1')
$pre=$LASTEXITCODE
if($pre -ne 0 -and $pre -ne 10){ exit $pre }
$backup=$null
if($pre -ne 10){
    $stamp=Get-Date -Format yyyyMMdd_HHmmss
    $backup=Join-Path $repo ('.sharpemu-hotfix-backup\ImeDialogHostTextInput_V74_0_85_1_'+$stamp)
    New-Item -ItemType Directory -Force $backup | Out-Null
    Copy-Item -LiteralPath $src -Destination (Join-Path $backup 'ImeDialogExports.cs') -Force
    Set-Content -LiteralPath (Join-Path $pkg 'LAST_BACKUP.txt') -Value $backup -Encoding UTF8
    try{
        Copy-Item -LiteralPath $payload -Destination $src -Force
        $post=[IO.File]::ReadAllText($src)
        foreach($m in @('SHARPEMU_V74_0_85_1_IME_DIALOG_HOST_TEXT_INPUT','host_panel_open','text_commit','StatusRunning')){
            if(-not $post.Contains($m)){ throw "post-apply marker missing: $m" }
        }
        if($post.Contains('DefaultInputText = "Sharp"')){ throw 'legacy immediate autofill still present after apply' }
        Write-Host '[V74.0.85.1] IME DIALOG SOURCE INSTALLED.' -ForegroundColor Green
        Write-Host "PostSHA256=$(Sha $src)"
        Write-Host "Backup=$backup"
    } catch {
        $old=Join-Path $backup 'ImeDialogExports.cs'
        if(Test-Path $old){ Copy-Item -LiteralPath $old -Destination $src -Force }
        Write-Host "[V74.0.85.1][ERROR] APPLY FAILED: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host '[V74.0.85.1] SAFE rollback completed.' -ForegroundColor Yellow
        exit 1
    }
}
Get-Process SharpEmu -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
$log=Join-Path $patches ('SharpEmu_V74_0_85_1_IME_DIALOG_BUILD_'+(Get-Date -Format yyyyMMdd_HHmmss)+'.log')
& dotnet build (CliProject) -c Debug -r win-x64 2>&1 | Tee-Object -FilePath $log
$code=$LASTEXITCODE
if($code -ne 0){
    if($backup){ $old=Join-Path $backup 'ImeDialogExports.cs'; if(Test-Path $old){ Copy-Item -LiteralPath $old -Destination $src -Force } }
    Write-Host '[V74.0.85.1][ERROR] BUILD FAILED; SAFE rollback completed.' -ForegroundColor Red
    exit $code
}
Write-Host '[V74.0.85.1] APPLY + BUILD PASSED.' -ForegroundColor Green
Write-Host "BuildLog=$log"
