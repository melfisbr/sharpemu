$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$packageRoot=[System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$manifest=[System.IO.Path]::Combine($packageRoot,"SHA256SUMS.txt")
if(-not [System.IO.File]::Exists($manifest)){
    throw "[V74.0.13.2] SHA256SUMS.txt missing."
}

$checked=0
foreach($line in Get-Content -LiteralPath $manifest){
    if([string]::IsNullOrWhiteSpace($line)){continue}
    if($line -notmatch '^([0-9A-Fa-f]{64})  (.+)$'){
        throw "[V74.0.13.2] Invalid hash manifest line: $line"
    }
    $expected=$Matches[1].ToUpperInvariant()
    $relative=$Matches[2].Replace('/',[System.IO.Path]::DirectorySeparatorChar)
    $path=[System.IO.Path]::Combine($packageRoot,$relative)
    if(-not [System.IO.File]::Exists($path)){
        throw "[V74.0.13.2] Package file missing: $relative"
    }
    $actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
    if($actual -ne $expected){
        throw "[V74.0.13.2] Hash mismatch: $relative expected=$expected actual=$actual"
    }
    $checked++
}

$required=@(
    "scripts\common.ps1",
    "scripts\precheck.ps1",
    "scripts\apply_build.ps1",
    "scripts\run_fastboot.ps1",
    "scripts\validate_package.ps1",
    "RUN_1_VALIDATE_PACKAGE.cmd",
    "RUN_2_PRECHECK.cmd",
    "RUN_3_APPLY_BUILD.cmd",
    "RUN_4_DEMONS_FASTBOOT_PERF_HANDOFF.cmd"
)
foreach($relative in $required){
    $path=[System.IO.Path]::Combine($packageRoot,$relative)
    if(-not [System.IO.File]::Exists($path)){
        throw "[V74.0.13.2] Required package component missing: $relative"
    }
}

# Parse every PowerShell script with the same parser used by Windows PowerShell.
# Also reject direct assignment to automatic/reserved variables.  This catches
# the V74.0.13.1 `$host collision before PRECHECK can ever run.
$reservedAutomaticVariables=@(
    "Host","HOME","PWD","PID","PSHOME","ShellId","Input","Args","Error",
    "LASTEXITCODE","MyInvocation","PSScriptRoot","PSCommandPath","StackTrace",
    "ExecutionContext","PSBoundParameters","PSVersionTable","PSEdition"
)
$parsed=0
foreach($ps1 in Get-ChildItem -LiteralPath $packageRoot -Recurse -File -Filter "*.ps1"){
    $tokens=$null
    $parseErrors=$null
    $ast=[System.Management.Automation.Language.Parser]::ParseFile(
        $ps1.FullName,
        [ref]$tokens,
        [ref]$parseErrors)
    if(@($parseErrors).Count -gt 0){
        $details=(@($parseErrors) | ForEach-Object { $_.Message }) -join " | "
        throw "[V74.0.13.2] PowerShell parse failure: $($ps1.FullName): $details"
    }

    $assignmentNodes=@($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst]
    },$true))
    foreach($assignment in $assignmentNodes){
        $left=$assignment.Left
        if($left -is [System.Management.Automation.Language.VariableExpressionAst]){
            $variableName=$left.VariablePath.UserPath
            if($reservedAutomaticVariables -contains $variableName){
                throw "[V74.0.13.2] Reserved/automatic PowerShell variable assignment rejected: `$$variableName in $($ps1.FullName)"
            }
        }
    }
    $parsed++
}

# Verify that every local script referenced by a .cmd actually exists.
$cmdTargets=0
foreach($cmd in Get-ChildItem -LiteralPath $packageRoot -File -Filter "*.cmd"){
    foreach($line in Get-Content -LiteralPath $cmd.FullName){
        if($line -match '(?i)-File\s+"%~dp0([^"]+\.ps1)"'){
            $target=[System.IO.Path]::Combine($packageRoot,$Matches[1])
            if(-not [System.IO.File]::Exists($target)){
                throw "[V74.0.13.2] CMD references missing PowerShell file: $($cmd.Name) -> $($Matches[1])"
            }
            $cmdTargets++
        }
        if($line -match '(?i)\bcall\s+"%~dp0([^"]+\.cmd)"'){
            $target=[System.IO.Path]::Combine($packageRoot,$Matches[1])
            if(-not [System.IO.File]::Exists($target)){
                throw "[V74.0.13.2] CMD references missing CMD file: $($cmd.Name) -> $($Matches[1])"
            }
            $cmdTargets++
        }
    }
}

Write-Host "[V74.0.13.2] PACKAGE VALIDATION PASSED ($checked hashed files; $parsed PowerShell scripts parsed; $cmdTargets CMD targets verified; reserved-variable audit passed)."
