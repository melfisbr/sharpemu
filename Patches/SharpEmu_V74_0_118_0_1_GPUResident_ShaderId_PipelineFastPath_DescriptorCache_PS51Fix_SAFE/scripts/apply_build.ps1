param()
. (Join-Path $PSScriptRoot 'common.ps1')
& (Join-Path $PSScriptRoot 'precheck.ps1');$s=Read-State 2
$repo=Get-RepositoryRoot;$patches=Get-PatchesRoot;$p=Get-Presenter;$q=Get-Envelope
if((Get-Sha $p)-ne$s.presenter_sha256-or(Get-Sha $q)-ne$s.envelope_sha256){throw "$script:Tag source changed"}
Get-Process SharpEmu -ErrorAction SilentlyContinue|Stop-Process -Force
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$b=Join-Path $repo ".sharpemu-hotfix-backup\V118_0_1_GPUResidentShader_$stamp"
$bp=Join-Path $b 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$bq=Join-Path $b 'src\SharpEmu.CLI\DemonsSoulsGpuQueueEnvelopeV74011224.cs'
New-Item -ItemType Directory (Split-Path $bp) -Force|Out-Null;New-Item -ItemType Directory (Split-Path $bq) -Force|Out-Null
Copy-Item $p $bp;Copy-Item $q $bq;Set-Content (Join-Path $patches $script:LastBackupName) $b
$tmp=Join-Path $env:TEMP "v1180_apply_$stamp";New-Item -ItemType Directory $tmp|Out-Null
try{
 $p16=Join-Path $tmp 'p16.cs';$q16=Join-Path $tmp 'q16.cs'
 & (Join-Path $PSScriptRoot 'patch_v11716_base.ps1') -PresenterSource $p -EnvelopeSource $q -OutputPresenter $p16 -OutputEnvelope $q16
 $pf=Join-Path $tmp 'pf.cs';$qf=Join-Path $tmp 'qf.cs'
 & (Join-Path $PSScriptRoot 'patch_v1180.ps1') -PresenterSource $p16 -EnvelopeSource $q16 -OutputPresenter $pf -OutputEnvelope $qf
 Assert-V1180 $pf $qf
 Copy-Item $pf $p -Force;Copy-Item $qf $q -Force
 $log=Join-Path $patches "SharpEmu_V74_0_118_0_1_BUILD_$stamp.log"
 Push-Location $repo
 try{dotnet build (Join-Path $repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj') -c Release -r win-x64 -t:Rebuild *>&1|Tee-Object $log;$ec=$LASTEXITCODE}finally{Pop-Location}
 if($ec-ne0){throw "$script:Tag build failed $ec"}
 Save-State 3 'APPLY_BUILD_PASSED' @{presenter=$p;presenter_sha256=(Get-Sha $p);envelope=$q;envelope_sha256=(Get-Sha $q);backup=$b;build_log=$log}
 Write-Tag "APPLY/REBUILD PASSED backup=$b"
}catch{Copy-Item $bp $p -Force;Copy-Item $bq $q -Force;Write-Tag 'FAILED; V117.14 exact source restored';throw}
finally{Remove-Item $tmp -Recurse -Force}
