$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "common.ps1")

$packageRoot=[System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$manifest=[System.IO.Path]::Combine($packageRoot,"SHA256SUMS.txt")
if(-not [System.IO.File]::Exists($manifest)){
    throw "[V74.0.17] SHA256SUMS.txt missing."
}

$manifestPaths=New-Object 'System.Collections.Generic.List[string]'
$checked=0
foreach($line in Get-Content -LiteralPath $manifest){
    if([string]::IsNullOrWhiteSpace($line)){continue}
    if($line -notmatch '^([0-9A-Fa-f]{64})  (.+)$'){
        throw "[V74.0.17] Invalid manifest line: $line"
    }
    $expected=$Matches[1].ToUpperInvariant()
    $relative=$Matches[2].Replace('/',[System.IO.Path]::DirectorySeparatorChar)
    if([System.IO.Path]::IsPathRooted($relative) -or
       $relative -match '(^|[\\/])\.\.([\\/]|$)'){
        throw "[V74.0.17] Unsafe manifest path: $relative"
    }
    if($manifestPaths.Contains($relative)){
        throw "[V74.0.17] Duplicate manifest path: $relative"
    }
    $manifestPaths.Add($relative)
    $path=[System.IO.Path]::Combine($packageRoot,$relative)
    if(-not [System.IO.File]::Exists($path)){
        throw "[V74.0.17] Missing package file: $relative"
    }
    $actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
    if($actual -ne $expected){
        throw "[V74.0.17] Hash mismatch: $relative"
    }
    $checked++
}

foreach($packageFile in Get-ChildItem -LiteralPath $packageRoot -Recurse -File){
    if($packageFile.FullName -eq $manifest){continue}
    $relativePath=$packageFile.FullName.Substring($packageRoot.Length).TrimStart(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)
    if(-not $manifestPaths.Contains($relativePath)){
        throw "[V74.0.17] Unmanifested package file: $relativePath"
    }
}

$reserved=@(
    "Host","HOME","PWD","PID","PSHOME","ShellId","Input","Args","Error",
    "Matches","LASTEXITCODE","MyInvocation","PSScriptRoot","PSCommandPath",
    "StackTrace","ExecutionContext","PSBoundParameters","PSVersionTable",
    "PSEdition","NestedPromptLevel","PSItem","_","this")
function Get-UnscopedVariableNameV74017 {
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
        throw "[V74.0.17] PowerShell parse failure: $($ps1.Name): $details"
    }
    foreach($assignment in @($ast.FindAll(
        {param($node) $node -is [System.Management.Automation.Language.AssignmentStatementAst]},$true))){
        if($assignment.Left -is [System.Management.Automation.Language.VariableExpressionAst]){
            $variableName=Get-UnscopedVariableNameV74017 -VariableName $assignment.Left.VariablePath.UserPath
            if($reserved -contains $variableName){
                throw "[V74.0.17] Reserved PowerShell variable assignment rejected: `$$variableName in $($ps1.Name)"
            }
        }
    }
    foreach($parameterAst in @($ast.FindAll(
        {param($node) $node -is [System.Management.Automation.Language.ParameterAst]},$true))){
        $parameterName=Get-UnscopedVariableNameV74017 -VariableName $parameterAst.Name.VariablePath.UserPath
        if($reserved -contains $parameterName){
            throw "[V74.0.17] Reserved PowerShell parameter rejected: `$$parameterName in $($ps1.Name)"
        }
    }
    foreach($foreachAst in @($ast.FindAll(
        {param($node) $node -is [System.Management.Automation.Language.ForEachStatementAst]},$true))){
        $foreachName=Get-UnscopedVariableNameV74017 -VariableName $foreachAst.Variable.VariablePath.UserPath
        if($reserved -contains $foreachName){
            throw "[V74.0.17] Reserved PowerShell foreach variable rejected: `$$foreachName in $($ps1.Name)"
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
            if(-not [System.IO.File]::Exists($target)){
                throw "[V74.0.17] CMD target missing: $($cmd.Name) -> $($Matches[1])"
            }
            $cmdTargets++
            $foundTarget=$true
        }
    }
    if(-not $foundTarget){
        throw "[V74.0.17] CMD has no PowerShell -File target: $($cmd.Name)"
    }
}
if($cmdTargets -ne 4){
    throw "[V74.0.17] Expected 4 verified CMD targets, got $cmdTargets."
}

$precheckText=[System.IO.File]::ReadAllText(
    [System.IO.Path]::Combine($packageRoot,"scripts","precheck.ps1"))
$applyText=[System.IO.File]::ReadAllText(
    [System.IO.Path]::Combine($packageRoot,"scripts","apply_build.ps1"))
$runnerText=[System.IO.File]::ReadAllText(
    [System.IO.Path]::Combine($packageRoot,"scripts","run_fastboot.ps1"))

foreach($guard in @(
    "Get-PthreadOpaqueOwnerGateStateV74017",
    "Add-PthreadOpaqueOwnerGateV74017"
)){
    if(-not $precheckText.Contains($guard) -or -not $applyText.Contains($guard)){
        throw "[V74.0.17] PRECHECK/APPLY shared-transformer guard missing: $guard"
    }
}
if($applyText -match '(?i)Copy-Item[^\r\n]+payload[^\r\n]+(?:KernelPthreadCompatExports|AgcExports|VulkanVideoPresenter|DirectExecutionBackend)'){
    throw "[V74.0.17] Whole-file source payload replacement forbidden."
}
foreach($guard in @(
    '$env:SHARPEMU_PTHREAD_OPAQUE_OWNER_SYNC="0"',
    '$env:SHARPEMU_DCC_ALIAS_HISTORY_MS="0"',
    '$env:SHARPEMU_TRACE_DCC_ALIAS="0"',
    '$env:SHARPEMU_NATIVE_WORKER_MAX_CONCURRENT="2"',
    '$env:SHARPEMU_RENDERER_RESOURCE_NATIVE_MAX_CONCURRENT="8"',
    '$env:SHARPEMU_RENDER_SCALE="0.25"',
    '[string]::Format(',
    'ErrorDeviceLost',
    'HEAP_CORRUPTION',
    'actual_runtime_seconds'
)){
    if(-not $runnerText.Contains($guard)){
        throw "[V74.0.17] Runner guard missing: $guard"
    }
}
if($runnerText -match '(?ms)Write-Host\s*\(\s*"\[V74\.0\.17\] t=\{0:F0\}'){
    throw "[V74.0.17] Broken status-format regression detected."
}

# Pure transformer self-tests. These exercise the same functions PRECHECK and
# APPLY use, including idempotence. No repository files are touched.
$synthetic=@'
public static class Synthetic
{
    // SHARPEMU_DBFZ_PTHREAD_OPAQUE_OWNER_SYNC_V1_4_5
    private static int _dbfzOpaqueOwnerTraceCount;

    private static int PthreadMutexLockCoreWithOpaqueOwnerSync(CpuContext ctx, ulong mutexAddress, bool tryOnly)
    {
        var result = PthreadMutexLockCore(ctx, mutexAddress, tryOnly);
        if (result == (int)OrbisGen2Result.ORBIS_GEN2_OK)
        {
            SyncAdaptiveGuestMutexOpaqueOwner(ctx, mutexAddress, "lock");
        }
        return result;
    }

    private static int PthreadMutexUnlockCoreWithOpaqueOwnerSync(CpuContext ctx, ulong mutexAddress, bool requireOwner)
    {
        var result = PthreadMutexUnlockCore(ctx, mutexAddress, requireOwner);
        if (result == (int)OrbisGen2Result.ORBIS_GEN2_OK)
        {
            SyncAdaptiveGuestMutexOpaqueOwner(ctx, mutexAddress, "unlock");
        }
        return result;
    }
}
'@
$syntheticState=Get-PthreadOpaqueOwnerGateStateV74017 -Text $synthetic
if($syntheticState.State -ne "Ready"){
    throw "[V74.0.17] Synthetic baseline state failed: $($syntheticState.State)"
}
$syntheticPatched=Add-PthreadOpaqueOwnerGateV74017 -Text $synthetic
$syntheticPatchedState=Get-PthreadOpaqueOwnerGateStateV74017 -Text $syntheticPatched
if($syntheticPatchedState.State -ne "Applied"){
    throw "[V74.0.17] Synthetic transformed state failed: $($syntheticPatchedState.State)"
}
$syntheticSecondPass=Add-PthreadOpaqueOwnerGateV74017 -Text $syntheticPatched
if(-not [string]::Equals($syntheticPatched,$syntheticSecondPass,[System.StringComparison]::Ordinal)){
    throw "[V74.0.17] Transformer idempotence self-test failed."
}

Write-Host "[V74.0.17] PACKAGE VALIDATION PASSED ($checked hashed files; $parsed PowerShell scripts parsed; $cmdTargets CMD targets verified; manifest coverage passed; reserved-variable audit passed; shared PRECHECK/APPLY transformer verified; synthetic transform+idempotence passed)."
