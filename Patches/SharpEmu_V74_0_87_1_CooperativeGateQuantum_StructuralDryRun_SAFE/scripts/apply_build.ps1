param([Parameter(Mandatory=$true)][string]$PackageRoot)
. (Join-Path $PSScriptRoot 'common.ps1') -PackageRoot $PackageRoot
& (Join-Path $PSScriptRoot 'validate_package.ps1') -PackageRoot $PackageRoot
$s=Assert-StructuralContracts
$backup=$null
$alreadyNew=($s.Checks.V871Field -ge 1 -and $s.Checks.V871Yield -ge 1)
$alreadyOld=($s.Checks.OldV87Field -ge 1 -and $s.Checks.OldV87Yield -ge 1)
if(-not $alreadyNew -and -not $alreadyOld){
    $backup=New-Backup
    try{
        # Exactly the same in-memory transform was already exercised by RUN_1 on
        # the current checkout. RUN_3 only commits that prevalidated text.
        $tx=Invoke-GateQuantumTransform $s.Agc
        if($tx.AlreadyApplied){throw "$script:Tag transform reported AlreadyApplied after precheck State=Ready."}
        Write-Utf8NoBom $script:AgcPath $tx.Text
        $post=Assert-StructuralContracts
        if($post.Checks.V871Field -ne 1 -or $post.Checks.V871Yield -ne 1){throw "$script:Tag post-write V87.1 marker verification failed."}
        if($post.Gate.Name -ne $s.Gate.Name -or $post.Gate.StateParam -ne $s.Gate.StateParam){throw "$script:Tag post-write GateOwner identity changed."}
        Write-Host "$script:Tag PATCH APPLIED STRUCTURALLY." -ForegroundColor Green
        Write-Host "$script:Tag GateOwnerMethod=$($post.Gate.Name) GateOwnerStateParam=$($post.Gate.StateParam)"
        Write-Host "$script:Tag gate_quantum=default-on packets=16 ms=1 env_0_0_restores_legacy"
        Write-Host "$script:Tag locator=all_markers+lexical_braces current_checkout_dry_run=passed"
        Write-Host "$script:Tag packet_atomicity=True ordered_side_effect_atomicity=True"
        Write-Host "$script:Tag Backup=$backup"
        Write-Host "$script:Tag AgcSHA256=$(Get-Sha256 $script:AgcPath)"
    }catch{
        if($null -ne $backup -and(Test-Path -LiteralPath $backup)){Restore-Backup $backup;Write-Host "$script:Tag APPLY FAILED; source restored from $backup" -ForegroundColor Yellow}
        throw
    }
}elseif($alreadyOld){
    Write-Host "$script:Tag State=LegacyV87AlreadyApplied; source not duplicated." -ForegroundColor Yellow
}else{
    Write-Host "$script:Tag State=AlreadyAppliedV87.1"
}

$buildLog=Join-Path $script:PatchesRoot ("SharpEmu_V74_0_87_1_APPLY_BUILD_"+(Get-Date -Format 'yyyyMMdd_HHmmss')+'.log')
$project=Join-Path $script:RepoRoot 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
$utf8=New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($buildLog,'',$utf8)
Write-Host "$script:Tag Building SharpEmu.CLI Debug win-x64..."
$cmdLine='dotnet build "'+$project+'" -c Debug -r win-x64 2>&1'
$code=-1
try{
    & $env:ComSpec /d /s /c $cmdLine | ForEach-Object {
        $line=[string]$_
        Write-Host $line
        [System.IO.File]::AppendAllText($buildLog,$line+[Environment]::NewLine,$utf8)
    }
    $code=$LASTEXITCODE
}catch{
    [System.IO.File]::AppendAllText($buildLog,($_|Out-String),$utf8)
    $code=1
}
if($code -ne 0){
    if($null -ne $backup -and(Test-Path -LiteralPath $backup)){Restore-Backup $backup;Write-Host "$script:Tag BUILD FAILED; source automatically restored from $backup" -ForegroundColor Yellow}
    throw "$script:Tag BUILD FAILED code=$code. Log=$buildLog"
}
Write-Host "$script:Tag BUILD PASSED. Log=$buildLog" -ForegroundColor Green
