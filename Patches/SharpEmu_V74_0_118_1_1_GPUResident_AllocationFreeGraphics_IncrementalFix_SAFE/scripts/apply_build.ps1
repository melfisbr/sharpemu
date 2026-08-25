param()
. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'precheck.ps1')
$s=Read-State 2

$repo=Get-RepositoryRoot
$patches=Get-PatchesRoot
$p=Get-Presenter
$q=Get-Envelope

$expectedPresenterSha=[string]$s.presenter_sha256
$expectedEnvelopeSha=[string]$s.envelope_sha256
if((Get-Sha $p) -ne $expectedPresenterSha -or
   (Get-Sha $q) -ne $expectedEnvelopeSha){
    throw "$script:Tag source changed after precheck"
}

Get-Process SharpEmu -ErrorAction SilentlyContinue|Stop-Process -Force

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$b=Join-Path $repo ".sharpemu-hotfix-backup\V118_1_1_IncrementalFromV1180_1_$stamp"
$bp=Join-Path $b 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$bq=Join-Path $b 'src\SharpEmu.CLI\DemonsSoulsGpuQueueEnvelopeV74011224.cs'
New-Item -ItemType Directory -Path (Split-Path $bp) -Force|Out-Null
New-Item -ItemType Directory -Path (Split-Path $bq) -Force|Out-Null
Copy-Item $p $bp -Force
Copy-Item $q $bq -Force
Set-Content (Join-Path $patches $script:LastBackupName) $b -Encoding UTF8

$tmp=Join-Path $env:TEMP "v11811_apply_$stamp"
New-Item -ItemType Directory -Path $tmp -Force|Out-Null
try{
    $pf=Join-Path $tmp 'VulkanVideoPresenter.cs'
    $qf=Join-Path $tmp 'DemonsSoulsGpuQueueEnvelope.cs'

    & (Join-Path $PSScriptRoot 'patch_v1181.ps1') `
        -PresenterSource $p `
        -EnvelopeSource $q `
        -OutputPresenter $pf `
        -OutputEnvelope $qf

    Assert-V11811 $pf $qf

    Copy-Item $pf $p -Force
    Copy-Item $qf $q -Force
    Assert-V11811 $p $q

    $log=Join-Path $patches "SharpEmu_V74_0_118_1_1_BUILD_$stamp.log"
    Push-Location $repo
    try{
        dotnet build `
            (Join-Path $repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj') `
            -c Release -r win-x64 -t:Rebuild *>&1 |
            Tee-Object -FilePath $log
        $ec=$LASTEXITCODE
    }finally{Pop-Location}

    if($ec-ne0){
        throw "$script:Tag build failed exit=$ec"
    }

    Save-State 3 'APPLY_BUILD_PASSED' @{
        presenter=$p
        presenter_sha256=(Get-Sha $p)
        envelope=$q
        envelope_sha256=(Get-Sha $q)
        backup=$b
        build_log=$log
    }
    Write-Tag "APPLY/REBUILD PASSED backup=$b"
}catch{
    Copy-Item $bp $p -Force
    Copy-Item $bq $q -Force
    Write-Tag 'FAILED; exact pre-V118.1.1 V118.0.1 sources restored.'
    throw
}finally{
    if(Test-Path $tmp){Remove-Item $tmp -Recurse -Force}
}
