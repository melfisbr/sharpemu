$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
$packageRoot=[System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$manifest=[System.IO.Path]::Combine($packageRoot,"SHA256SUMS.txt")
if(-not [System.IO.File]::Exists($manifest)){throw "[V74.0.21] SHA256SUMS.txt missing."}

$manifestPaths=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$checked=0
foreach($manifestLine in Get-Content -LiteralPath $manifest){
    if([string]::IsNullOrWhiteSpace($manifestLine)){continue}
    if($manifestLine -notmatch '^([0-9A-Fa-f]{64})  (.+)$'){throw "[V74.0.21] Invalid manifest line: $manifestLine"}
    $expectedHash=$Matches[1].ToUpperInvariant()
    $relativePath=$Matches[2].Replace('/',[System.IO.Path]::DirectorySeparatorChar)
    if([System.IO.Path]::IsPathRooted($relativePath) -or $relativePath -match '(^|[\\/])\.\.([\\/]|$)'){throw "[V74.0.21] Unsafe manifest path: $relativePath"}
    if(-not $manifestPaths.Add($relativePath)){throw "[V74.0.21] Duplicate manifest path: $relativePath"}
    $filePath=[System.IO.Path]::Combine($packageRoot,$relativePath)
    if(-not [System.IO.File]::Exists($filePath)){throw "[V74.0.21] Missing package file: $relativePath"}
    $actualHash=(Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash.ToUpperInvariant()
    if($actualHash -ne $expectedHash){throw "[V74.0.21] Hash mismatch: $relativePath"}
    $checked++
}
foreach($packageFile in Get-ChildItem -LiteralPath $packageRoot -Recurse -File){
    if($packageFile.FullName -eq $manifest){continue}
    $coveredRelative=$packageFile.FullName.Substring($packageRoot.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar,[System.IO.Path]::AltDirectorySeparatorChar)
    if(-not $manifestPaths.Contains($coveredRelative)){throw "[V74.0.21] Unmanifested package file: $coveredRelative"}
}

$parsed=0
foreach($powerShellFile in Get-ChildItem -LiteralPath $packageRoot -Recurse -File -Filter "*.ps1"){
    $tokenData=$null
    $parseErrors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($powerShellFile.FullName,[ref]$tokenData,[ref]$parseErrors)
    if(@($parseErrors).Count -gt 0){
        $details=(@($parseErrors)|ForEach-Object{$_.Message}) -join ' | '
        throw "[V74.0.21] PowerShell parse failure: $($powerShellFile.Name): $details"
    }
    $parsed++
}

$cmdTargets=0
foreach($cmdFile in Get-ChildItem -LiteralPath $packageRoot -File -Filter "*.cmd"){
    $foundTarget=$false
    foreach($cmdLine in Get-Content -LiteralPath $cmdFile.FullName){
        if($cmdLine -match '(?i)-File\s+"%~dp0([^\"]+\.ps1)"'){
            $target=[System.IO.Path]::Combine($packageRoot,$Matches[1])
            if(-not [System.IO.File]::Exists($target)){throw "[V74.0.21] CMD target missing: $($cmdFile.Name) -> $($Matches[1])"}
            $foundTarget=$true
            $cmdTargets++
        }
    }
    if(-not $foundTarget){throw "[V74.0.21] CMD has no PowerShell target: $($cmdFile.Name)"}
}
if($cmdTargets -ne 4){throw "[V74.0.21] Expected 4 CMD targets, got $cmdTargets."}

$cpuFragment=[System.IO.File]::ReadAllText([System.IO.Path]::Combine($packageRoot,"patch","CpuDispatcher.InitializeProcessEntryFrame.v74021.csfrag"))
foreach($guard in @("SHARPEMU_V74_0_21_EBOOT_ENTRY_ABI","entryParamsSize = 0x118","maxArguments = 33","entryAddressOffset = 0x110","entryPoint")){
    if(-not $cpuFragment.Contains($guard)){throw "[V74.0.21] CpuDispatcher fragment guard missing: $guard"}
}
$directFragment=[System.IO.File]::ReadAllText([System.IO.Path]::Combine($packageRoot,"patch","DirectExecutionBackend.IsSafeLleLibcExport.v74021.csfrag"))
foreach($guard in @("SHARPEMU_V74_0_21_LLE_INIT_ENV_GATE","SHARPEMU_LLE_INIT_ENV",'"_init_env"')){
    if(-not $directFragment.Contains($guard)){throw "[V74.0.21] LLE fragment guard missing: $guard"}
}
$kernelFragment=[System.IO.File]::ReadAllText([System.IO.Path]::Combine($packageRoot,"patch","KernelExports.InitEnv.v74021.csfrag"))
foreach($guard in @("SHARPEMU_V74_0_21_INIT_ENV_FALLBACK_DIAGNOSTIC","entryAddressOffset = 0x110","init_env_hle_fallback")){
    if(-not $kernelFragment.Contains($guard)){throw "[V74.0.21] InitEnv fragment guard missing: $guard"}
}
$runner=[System.IO.File]::ReadAllText([System.IO.Path]::Combine($packageRoot,"scripts","run_entry_abi.ps1"))
foreach($guard in @('SHARPEMU_BINK_AUTO_BOOT="0"','SHARPEMU_LLE_INIT_ENV="1"','SHARPEMU_LOG_PROC_PARAM="1"','HOST_MOVIE_BRIDGE_CHANGED=False')){
    if(-not $runner.Contains($guard)){throw "[V74.0.21] Runner guard missing: $guard"}
}
$apply=[System.IO.File]::ReadAllText([System.IO.Path]::Combine($packageRoot,"scripts","apply_build.ps1"))
if($apply -match 'WriteAllText\([^\r\n]*HostMovieBridge'){throw "[V74.0.21] RUN_3 must not write HostMovieBridge."}

Write-Host "[V74.0.21] PACKAGE VALIDATION PASSED ($checked hashed files; $parsed PowerShell scripts parsed; $cmdTargets CMD targets verified; manifest coverage passed; EntryParams/LLE/HLE/host-isolation guards passed)."
