$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "common.ps1")

$packageRoot=[System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$manifest=[System.IO.Path]::Combine($packageRoot,"SHA256SUMS.txt")
if(-not [System.IO.File]::Exists($manifest)){throw "[V74.0.19] SHA256SUMS.txt missing."}

$manifestPaths=New-Object 'System.Collections.Generic.List[string]'
$checked=0
foreach($line in Get-Content -LiteralPath $manifest){
    if([string]::IsNullOrWhiteSpace($line)){continue}
    if($line -notmatch '^([0-9A-Fa-f]{64})  (.+)$'){throw "[V74.0.19] Invalid manifest line: $line"}
    $expected=$Matches[1].ToUpperInvariant()
    $relative=$Matches[2].Replace('/',[System.IO.Path]::DirectorySeparatorChar)
    if([System.IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)'){
        throw "[V74.0.19] Unsafe manifest path: $relative"
    }
    if($manifestPaths.Contains($relative)){throw "[V74.0.19] Duplicate manifest path: $relative"}
    $manifestPaths.Add($relative)
    $path=[System.IO.Path]::Combine($packageRoot,$relative)
    if(-not [System.IO.File]::Exists($path)){throw "[V74.0.19] Missing package file: $relative"}
    $actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
    if($actual -ne $expected){throw "[V74.0.19] Hash mismatch: $relative"}
    $checked++
}
foreach($packageFile in Get-ChildItem -LiteralPath $packageRoot -Recurse -File){
    if($packageFile.FullName -eq $manifest){continue}
    $relativePath=$packageFile.FullName.Substring($packageRoot.Length).TrimStart(
        [System.IO.Path]::DirectorySeparatorChar,[System.IO.Path]::AltDirectorySeparatorChar)
    if(-not $manifestPaths.Contains($relativePath)){throw "[V74.0.19] Unmanifested package file: $relativePath"}
}

$reserved=@(
    "Host","HOME","PWD","PID","PSHOME","ShellId","Input","Args","Error",
    "Matches","LASTEXITCODE","MyInvocation","PSScriptRoot","PSCommandPath",
    "StackTrace","ExecutionContext","PSBoundParameters","PSVersionTable",
    "PSEdition","NestedPromptLevel","PSItem","_","this")
function Get-UnscopedVariableNameV74019 {
    param([string]$VariableName)
    if([string]::IsNullOrWhiteSpace($VariableName)){return $VariableName}
    $parts=$VariableName.Split(':')
    return $parts[$parts.Length-1]
}

$parsed=0
foreach($ps1 in Get-ChildItem -LiteralPath $packageRoot -Recurse -File -Filter "*.ps1"){
    $tokens=$null
    $parseErrors=$null
    $ast=[System.Management.Automation.Language.Parser]::ParseFile(
        $ps1.FullName,[ref]$tokens,[ref]$parseErrors)
    if(@($parseErrors).Count -gt 0){
        $details=(@($parseErrors)|ForEach-Object{$_.Message}) -join ' | '
        throw "[V74.0.19] PowerShell parse failure: $($ps1.Name): $details"
    }
    foreach($assignment in @($ast.FindAll(
        {param($node) $node -is [System.Management.Automation.Language.AssignmentStatementAst]},$true))){
        if($assignment.Left -is [System.Management.Automation.Language.VariableExpressionAst]){
            $variableName=Get-UnscopedVariableNameV74019 -VariableName $assignment.Left.VariablePath.UserPath
            if($reserved -contains $variableName){
                throw "[V74.0.19] Reserved PowerShell variable assignment rejected: `$$variableName in $($ps1.Name)"
            }
        }
    }
    foreach($parameterAst in @($ast.FindAll(
        {param($node) $node -is [System.Management.Automation.Language.ParameterAst]},$true))){
        $parameterName=Get-UnscopedVariableNameV74019 -VariableName $parameterAst.Name.VariablePath.UserPath
        if($reserved -contains $parameterName){
            throw "[V74.0.19] Reserved PowerShell parameter rejected: `$$parameterName in $($ps1.Name)"
        }
    }
    foreach($foreachAst in @($ast.FindAll(
        {param($node) $node -is [System.Management.Automation.Language.ForEachStatementAst]},$true))){
        $foreachName=Get-UnscopedVariableNameV74019 -VariableName $foreachAst.Variable.VariablePath.UserPath
        if($reserved -contains $foreachName){
            throw "[V74.0.19] Reserved PowerShell foreach variable rejected: `$$foreachName in $($ps1.Name)"
        }
    }
    $parsed++
}

$cmdTargets=0
foreach($cmd in Get-ChildItem -LiteralPath $packageRoot -File -Filter "*.cmd"){
    $foundTarget=$false
    foreach($cmdLine in Get-Content -LiteralPath $cmd.FullName){
        if($cmdLine -match '(?i)-File\s+"%~dp0([^"]+\.ps1)"'){
            $target=[System.IO.Path]::Combine($packageRoot,$Matches[1])
            if(-not [System.IO.File]::Exists($target)){throw "[V74.0.19] CMD target missing: $($cmd.Name) -> $($Matches[1])"}
            $cmdTargets++
            $foundTarget=$true
        }
    }
    if(-not $foundTarget){throw "[V74.0.19] CMD has no PowerShell -File target: $($cmd.Name)"}
}
if($cmdTargets -ne 4){throw "[V74.0.19] Expected 4 verified CMD targets, got $cmdTargets."}

$runner=[System.IO.File]::ReadAllText([System.IO.Path]::Combine($packageRoot,"scripts","run_fastboot.ps1"))
foreach($guard in @(
    '$env:SHARPEMU_BINK_AUTO_BOOT="1"',
    '$env:SHARPEMU_BINK_AUTO_BOOT_GRACE_MS="1500"',
    '$env:SHARPEMU_BINK_STARTUP_COMPLETION_SHIM="0"',
    '$env:SHARPEMU_NATIVE_MEMCPY_INTRINSIC="1"',
    '$env:SHARPEMU_RENDER_SCALE="1.0"',
    'ps_studios_logo.bk2 -> logo_intro.bk2 -> logo_intro_loop.bk2',
    'bink2\.direct_boot_started movies=(\d+)',
    'bink2\.direct_boot_completed',
    'auto-boot-not-started',
    'post-boot-observation-complete',
    '[string]::Format('
)){
    if(-not $runner.Contains($guard)){throw "[V74.0.19] Runner guard missing: $guard"}
}
foreach($forbidden in @(
    '$env:SHARPEMU_BINK_AUTO_BOOT="0"',
    '$env:SHARPEMU_BINK_AUTO_BOOT_GRACE_MS="900000"',
    '$env:SHARPEMU_BINK_STARTUP_COMPLETION_SHIM="1"'
)){
    if($runner.Contains($forbidden)){throw "[V74.0.19] Forbidden V74.0.18 boot regression still present: $forbidden"}
}

$buildScript=[System.IO.File]::ReadAllText([System.IO.Path]::Combine($packageRoot,"scripts","apply_build.ps1"))
if($buildScript -match '(?i)\[System\.IO\.File\]::WriteAllText\([^,\r\n]*(?:DirectExecutionBackend|HostMovieBridge|AgcExports|VulkanVideoPresenter)'){
    throw "[V74.0.19] RUN_3 must not mutate source."
}

Write-Host "[V74.0.19] PACKAGE VALIDATION PASSED ($checked hashed files; $parsed PowerShell scripts parsed; $cmdTargets CMD targets verified; manifest coverage passed; reserved-variable audit passed; auto-boot restore guards passed; V74.0.18 boot-disable regression absent)."
