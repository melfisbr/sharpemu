param([Parameter(Mandatory=$true)][string]$PackageRoot)
. (Join-Path $PSScriptRoot 'common.ps1') -PackageRoot $PackageRoot
& (Join-Path $PSScriptRoot 'validate_package.ps1') -PackageRoot $PackageRoot
$s=Assert-StructuralContracts
$p=$s.Presenter;$nl=if($p.Contains("`r`n")){"`r`n"}else{"`n"};$backup=$null
$marker='SHARPEMU_V74_0_84_SUBMISSION_HEADROOM_ADAPTIVE'
if(-not $p.Contains($marker)){
  $backup=New-Backup
  try{
    $f=Get-DeclarationSegment $p '_kytyComputeSubmissionFairnessV74033';if($null -eq $f){throw "$script:Tag fairness declaration missing."}
    $ls=$p.LastIndexOf($nl,$f.Start,[System.StringComparison]::Ordinal);if($ls -lt 0){$ls=0}else{$ls+=$nl.Length}
    $indent=[regex]::Match($p.Substring($ls,$f.Start-$ls),'^\s*').Value
    $p=$p.Insert($ls,$indent+'// '+$marker+$nl+$indent+'// Existing soft target stays 8; existing emergency hard ceiling stays 24.'+$nl)
    $f=Get-DeclarationSegment $p '_kytyComputeSubmissionFairnessV74033'
    if(-not($f.Text.Contains('!string.Equals') -and $f.Text.Contains('"0"'))){
      if($f.Text.Contains('string.Equals') -and -not $f.Text.Contains('!string.Equals') -and $f.Text.Contains('"1"')){
        $rep=$f.Text.Replace('string.Equals(','!string.Equals(');$rep=[regex]::Replace($rep,'(?m)^(\s*)"1",\s*$','$1"0",');if($rep -eq $f.Text){throw "$script:Tag fairness transform made no change."};$p=$p.Remove($f.Start,$f.Length).Insert($f.Start,$rep)
      }else{throw "$script:Tag fairness declaration unknown; refusing rewrite."}
    }
    $ad=Get-DeclarationSegment $p '_adaptiveUnifiedComputeV7405616';if($null -eq $ad){throw "$script:Tag adaptive declaration missing."}
    if(-not($ad.Text.Contains('!string.Equals') -and $ad.Text.Contains('"0"'))){
      if($ad.Text.Contains('string.Equals') -and -not $ad.Text.Contains('!string.Equals') -and $ad.Text.Contains('"1"')){
        $arep=$ad.Text.Replace('string.Equals(','!string.Equals(');$arep=[regex]::Replace($arep,'(?m)^(\s*)"1",\s*$','$1"0",');if($arep -eq $ad.Text){throw "$script:Tag adaptive transform made no change."};$p=$p.Remove($ad.Start,$ad.Length).Insert($ad.Start,$arep)
      }else{throw "$script:Tag adaptive declaration unknown; refusing rewrite."}
    }
    if(-not $p.Contains('SHARPEMU_V74_0_81_2_COMPUTE_START_FENCE_BOUNDARY') -or -not $p.Contains('SHARPEMU_V74_0_81_2_RESOURCE_UPLOAD_FENCE_BOUNDARY')){throw "$script:Tag V81.2 Vulkan boundaries lost."}
    if(-not $p.Contains('SHARPEMU_V74_0_82_NONBLOCKING_ORDERED_VISIBILITY_DEFAULT')){throw "$script:Tag V82 nonblocking path lost."}
    $f2=Get-DeclarationSegment $p '_kytyComputeSubmissionFairnessV74033';$ad2=Get-DeclarationSegment $p '_adaptiveUnifiedComputeV7405616'
    if($null -eq $f2 -or -not($f2.Text.Contains('!string.Equals') -and $f2.Text.Contains('"0"'))){throw "$script:Tag fairness did not become default-on."}
    if($null -eq $ad2 -or -not($ad2.Text.Contains('!string.Equals') -and $ad2.Text.Contains('"0"'))){throw "$script:Tag adaptive unified did not become default-on."}
    Write-Utf8NoBom $script:PresenterPath $p
    Write-Host "$script:Tag PATCH APPLIED STRUCTURALLY." -ForegroundColor Green
    Write-Host "$script:Tag submission_fairness=default-on soft_target=8 hard_emergency=existing-24 env_0_restores_legacy"
    Write-Host "$script:Tag adaptive_unified_compute=default-on max_groups=existing-65536 indirect_excluded=True env_0_restores_legacy"
    Write-Host "$script:Tag v81_2_vulkan_boundaries_preserved=True v82_nonblocking_preserved=True"
    Write-Host "$script:Tag Backup=$backup"
    Write-Host "$script:Tag PresenterSHA256=$(Get-Sha256 $script:PresenterPath)"
  }catch{if($null -ne $backup -and (Test-Path -LiteralPath $backup)){Restore-Backup $backup};throw}
}else{Write-Host "$script:Tag State=AlreadyApplied"}
$buildLog=Join-Path $script:PatchesRoot ("SharpEmu_V74_0_84_APPLY_BUILD_"+(Get-Date -Format 'yyyyMMdd_HHmmss')+'.log')
Write-Host "$script:Tag Building SharpEmu.CLI Debug win-x64..."
$project=Join-Path $script:RepoRoot 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
try{& dotnet build $project -c Debug -r win-x64 2>&1|Tee-Object -FilePath $buildLog;$code=$LASTEXITCODE}catch{$code=1;$_|Out-String|Add-Content -LiteralPath $buildLog}
if($code -ne 0){if($null -ne $backup -and (Test-Path -LiteralPath $backup)){Restore-Backup $backup;Write-Host "$script:Tag BUILD FAILED; source automatically restored from $backup" -ForegroundColor Yellow};throw "$script:Tag BUILD FAILED. Log=$buildLog"}
Write-Host "$script:Tag BUILD PASSED. Log=$buildLog" -ForegroundColor Green
