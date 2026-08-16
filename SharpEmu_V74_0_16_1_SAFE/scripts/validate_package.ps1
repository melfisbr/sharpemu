$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "common.ps1")
$packageRoot=[System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$manifest=[System.IO.Path]::Combine($packageRoot,"SHA256SUMS.txt")
if(-not [System.IO.File]::Exists($manifest)){throw "[V74.0.16.1] SHA256SUMS.txt missing."}
$manifestPaths=New-Object 'System.Collections.Generic.List[string]'
$checked=0
foreach($line in Get-Content -LiteralPath $manifest){
    if([string]::IsNullOrWhiteSpace($line)){continue}
    if($line -notmatch '^([0-9A-Fa-f]{64})  (.+)$'){throw "[V74.0.16.1] Invalid manifest line: $line"}
    $expected=$Matches[1].ToUpperInvariant()
    $relative=$Matches[2].Replace('/',[System.IO.Path]::DirectorySeparatorChar)
    if([System.IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)'){throw "[V74.0.16.1] Unsafe manifest path: $relative"}
    if($manifestPaths.Contains($relative)){throw "[V74.0.16.1] Duplicate manifest path: $relative"}
    $manifestPaths.Add($relative)
    $path=[System.IO.Path]::Combine($packageRoot,$relative)
    if(-not [System.IO.File]::Exists($path)){throw "[V74.0.16.1] Missing package file: $relative"}
    $actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
    if($actual -ne $expected){throw "[V74.0.16.1] Hash mismatch: $relative"}
    $checked++
}
foreach($packageFile in Get-ChildItem -LiteralPath $packageRoot -Recurse -File){
    if($packageFile.FullName -eq $manifest){continue}
    $relativePath=$packageFile.FullName.Substring($packageRoot.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar,[System.IO.Path]::AltDirectorySeparatorChar)
    if(-not $manifestPaths.Contains($relativePath)){throw "[V74.0.16.1] Unmanifested package file: $relativePath"}
}
$reserved=@("Host","HOME","PWD","PID","PSHOME","ShellId","Input","Args","Error","Matches","LASTEXITCODE","MyInvocation","PSScriptRoot","PSCommandPath","StackTrace","ExecutionContext","PSBoundParameters","PSVersionTable","PSEdition","NestedPromptLevel","PSItem","_","this")
function Get-UnscopedVariableNameV74016 { param([string]$VariableName) if([string]::IsNullOrWhiteSpace($VariableName)){return $VariableName}; $parts=$VariableName.Split(':'); return $parts[$parts.Length-1] }
$parsed=0
foreach($ps1 in Get-ChildItem -LiteralPath $packageRoot -Recurse -File -Filter "*.ps1"){
    $tokens=$null; $parseErrors=$null
    $ast=[System.Management.Automation.Language.Parser]::ParseFile($ps1.FullName,[ref]$tokens,[ref]$parseErrors)
    if(@($parseErrors).Count -gt 0){$details=(@($parseErrors)|ForEach-Object{$_.Message}) -join ' | '; throw "[V74.0.16.1] PowerShell parse failure: $($ps1.Name): $details"}
    foreach($assignment in @($ast.FindAll({param($node) $node -is [System.Management.Automation.Language.AssignmentStatementAst]},$true))){
        if($assignment.Left -is [System.Management.Automation.Language.VariableExpressionAst]){
            $variableName=Get-UnscopedVariableNameV74016 $assignment.Left.VariablePath.UserPath
            if($reserved -contains $variableName){throw "[V74.0.16.1] Reserved PowerShell variable assignment rejected: `$$variableName in $($ps1.Name)"}
        }
    }
    foreach($parameterAst in @($ast.FindAll({param($node) $node -is [System.Management.Automation.Language.ParameterAst]},$true))){
        $parameterName=Get-UnscopedVariableNameV74016 $parameterAst.Name.VariablePath.UserPath
        if($reserved -contains $parameterName){throw "[V74.0.16.1] Reserved PowerShell parameter rejected: `$$parameterName in $($ps1.Name)"}
    }
    foreach($foreachAst in @($ast.FindAll({param($node) $node -is [System.Management.Automation.Language.ForEachStatementAst]},$true))){
        $foreachName=Get-UnscopedVariableNameV74016 $foreachAst.Variable.VariablePath.UserPath
        if($reserved -contains $foreachName){throw "[V74.0.16.1] Reserved PowerShell foreach variable rejected: `$$foreachName in $($ps1.Name)"}
    }
    $parsed++
}
$cmdTargets=0
foreach($cmd in Get-ChildItem -LiteralPath $packageRoot -File -Filter "*.cmd"){
    foreach($cmdLine in Get-Content -LiteralPath $cmd.FullName){
        if($cmdLine -match '(?i)-File\s+"%~dp0([^"]+\.ps1)"'){
            $target=[System.IO.Path]::Combine($packageRoot,$Matches[1])
            if(-not [System.IO.File]::Exists($target)){throw "[V74.0.16.1] CMD target missing: $($cmd.Name) -> $($Matches[1])"}
            $cmdTargets++
        }
    }
}
$applyText=[System.IO.File]::ReadAllText([System.IO.Path]::Combine($packageRoot,"scripts","apply_build.ps1"))
$runnerText=[System.IO.File]::ReadAllText([System.IO.Path]::Combine($packageRoot,"scripts","run_fastboot.ps1"))
foreach($guard in @("SHARPEMU_V74_0_16_DCC_RESIDENT_ALIAS_HISTORY","TryUseV74016DccAlias","RememberV74016DccAlias","SHARPEMU_DCC_ALIAS_HISTORY_MS","SHARPEMU_LARGE_TEXTURE_SNAPSHOT_REUSE_MS","history_hit=1")){
    if(-not $applyText.Contains($guard)){throw "[V74.0.16.1] Apply guard missing: $guard"}
}
if($applyText -match '(?i)Copy-Item[^\r\n]+payload[^\r\n]+(?:AgcExports|VulkanVideoPresenter|DirectExecutionBackend)'){throw "[V74.0.16.1] Whole-file source payload replacement forbidden."}
foreach($guard in @('$env:SHARPEMU_DCC_ALIAS_HISTORY_MS="2000"','$env:SHARPEMU_LARGE_TEXTURE_SNAPSHOT_REUSE_MS="10000"','$env:SHARPEMU_NATIVE_WORKER_MAX_CONCURRENT="2"','$env:SHARPEMU_RENDER_SCALE="0.25"','[string]::Format(','DCC_HISTORY','ErrorDeviceLost','HEAP_CORRUPTION')){
    if(-not $runnerText.Contains($guard)){throw "[V74.0.16.1] Runner guard missing: $guard"}
}
if($runnerText -match '(?ms)Write-Host\s*\(\s*"\[V74\.0\.16(?:\.1)?\] t=\{0:F0\}'){throw "[V74.0.16.1] Broken status-format regression detected."}

$applyText=[System.IO.File]::ReadAllText([System.IO.Path]::Combine($packageRoot,"scripts","apply_build.ps1"))
foreach($structuralGuard in @(
    "Get-V740161DccResultReasonAnchor -ResolverText `$resolver",
    "RememberV74016DccAlias(descriptor, alias, writerSequence);",
    "else if (TryUseV74016DccAlias(descriptor, out alias, out writerSequence))"
)){
    if(-not $applyText.Contains($structuralGuard)){
        throw "[V74.0.16.1] Structural patcher guard missing: $structuralGuard"
    }
}

$syntheticResolvers=@(
    '    reason = $"metadata_matches={metadataMatches};shape_matches={shapeMatches};resident_matches={residentMatches}"; return found;',
    '    reason = $"extra={candidateCount};metadata_matches={metadataMatches};shape_matches={shapeMatches};resident_matches={residentMatches};tail=1"; return found;',
    ('    reason =' + [Environment]::NewLine + '        $"metadata_matches={metadataMatches};shape_matches={shapeMatches};resident_matches={residentMatches}";' + [Environment]::NewLine + '    return found;')
)
$semanticSelfTests=0
foreach($syntheticResolver in $syntheticResolvers){
    $syntheticAnchor=Get-V740161DccResultReasonAnchor -ResolverText $syntheticResolver
    if($syntheticAnchor.Start -lt 0){
        throw "[V74.0.16.1] Semantic DCC anchor synthetic self-test failed."
    }
    $semanticSelfTests++
}

Write-Host "[V74.0.16.1] PACKAGE VALIDATION PASSED ($checked hashed files; $parsed PowerShell scripts parsed; $cmdTargets CMD targets verified; manifest coverage passed; reserved-variable audit passed; DCC semantic-anchor self-tests=$semanticSelfTests; DCC/snapshot guards passed)."
