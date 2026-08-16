$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
$packageRoot=[System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$manifest=[System.IO.Path]::Combine($packageRoot,"SHA256SUMS.txt")
if(-not [System.IO.File]::Exists($manifest)){throw "[V74.0.22] SHA256SUMS.txt missing."}

$manifestPaths=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$checked=0
foreach($manifestLine in Get-Content -LiteralPath $manifest){
    if([string]::IsNullOrWhiteSpace($manifestLine)){continue}
    if($manifestLine -notmatch '^([0-9A-Fa-f]{64})  (.+)$'){throw "[V74.0.22] Invalid manifest line: $manifestLine"}
    $expectedHash=$Matches[1].ToUpperInvariant()
    $relativePath=$Matches[2].Replace('/',[System.IO.Path]::DirectorySeparatorChar)
    if([System.IO.Path]::IsPathRooted($relativePath) -or $relativePath -match '(^|[\\/])\.\.([\\/]|$)'){throw "[V74.0.22] Unsafe manifest path: $relativePath"}
    if(-not $manifestPaths.Add($relativePath)){throw "[V74.0.22] Duplicate manifest path: $relativePath"}
    $filePath=[System.IO.Path]::Combine($packageRoot,$relativePath)
    if(-not [System.IO.File]::Exists($filePath)){throw "[V74.0.22] Missing package file: $relativePath"}
    $actualHash=(Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash.ToUpperInvariant()
    if($actualHash -ne $expectedHash){throw "[V74.0.22] Hash mismatch: $relativePath"}
    $checked++
}
foreach($packageFile in Get-ChildItem -LiteralPath $packageRoot -Recurse -File){
    if($packageFile.FullName -eq $manifest){continue}
    $coveredRelative=$packageFile.FullName.Substring($packageRoot.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar,[System.IO.Path]::AltDirectorySeparatorChar)
    if(-not $manifestPaths.Contains($coveredRelative)){throw "[V74.0.22] Unmanifested package file: $coveredRelative"}
}

$parsed=0
foreach($powerShellFile in Get-ChildItem -LiteralPath $packageRoot -Recurse -File -Filter "*.ps1"){
    $tokenData=$null
    $parseErrors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($powerShellFile.FullName,[ref]$tokenData,[ref]$parseErrors)
    if(@($parseErrors).Count -gt 0){
        $details=(@($parseErrors)|ForEach-Object{$_.Message}) -join ' | '
        throw "[V74.0.22] PowerShell parse failure: $($powerShellFile.Name): $details"
    }
    $parsed++
}

$cmdTargets=0
foreach($cmdFile in Get-ChildItem -LiteralPath $packageRoot -File -Filter "*.cmd"){
    $foundTarget=$false
    foreach($cmdLine in Get-Content -LiteralPath $cmdFile.FullName){
        if($cmdLine -match '(?i)-File\s+"%~dp0([^\"]+\.ps1)"'){
            $target=[System.IO.Path]::Combine($packageRoot,$Matches[1])
            if(-not [System.IO.File]::Exists($target)){throw "[V74.0.22] CMD target missing: $($cmdFile.Name) -> $($Matches[1])"}
            $foundTarget=$true
            $cmdTargets++
        }
    }
    if(-not $foundTarget){throw "[V74.0.22] CMD has no PowerShell target: $($cmdFile.Name)"}
}
if($cmdTargets -ne 4){throw "[V74.0.22] Expected 4 CMD targets, got $cmdTargets."}

# Automatic/reserved variable binder audit: assignments, parameters and foreach binders.
$reserved=@('Host','HOME','PWD','PID','PSHOME','ShellId','Input','Args','Error','Matches','LASTEXITCODE','MyInvocation','PSScriptRoot','PSCommandPath','StackTrace','ExecutionContext','PSBoundParameters','PSVersionTable','PSEdition','NestedPromptLevel','PSItem','_','this')
$reservedSet=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($reservedName in $reserved){[void]$reservedSet.Add($reservedName)}
foreach($powerShellFile in Get-ChildItem -LiteralPath $packageRoot -Recurse -File -Filter "*.ps1"){
    $tokens=$null;$errors=$null
    $ast=[System.Management.Automation.Language.Parser]::ParseFile($powerShellFile.FullName,[ref]$tokens,[ref]$errors)
    $bad=New-Object 'System.Collections.Generic.List[string]'
    foreach($node in $ast.FindAll({param($candidate) $candidate -is [System.Management.Automation.Language.AssignmentStatementAst]},$true)){
        if($node.Left -is [System.Management.Automation.Language.VariableExpressionAst]){
            $name=$node.Left.VariablePath.UserPath
            if($reservedSet.Contains($name)){$bad.Add("assignment:$name")}
        }
    }
    foreach($node in $ast.FindAll({param($candidate) $candidate -is [System.Management.Automation.Language.ParameterAst]},$true)){
        $name=$node.Name.VariablePath.UserPath
        if($reservedSet.Contains($name)){$bad.Add("parameter:$name")}
    }
    foreach($node in $ast.FindAll({param($candidate) $candidate -is [System.Management.Automation.Language.ForEachStatementAst]},$true)){
        $name=$node.Variable.VariablePath.UserPath
        if($reservedSet.Contains($name)){$bad.Add("foreach:$name")}
    }
    if($bad.Count -gt 0){throw "[V74.0.22] Reserved automatic-variable binder in $($powerShellFile.Name): $($bad -join ', ')"}
}

$runner=[System.IO.File]::ReadAllText([System.IO.Path]::Combine($packageRoot,"scripts","run_guest_owned_boot.ps1"))
foreach($guard in @(
    'SHARPEMU_BINK_AUTO_BOOT="0"',
    'SHARPEMU_BINK_STARTUP_COMPLETION_SHIM="1"',
    'runner_auto_kill=False',
    'exit_policy=user-closes-window-or-runtime-exits',
    'this runner does NOT close SharpEmu',
    'HOST_MOVIE_BRIDGE_CHANGED=False'
)){
    if(-not $runner.Contains($guard)){throw "[V74.0.22] Runner guard missing: $guard"}
}
if($runner -match '(?i)Stop-ProcessTreeV74022|Stop-Process\s+-Id'){
    throw "[V74.0.22] RUN_4 contains a process-kill call; no-auto-kill contract violated."
}
if($runner -match '(?i)absoluteDeadline|postProofSeconds|abi-proof-plus-observation'){
    throw "[V74.0.22] Old V74.0.21 auto-stop logic leaked into RUN_4."
}
$apply=[System.IO.File]::ReadAllText([System.IO.Path]::Combine($packageRoot,"scripts","apply_build.ps1"))
if($apply -match '(?i)WriteAllText|Copy-Item[^\r\n]*Destination[^\r\n]*src\\'){
    throw "[V74.0.22] RUN_3 contains a source-write primitive; this revision must be build-only."
}

Write-Host "[V74.0.22] PACKAGE VALIDATION PASSED ($checked hashed files; $parsed PowerShell scripts parsed; $cmdTargets CMD targets verified; manifest coverage passed; reserved-variable binder audit passed; no-auto-kill contract passed)."
