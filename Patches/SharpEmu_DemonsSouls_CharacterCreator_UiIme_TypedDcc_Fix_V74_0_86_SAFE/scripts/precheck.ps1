. "$PSScriptRoot\common.ps1"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'validate.ps1')
if($LASTEXITCODE -ne 0){ exit $LASTEXITCODE }
$repo=RepoRoot; $ime=ImeDialogSource; $presenter=PresenterSource
foreach($p in @($ime,$presenter,(CliProject))){if(-not(Test-Path -LiteralPath $p -PathType Leaf)){Write-Host "$script:Tag [ERROR] missing source: $p" -ForegroundColor Red; exit 1}}
$it=NL([IO.File]::ReadAllText($ime)); $pt=NL([IO.File]::ReadAllText($presenter))
$imeInstalled=$it.Contains('SHARPEMU_V74_0_86_IME_VISIBLE_HOST_TEXT_INPUT')
$presenterInstalled=$pt.Contains('SHARPEMU_V74_0_86_DS_CHARACTER_CREATOR_TYPED_DCC')
if($imeInstalled -and $presenterInstalled){Write-Host "$script:Tag PRECHECK: patch already installed." -ForegroundColor Yellow; exit 10}
if($imeInstalled -xor $presenterInstalled){Write-Host "$script:Tag [ERROR] partial V74.0.86 state detected; use this package's rollback or restore the missing side before reapplying." -ForegroundColor Red; exit 1}
$issues=0
$expectedImeSha='AEA44C97EFA0ED2EFC1AFD7D61AE1701990568559CFA1B27A3A20B92F38E965A'
$currentImeSha=Sha $ime
if(-not$it.Contains('SHARPEMU_V74_0_85_1_IME_DIALOG_HOST_TEXT_INPUT')){$issues++;Write-Host "$script:Tag [ERROR] V74.0.85.1 IME prerequisite missing." -ForegroundColor Red}
if($currentImeSha -ne $expectedImeSha){$issues++;Write-Host "$script:Tag [ERROR] unsupported ImeDialogExports.cs baseline." -ForegroundColor Red;Write-Host "$script:Tag ExpectedSHA256=$expectedImeSha";Write-Host "$script:Tag CurrentSHA256=$currentImeSha"}
foreach($m in @('SHARPEMU_V74_0_56_32_DCC_METADATA_ALIAS','TryResolveGuestImageMetadataAliasV7405632(','_v7405632DccMetadataAliasMissCount','[V74.0.80][DCC_PROVENANCE_RECOVERY]','[V74.0.82][DCC_METADATA_INDEX]')){if(-not$pt.Contains($m)){$issues++;Write-Host "$script:Tag [ERROR] Presenter prerequisite missing: $m" -ForegroundColor Red}}
try{
    $span=Get-DccAliasSpan $pt; $body=MethodBody $pt $span
    $missCounterPos=$body.LastIndexOf('ref _v7405632DccMetadataAliasMissCount',[StringComparison]::Ordinal)
    $missBranchPos=if($missCounterPos -ge 0){$body.LastIndexOf('            if (best is null)',$missCounterPos,[StringComparison]::Ordinal)}else{-1}
    if($missCounterPos -lt 0 -or $missBranchPos -lt 0){$issues++;Write-Host "$script:Tag [ERROR] final DCC miss branch structural locator failed." -ForegroundColor Red}
}catch{$issues++;Write-Host "$script:Tag [ERROR] DCC alias method structural probe failed: $($_.Exception.Message)" -ForegroundColor Red}
Write-Host "$script:Tag Target A: visible asynchronous host IME for character-name entry."
Write-Host "$script:Tag Target B: PPSA01341 exact typed-format DCC alias integrity after V80 provenance selection."
Write-Host "$script:Tag Evidence: current runtime enters IME RUNNING/host_panel_open but never completes; current DCC path repeatedly aliases RGBA8/R32G32UI samples to floating-point images."
Write-Host "$script:Tag ImeDialogSHA256=$currentImeSha"
Write-Host "$script:Tag PresenterSHA256=$(Sha $presenter)"
$eboot=$env:SHARPEMU_DEMONS_EBOOT; if([string]::IsNullOrWhiteSpace($eboot)){$eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'}
if(Test-Path -LiteralPath $eboot){Write-Host "$script:Tag Eboot=$eboot";Write-Host "$script:Tag EbootSHA256=$(Sha $eboot)"}else{Write-Host "$script:Tag [WARN] eboot not found during precheck: $eboot" -ForegroundColor Yellow}
if($issues -gt 0){Write-Host "$script:Tag PRECHECK FAILED issues=$issues" -ForegroundColor Red;exit 1}
Write-Host "$script:Tag PRECHECK PASSED." -ForegroundColor Green
