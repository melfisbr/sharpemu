. (Join-Path $PSScriptRoot 'common.ps1')
$package=Get-PackageRoot
$manifest=Join-Path $package 'SHA256SUMS.txt'
if(!(Test-Path -LiteralPath $manifest -PathType Leaf)){
    throw '[V74.0.67.2.18] SHA256SUMS.txt missing.'
}

$failed=$false
$hashCount=0
foreach($line in Get-Content -LiteralPath $manifest){
    if([string]::IsNullOrWhiteSpace($line)){continue}
    if($line -notmatch '^([0-9A-Fa-f]{64}) \*(.+)$'){
        Write-Host "[V74.0.67.2.18] malformed_manifest_line=$line"
        $failed=$true
        continue
    }
    $expected=$matches[1].ToUpperInvariant()
    $relative=$matches[2].Replace('\',[IO.Path]::DirectorySeparatorChar)
    $path=Join-Path $package $relative
    if(!(Test-Path -LiteralPath $path -PathType Leaf)){
        Write-Host "[V74.0.67.2.18] manifest_missing=$relative"
        $failed=$true
        continue
    }
    $actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if($actual-ne $expected){
        Write-Host "[V74.0.67.2.18] manifest_hash_mismatch=$relative"
        $failed=$true
    }
    $hashCount++
}

$scripts=Get-ChildItem -LiteralPath (Join-Path $package 'scripts') -Filter '*.ps1' -File
$parseErrors=0
foreach($ps1 in $scripts){
    $tokens=$null;$errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile(
        $ps1.FullName,[ref]$tokens,[ref]$errors)
    if($errors.Count-ne 0){
        foreach($err in $errors){
            Write-Host "[V74.0.67.2.18] parse_error=$($ps1.Name):$($err.Message)"
            $parseErrors++
        }
        $failed=$true
    }
}
Write-Host "[V74.0.67.2.18] parsed_powershell_files=$($scripts.Count)"
Write-Host "[V74.0.67.2.18] powershell_parse_errors=$parseErrors"

$forbiddenShort='[IO.Path]::Get'+'RelativePath('
$forbiddenFull='[System.IO.Path]::Get'+'RelativePath('
$unsafeContainsPattern='(?m)\.Contains\("[^"\r\n]*\$[^"\r\n]*"\)'
$reserved=0;$relativeHits=0;$unsafeHits=0

foreach($ps1 in $scripts){
    $text=[IO.File]::ReadAllText($ps1.FullName)
    if([regex]::IsMatch($text,'(?im)^\s*\$host\s*=')){
        Write-Host "[V74.0.67.2.18] reserved_host_assignment=$($ps1.Name)"
        $reserved++;$failed=$true
    }
    if($text.Contains($forbiddenShort) -or $text.Contains($forbiddenFull)){
        Write-Host "[V74.0.67.2.18] powershell51_getrelativepath=$($ps1.Name)"
        $relativeHits++;$failed=$true
    }
    $unsafe=[regex]::Matches($text,$unsafeContainsPattern)
    if($unsafe.Count-ne 0){
        foreach($m in $unsafe){
            Write-Host "[V74.0.67.2.18] unsafe_contains_interpolation=$($ps1.Name):$($m.Value)"
        }
        $unsafeHits += $unsafe.Count
        $failed=$true
    }
}

Write-Host "[V74.0.67.2.18] reserved_host_assignment_count=$reserved"
Write-Host "[V74.0.67.2.18] getrelativepath_hit_count=$relativeHits"
Write-Host "[V74.0.67.2.18] unsafe_contains_interpolation_count=$unsafeHits"

$runnerMap=[ordered]@{
    'RUN_1_VALIDATE_PACKAGE.cmd'='validate_package.ps1'
    'RUN_2_PRECHECK.cmd'='precheck.ps1'
    'RUN_3_APPLY_BUILD.cmd'='apply_build.ps1'
    'RUN_4_DIAGNOSTIC.cmd'='diagnostic.ps1'
    'RUN_5_OPEN_GUI.cmd'='open_gui.ps1'
}
foreach($entry in $runnerMap.GetEnumerator()){
    $runner=Join-Path $package $entry.Key
    $target=Join-Path (Join-Path $package 'scripts') $entry.Value
    $runnerOk=Test-Path -LiteralPath $runner -PathType Leaf
    $targetOk=Test-Path -LiteralPath $target -PathType Leaf
    $mapOk=$false
    if($runnerOk){
        $mapOk=[IO.File]::ReadAllText($runner).Contains(('scripts\'+$entry.Value))
    }
    Write-Host "[V74.0.67.2.18] runner_$($entry.Key)_exists=$($runnerOk.ToString().ToLowerInvariant())"
    Write-Host "[V74.0.67.2.18] runner_$($entry.Key)_target_ok=$($mapOk.ToString().ToLowerInvariant())"
    if(!$runnerOk -or !$targetOk -or !$mapOk){$failed=$true}
}

$patch=[IO.File]::ReadAllText((Join-Path $package 'scripts\patch_bpe_head2_sentinel.ps1'))
$apply=[IO.File]::ReadAllText((Join-Path $package 'scripts\apply_build.ps1'))
$launcher=[IO.File]::ReadAllText((Join-Path $package 'scripts\open_gui.ps1'))

$checks=[ordered]@{
    exact_target=$patch.Contains('er->ExceptionInformation[1] != 0xA')
    exact_rcx2=$patch.Contains('rcx != 2')
    exact_rax2=$patch.Contains('rax != 2')
    exact_rdi_r14=$patch.Contains('rdi != r14')
    exact_head2=$patch.Contains('head != 2')
    exact_adjacent0=$patch.Contains('adjacent != 0')
    exact_helper=$patch.Contains('0x48, 0x8B, 0x49, 0x08')
    exact_primary_caller=$patch.Contains('0xF390853B48C68949UL')
    exact_caller_cmp=$patch.Contains('0x840FFFFFUL')
    exact_caller_deref=$patch.Contains('0x20468B41UL')
    caller_end_payload=$patch.Contains('callerEndSentinel != payload')
    returns_payload=$patch.Contains('WriteCtxU64(ctx, CTX_RAX, payload);')
    clears_rcx=$patch.Contains('WriteCtxU64(ctx, CTX_RCX, 0);')
    resumes_rip=$patch.Contains('WriteCtxU64(ctx, CTX_RIP, rip + 4);')
    v217_cumulative=$apply.Contains('patch_v217.ps1')
    launcher_no_forced_dlss=
        !$launcher.Contains(('$env:SHARPEMU_VK_UPSCALER'+[char]61+[char]39+'dlss'+[char]39))
}

foreach($entry in $checks.GetEnumerator()){
    Write-Host "[V74.0.67.2.18] validator_$($entry.Key)=$($entry.Value.ToString().ToLowerInvariant())"
    if(!$entry.Value){$failed=$true}
}

Write-Host '[V74.0.67.2.18] patch_scope=DirectExecutionBackend.Exceptions.cs'
Write-Host '[V74.0.67.2.18] cumulative_v217=apply-only-if-source-ready'
Write-Host '[V74.0.67.2.18] native_provider_change=false'
Write-Host '[V74.0.67.2.18] absolute_guest_address_gate=false'
Write-Host '[V74.0.67.2.18] powershell_51_compatible=true'

if($failed){throw '[V74.0.67.2.18] PACKAGE VALIDATION FAILED.'}
Write-Host "[V74.0.67.2.18] PACKAGE VALIDATION PASSED ($hashCount hashed files; $($scripts.Count) PowerShell files parsed; exact BPE head2 gates passed)."
