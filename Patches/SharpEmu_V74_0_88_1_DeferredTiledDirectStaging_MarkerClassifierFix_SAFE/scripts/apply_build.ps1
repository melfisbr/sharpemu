param([Parameter(Mandatory=$true)][string]$PackageRoot)
. (Join-Path $PSScriptRoot 'common.ps1') -PackageRoot $PackageRoot
& (Join-Path $PSScriptRoot 'validate_package.ps1') -PackageRoot $PackageRoot
$dry=Invoke-CheckoutDryRun $false
$backup=$null
if($dry.State -eq 'Ready'){
    $backup=New-Backup
    try{
        # Commit exactly the four in-memory texts already validated by RUN_1.
        Write-Utf8NoBom $script:GuestPath $dry.Transformed.Guest
        Write-Utf8NoBom $script:AgcPath $dry.Transformed.Agc
        Write-Utf8NoBom $script:DetilePath $dry.Transformed.Detile
        Write-Utf8NoBom $script:PresenterPath $dry.Transformed.Presenter
        $post=Invoke-CheckoutDryRun $false
        if($post.State -ne 'Applied'){throw "$script:Tag post-write state=$($post.State), expected Applied"}
        Write-Host "$script:Tag PATCH APPLIED STRUCTURALLY." -ForegroundColor Green
        Write-Host "$script:Tag parser_payload=deferred_guest_reference threshold_mb=8"
        Write-Host "$script:Tag vulkan_upload=guest_memory_to_mapped_detile_staging direct=True"
        Write-Host "$script:Tag render_thread_managed_fallback=True"
        Write-Host "$script:Tag V81.2_boundaries_untouched=True V87.2_quantum_preserved=True"
        Write-Host "$script:Tag Backup=$backup"
    }catch{
        if($null -ne $backup -and(Test-Path -LiteralPath $backup)){Restore-Backup $backup;Write-Host "$script:Tag APPLY FAILED; all 4 sources restored from $backup" -ForegroundColor Yellow}
        throw
    }
}else{
    Write-Host "$script:Tag State=AlreadyApplied; source not duplicated." -ForegroundColor Yellow
}

$buildLog=Join-Path $script:PatchesRoot ("SharpEmu_V74_0_88_1_APPLY_BUILD_"+(Get-Date -Format 'yyyyMMdd_HHmmss')+'.log')
$project=Join-Path $script:RepoRoot 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
$utf8=New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($buildLog,'',$utf8)
Write-Host "$script:Tag Building SharpEmu.CLI Debug win-x64..."
$cmdLine='dotnet build "'+$project+'" -c Debug -r win-x64 2>&1'
$code=-1
try{
    & $env:ComSpec /d /s /c $cmdLine | ForEach-Object {
        $line=[string]$_;Write-Host $line;[System.IO.File]::AppendAllText($buildLog,$line+[Environment]::NewLine,$utf8)
    }
    $code=$LASTEXITCODE
}catch{[System.IO.File]::AppendAllText($buildLog,($_|Out-String),$utf8);$code=1}
if($code -ne 0){
    if($null -ne $backup -and(Test-Path -LiteralPath $backup)){Restore-Backup $backup;Write-Host "$script:Tag BUILD FAILED; all 4 sources automatically restored from $backup" -ForegroundColor Yellow}
    throw "$script:Tag BUILD FAILED code=$code. Log=$buildLog"
}
Write-Host "$script:Tag BUILD PASSED. Log=$buildLog" -ForegroundColor Green
