param()
. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'precheck.ps1')
$state=Read-State 2
$repo=Get-RepositoryRoot
$patches=Get-PatchesRoot
$presenter=Get-PresenterSource
if((Get-Sha $presenter)-ne[string]$state.presenter_sha256){
    throw "$script:Tag source changed after precheck"
}

Get-Process SharpEmu -ErrorAction SilentlyContinue|Stop-Process -Force
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$backup=Join-Path $repo ".sharpemu-hotfix-backup\V120_0_DrawFeed_$stamp"
$backupPresenter=Join-Path $backup 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
New-Item -ItemType Directory -Path (Split-Path $backupPresenter -Parent) -Force|Out-Null
Copy-Item -LiteralPath $presenter -Destination $backupPresenter -Force
Set-Content -LiteralPath (Join-Path $patches $script:LastBackupName) -Value $backup -Encoding UTF8

$tmp=Join-Path $env:TEMP ('v120_apply_'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force|Out-Null
$out=Join-Path $tmp 'VulkanVideoPresenter.cs'
try{
    & (Join-Path $PSScriptRoot 'patch_v120.ps1') -Source $presenter -Output $out
    Assert-V120Markers $out
    Copy-Item -LiteralPath $out -Destination $presenter -Force
    Assert-V120Markers $presenter

    $buildLog=Join-Path $patches "SharpEmu_V74_0_120_0_BUILD_$stamp.log"
    $project=Join-Path $repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
    Push-Location $repo
    try{
        & dotnet build $project -c Release -r win-x64 -t:Rebuild *>&1|
            Tee-Object -FilePath $buildLog
        $exitCode=$LASTEXITCODE
    }finally{
        Pop-Location
    }
    if($exitCode-ne0){
        throw "$script:Tag build failed exit=$exitCode"
    }

    Save-State 3 'APPLY_BUILD_PASSED' @{
        presenter=$presenter
        presenter_sha256=(Get-Sha $presenter)
        backup=$backup
        build_log=$buildLog
    }
    Write-Tag "APPLY/REBUILD PASSED backup=$backup"
}catch{
    Copy-Item -LiteralPath $backupPresenter -Destination $presenter -Force
    Write-Tag 'APPLY/BUILD failed; exact pre-V120 source restored.'
    throw
}finally{
    if(Test-Path $tmp){Remove-Item $tmp -Recurse -Force}
}
