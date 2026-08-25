param()
. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'precheck.ps1')
$state=Assert-Baseline

if($state.Already){
    Write-Tag 'V3.12 already installed; source write skipped.'
    exit 0
}

$repo=Get-RepositoryRoot
$patches=Get-PatchesRoot
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$backupRoot=Join-Path $repo ".sharpemu-hotfix-backup\V74_0_118_7_6_3_12_$stamp"

$targets=@(
    [pscustomobject]@{
        Target=$state.HostApi
        Payload=(Get-HostPayload)
        Relative=$script:RelativeHostApi
        ExpectedAfter=$script:PayloadHostApiSha
    },
    [pscustomobject]@{
        Target=$state.Presenter
        Payload=(Get-PresenterPayload)
        Relative=$script:RelativePresenter
        ExpectedAfter=$script:PayloadPresenterSha
    }
)

foreach($item in $targets){
    $backup=Join-Path $backupRoot $item.Relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force|Out-Null
    Copy-Item -LiteralPath $item.Target -Destination $backup -Force
}
Set-Content -LiteralPath (Get-BackupPointer) -Value $backupRoot -Encoding UTF8

Get-Process SharpEmu -ErrorAction SilentlyContinue|Stop-Process -Force

try{
    foreach($item in $targets){
        Copy-Item -LiteralPath $item.Payload -Destination $item.Target -Force
        $installedSha=Get-Sha $item.Target
        if($installedSha -ne $item.ExpectedAfter){
            throw "$script:Tag installed SHA mismatch path=$($item.Target) expected=$($item.ExpectedAfter) actual=$installedSha"
        }
    }

    $buildLog=Join-Path $patches "SharpEmu_V74_0_118_7_6_3_12_BUILD_$stamp.log"
    Push-Location $repo
    $savedErrorAction=$ErrorActionPreference
    try{
        $ErrorActionPreference='Continue'
        & dotnet build .\src\SharpEmu.CLI\SharpEmu.CLI.csproj -c Release -r win-x64 --no-incremental *>&1 |
            Tee-Object -FilePath $buildLog
        $buildExit=$LASTEXITCODE
    }finally{
        $ErrorActionPreference=$savedErrorAction
        Pop-Location
    }

    if($buildExit -ne 0){
        throw "$script:Tag build failed exit=$buildExit log=$buildLog"
    }

    [ordered]@{
        version=$script:Version
        installed_at=(Get-Date).ToString('o')
        backup=$backupRoot
        build_log=$buildLog
        hostapi_before=$script:ExpectedHostApiSha
        hostapi_after=$script:PayloadHostApiSha
        presenter_before=$script:ExpectedPresenterSha
        presenter_after=$script:PayloadPresenterSha
        partial_preserved=$script:ExpectedPartialSha
        shader_preserved=$script:ExpectedShaderSha
        ampr_preserved=$script:ExpectedAmprSha
        architecture='official RAD texture source -> guest YUV -> guest final framebuffer'
    }|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Get-StatePath) -Encoding UTF8

    Write-Tag "APPLY/BUILD PASSED backup=$backupRoot build_log=$buildLog"
}catch{
    foreach($item in $targets){
        $backup=Join-Path $backupRoot $item.Relative
        if(Test-Path -LiteralPath $backup){
            Copy-Item -LiteralPath $backup -Destination $item.Target -Force
        }
    }
    Remove-Item -LiteralPath (Get-StatePath) -Force -ErrorAction SilentlyContinue
    throw "$script:Tag APPLY/BUILD failed; HostApi/Presenter restored. $($_.Exception.Message)"
}
