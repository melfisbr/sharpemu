$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$packageRoot=[System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$manifest=[System.IO.Path]::Combine($packageRoot,"SHA256SUMS.txt")
if(-not [System.IO.File]::Exists($manifest)){
    throw "[V74.0.15] SHA256SUMS.txt missing."
}

$manifestPaths=New-Object 'System.Collections.Generic.List[string]'
$checked=0
foreach($line in Get-Content -LiteralPath $manifest){
    if([string]::IsNullOrWhiteSpace($line)){continue}
    if($line -notmatch '^([0-9A-Fa-f]{64})  (.+)$'){
        throw "[V74.0.15] Invalid hash manifest line: $line"
    }
    $expected=$Matches[1].ToUpperInvariant()
    $manifestRelative=$Matches[2].Replace('/',[System.IO.Path]::DirectorySeparatorChar)
    if([System.IO.Path]::IsPathRooted($manifestRelative) -or
       $manifestRelative -match '(^|[\\/])\.\.([\\/]|$)'){
        throw "[V74.0.15] Unsafe manifest path: $manifestRelative"
    }
    if($manifestPaths.Contains($manifestRelative)){
        throw "[V74.0.15] Duplicate manifest entry: $manifestRelative"
    }
    $manifestPaths.Add($manifestRelative)

    $path=[System.IO.Path]::Combine($packageRoot,$manifestRelative)
    if(-not [System.IO.File]::Exists($path)){
        throw "[V74.0.15] Package file missing: $manifestRelative"
    }
    $actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
    if($actual -ne $expected){
        throw "[V74.0.15] Hash mismatch: $manifestRelative expected=$expected actual=$actual"
    }
    $checked++
}

# Reject accidental unmanifested files. SHA256SUMS itself is the only exception.
foreach($packageFile in Get-ChildItem -LiteralPath $packageRoot -Recurse -File){
    if($packageFile.FullName -eq $manifest){continue}
    $relativePath=$packageFile.FullName.Substring($packageRoot.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar,[System.IO.Path]::AltDirectorySeparatorChar)
    if(-not $manifestPaths.Contains($relativePath)){
        throw "[V74.0.15] Unmanifested package file: $relativePath"
    }
}

$required=@(
    "scripts\common.ps1",
    "scripts\precheck.ps1",
    "scripts\apply_build.ps1",
    "scripts\run_fastboot.ps1",
    "scripts\validate_package.ps1",
    "evidence\V74_0_14_RESULT_ANALYSIS.txt",
    "evidence\CUMULATIVE_GUARDS.txt",
    "RUN_1_VALIDATE_PACKAGE.cmd",
    "RUN_2_PRECHECK.cmd",
    "RUN_3_APPLY_BUILD.cmd",
    "RUN_4_DEMONS_ARRAY_SINGLEFLIGHT.cmd"
)
foreach($requiredRelative in $required){
    $requiredPath=[System.IO.Path]::Combine($packageRoot,$requiredRelative)
    if(-not [System.IO.File]::Exists($requiredPath)){
        throw "[V74.0.15] Required package component missing: $requiredRelative"
    }
}

# Parse every PowerShell file before any repository access. In addition to
# ordinary assignment statements, audit parameter and foreach binders because
# PowerShell automatic variables are case-insensitive (e.g. $host == $Host).
$reservedAutomaticVariables=@(
    "Host","HOME","PWD","PID","PSHOME","ShellId","Input","Args","Error",
    "Matches","LASTEXITCODE","MyInvocation","PSScriptRoot","PSCommandPath",
    "StackTrace","ExecutionContext","PSBoundParameters","PSVersionTable",
    "PSEdition","NestedPromptLevel","PSItem","_","this"
)

function Get-UnscopedVariableNameV74015 {
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
        $details=(@($parseErrors) | ForEach-Object { $_.Message }) -join " | "
        throw "[V74.0.15] PowerShell parse failure: $($ps1.FullName): $details"
    }

    $assignments=@($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst]
    },$true))
    foreach($assignment in $assignments){
        $left=$assignment.Left
        if($left -is [System.Management.Automation.Language.VariableExpressionAst]){
            $variableName=Get-UnscopedVariableNameV74015 $left.VariablePath.UserPath
            if($reservedAutomaticVariables -contains $variableName){
                throw "[V74.0.15] Reserved PowerShell variable assignment rejected: `$$variableName in $($ps1.FullName)"
            }
        }
    }

    $parameters=@($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.ParameterAst]
    },$true))
    foreach($parameterAst in $parameters){
        $parameterName=Get-UnscopedVariableNameV74015 $parameterAst.Name.VariablePath.UserPath
        if($reservedAutomaticVariables -contains $parameterName){
            throw "[V74.0.15] Reserved PowerShell parameter rejected: `$$parameterName in $($ps1.FullName)"
        }
    }

    $foreachStatements=@($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.ForEachStatementAst]
    },$true))
    foreach($foreachAst in $foreachStatements){
        $foreachName=Get-UnscopedVariableNameV74015 $foreachAst.Variable.VariablePath.UserPath
        if($reservedAutomaticVariables -contains $foreachName){
            throw "[V74.0.15] Reserved PowerShell foreach variable rejected: `$$foreachName in $($ps1.FullName)"
        }
    }

    $parsed++
}

# Every local target referenced by CMD launchers must exist.
$cmdTargets=0
foreach($cmd in Get-ChildItem -LiteralPath $packageRoot -File -Filter "*.cmd"){
    foreach($cmdLine in Get-Content -LiteralPath $cmd.FullName){
        if($cmdLine -match '(?i)-File\s+"%~dp0([^"]+\.ps1)"'){
            $target=[System.IO.Path]::Combine($packageRoot,$Matches[1])
            if(-not [System.IO.File]::Exists($target)){
                throw "[V74.0.15] CMD references missing PowerShell file: $($cmd.Name) -> $($Matches[1])"
            }
            $cmdTargets++
        }
        if($cmdLine -match '(?i)\bcall\s+"%~dp0([^"]+\.cmd)"'){
            $target=[System.IO.Path]::Combine($packageRoot,$Matches[1])
            if(-not [System.IO.File]::Exists($target)){
                throw "[V74.0.15] CMD references missing CMD file: $($cmd.Name) -> $($Matches[1])"
            }
            $cmdTargets++
        }
    }
}

# Guard V74.0.15's exact scope. The package must structurally patch AGC;
# whole-file source payload replacement is forbidden.
$applyText=[System.IO.File]::ReadAllText(
    [System.IO.Path]::Combine($packageRoot,"scripts","apply_build.ps1"))
$commonText=[System.IO.File]::ReadAllText(
    [System.IO.Path]::Combine($packageRoot,"scripts","common.ps1"))
$runnerText=[System.IO.File]::ReadAllText(
    [System.IO.Path]::Combine($packageRoot,"scripts","run_fastboot.ps1"))

foreach($sourceGuard in @(
    "SHARPEMU_V74_0_15_LARGE_ARRAY_SINGLE_FLIGHT",
    "V74015LargeArraySnapshotKey",
    "V74015LargeArraySnapshotTtlMs = 500L",
    "GC.AllocateUninitializedArray<byte>",
    "GPU tiled array single-flight",
    "CPU linear array single-flight",
    "V74.0.5 non-array reuse bounded to 8..32 MB",
    "v7405PredicatePattern",
    "v7405UpperBoundPattern",
    "V74.0.15.1] V74.0.5 snapshot predicate structural narrowing failed"
)){
    if(-not $applyText.Contains($sourceGuard)){
        throw "[V74.0.15] Source patch guard missing: $sourceGuard"
    }
}
if($applyText -match '(?i)Copy-Item[^\r\n]+payload[^\r\n]+(?:AgcExports|VulkanVideoPresenter|DirectExecutionBackend)'){
    throw "[V74.0.15] Whole-file source payload replacement is forbidden."
}
if($applyText.Contains("snapshot predicate is neither original nor V74.0.15-bounded")){
    throw "[V74.0.15.1] Obsolete exact-literal V74.0.5 predicate check is forbidden."
}
if(-not $commonText.Contains("Get-AgcPathV74015") -or
   -not $commonText.Contains("Get-ProcessTreeSampleV74015")){
    throw "[V74.0.15] AGC path/process-tree common guards missing."
}
foreach($runnerGuard in @(
    '$env:SHARPEMU_NATIVE_WORKER_MAX_CONCURRENT="2"',
    '$env:SHARPEMU_RENDER_SCALE="0.25"',
    '$env:SHARPEMU_GPU_DETILE="1"',
    '$env:SHARPEMU_VK_STANDALONE_TEXTURE_CACHE_MB="768"',
    'Get-ProcessTreeSampleV74015',
    'Read-NewSharedChunkV74015',
    '[string]::Format(',
    'Write-Host $statusLine',
    'ARRAY_SINGLEFLIGHT',
    'max_alloc2s_mb'
)){
    if(-not $runnerText.Contains($runnerGuard)){
        throw "[V74.0.15] Runner guard missing: $runnerGuard"
    }
}
if($runnerText -match '(?ms)Write-Host\s*\(\s*"\[V74\.0\.15\] t=\{0:F0\}'){
    throw "[V74.0.15] Old broken status-format pattern is forbidden."
}
if(-not $runnerText.Contains("ErrorDeviceLost") -or
   -not $runnerText.Contains("HEAP_CORRUPTION")){
    throw "[V74.0.15] Fatal Vulkan/heap detection missing."
}

Write-Host "[V74.0.15] PACKAGE VALIDATION PASSED ($checked hashed files; $parsed PowerShell scripts parsed; $cmdTargets CMD targets verified; manifest coverage passed; reserved-variable binder audit passed; AGC single-flight guards passed; runner format regression guard passed)."
