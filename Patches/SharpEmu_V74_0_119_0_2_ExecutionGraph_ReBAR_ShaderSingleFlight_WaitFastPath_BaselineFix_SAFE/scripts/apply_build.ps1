param()
. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'precheck.ps1')
$s=Read-State 2
$repo=Get-RepositoryRoot
$patches=Get-PatchesRoot
$a=Get-AgcSource;$w=Get-GpuWaitRegistrySource;$p=Get-PresenterSource;$h=Get-HostPoolSource;$q=Get-EnvelopeSource

foreach($pair in @(
    @($a,[string]$s.agc_sha256),
    @($w,[string]$s.gpu_wait_registry_sha256),
    @($p,[string]$s.presenter_sha256),
    @($h,[string]$s.host_pool_sha256),
    @($q,[string]$s.envelope_sha256)
)){
    if((Get-Sha $pair[0])-ne$pair[1]){throw "$script:Tag source changed after precheck: $($pair[0])"}
}

Get-Process SharpEmu -ErrorAction SilentlyContinue|Stop-Process -Force
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$backup=Join-Path $repo ".sharpemu-hotfix-backup\V119_0_2_ExecutionGraph_$stamp"
$rels=[ordered]@{
    agc='src\SharpEmu.Libs\Agc\AgcExports.cs'
    presenter='src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
    hostpool='src\SharpEmu.Libs\VideoOut\VulkanHostBufferPool.cs'
    envelope='src\SharpEmu.CLI\DemonsSoulsGpuQueueEnvelopeV74011224.cs'
}
foreach($rel in $rels.Values){
    $dst=Join-Path $backup $rel
    New-Item -ItemType Directory (Split-Path $dst -Parent) -Force|Out-Null
}
Copy-Item $a (Join-Path $backup $rels.agc) -Force
Copy-Item $p (Join-Path $backup $rels.presenter) -Force
Copy-Item $h (Join-Path $backup $rels.hostpool) -Force
Copy-Item $q (Join-Path $backup $rels.envelope) -Force
Set-Content (Join-Path $patches $script:LastBackupName) $backup -Encoding UTF8

$tmp=Join-Path $env:TEMP ('v1190_apply_'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $tmp -Force|Out-Null
$oa=Join-Path $tmp 'AgcExports.cs'
$op=Join-Path $tmp 'VulkanVideoPresenter.cs'
$oh=Join-Path $tmp 'VulkanHostBufferPool.cs'
$oq=Join-Path $tmp 'Envelope.cs'
try{
    & (Join-Path $PSScriptRoot 'patch_v1190.ps1') `
        -AgcSource $a -PresenterSource $p -HostPoolSource $h -EnvelopeSource $q `
        -OutputAgc $oa -OutputPresenter $op -OutputHostPool $oh -OutputEnvelope $oq
    Assert-V1190Markers $oa $op $oh $oq

    Copy-Item $oa $a -Force
    Copy-Item $op $p -Force
    Copy-Item $oh $h -Force
    Copy-Item $oq $q -Force

    $log=Join-Path $patches "SharpEmu_V74_0_119_0_2_BUILD_$stamp.log"
    Push-Location $repo
    try{
        & dotnet build (Join-Path $repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj') `
            -c Release -r win-x64 -t:Rebuild *>&1|Tee-Object -FilePath $log
        $ec=$LASTEXITCODE
    }finally{Pop-Location}
    if($ec-ne0){throw "$script:Tag rebuild failed exit=$ec"}

    Save-State 3 'APPLY_BUILD_PASSED' @{
        agc=$a;agc_sha256=(Get-Sha $a)
        gpu_wait_registry=$w;gpu_wait_registry_sha256=(Get-Sha $w)
        presenter=$p;presenter_sha256=(Get-Sha $p)
        host_pool=$h;host_pool_sha256=(Get-Sha $h)
        envelope=$q;envelope_sha256=(Get-Sha $q)
        backup=$backup;build_log=$log
    }
    Write-Tag "APPLY/REBUILD PASSED backup=$backup"
}catch{
    Copy-Item (Join-Path $backup $rels.agc) $a -Force
    Copy-Item (Join-Path $backup $rels.presenter) $p -Force
    Copy-Item (Join-Path $backup $rels.hostpool) $h -Force
    Copy-Item (Join-Path $backup $rels.envelope) $q -Force
    Write-Tag 'FAILED; exact V118.0.1 sources restored.'
    throw
}finally{
    if(Test-Path $tmp){Remove-Item $tmp -Recurse -Force}
}
