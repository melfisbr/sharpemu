param()
. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'precheck.ps1')
$state=Get-BaselineState
if($state.State -eq 'installed'){Write-Tag 'V3.12 already installed; source write/build skipped.'; exit 0}
$repo=Get-RepositoryRoot; $patches=Get-PatchesRoot; $stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$backupRoot=Join-Path $repo ".sharpemu-hotfix-backup\V74_0_118_7_6_3_12_$stamp"
Get-Process SharpEmu -ErrorAction SilentlyContinue|Stop-Process -Force
try{
    foreach($entry in $script:Files.GetEnumerator()){
        $source=Get-SourcePath $entry.Value.Rel
        $backup=Join-Path $backupRoot $entry.Value.Rel
        New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force|Out-Null
        Copy-Item -LiteralPath $source -Destination $backup -Force
    }
    Set-Content -LiteralPath (Get-BackupPointer) -Value $backupRoot -Encoding UTF8
    foreach($entry in $script:Files.GetEnumerator()){
        $payload=Get-PayloadPath $entry.Value.Rel; $target=Get-SourcePath $entry.Value.Rel
        Copy-Item -LiteralPath $payload -Destination $target -Force
        $actual=Get-Sha $target
        if($actual -ne $entry.Value.After){throw "$script:Tag installed hash mismatch $($entry.Key) expected=$($entry.Value.After) actual=$actual"}
    }
    $buildLog=Join-Path $patches "SharpEmu_V74_0_118_7_6_3_12_1_BUILD_$stamp.log"
    Push-Location $repo
    $saved=$ErrorActionPreference
    try{
        $ErrorActionPreference='Continue'
        & dotnet build .\src\SharpEmu.CLI\SharpEmu.CLI.csproj -c Release -r win-x64 --no-incremental *>&1|Tee-Object -FilePath $buildLog
        $exitCode=$LASTEXITCODE
    }finally{$ErrorActionPreference=$saved;Pop-Location}
    if($exitCode -ne 0){throw "$script:Tag build failed exit=$exitCode log=$buildLog"}
    [ordered]@{
      version=$script:Version;installed_at=(Get-Date).ToString('o');backup=$backupRoot;build_log=$buildLog;
      hostapi_before=$script:Files.HostApi.Before;hostapi_after=$script:Files.HostApi.After;
      external_before=$script:Files.RadExternal.Before;external_after=$script:Files.RadExternal.After;
      presenter_before=$script:Files.Presenter.Before;presenter_after=$script:Files.Presenter.After;
      integration='official-rad-frame-source-to-guest-bink-yuv';final_owner='sceVideoOutSubmitFlip';standalone_default=$true
    }|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Get-StatePath) -Encoding UTF8
    Write-Tag "APPLY/BUILD PASSED backup=$backupRoot build_log=$buildLog"
}catch{
    foreach($entry in $script:Files.GetEnumerator()){
        $backup=Join-Path $backupRoot $entry.Value.Rel; $target=Get-SourcePath $entry.Value.Rel
        if(Test-Path -LiteralPath $backup){Copy-Item -LiteralPath $backup -Destination $target -Force}
    }
    Remove-Item -LiteralPath (Get-StatePath) -Force -ErrorAction SilentlyContinue
    throw "$script:Tag APPLY/BUILD failed; all 3 source files restored. $($_.Exception.Message)"
}
