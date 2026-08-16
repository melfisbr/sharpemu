Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=[IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'..'))
$manifest=[IO.Path]::Combine($root,'SHA256SUMS.txt')
if(-not [IO.File]::Exists($manifest)){
    throw 'SHA256SUMS.txt missing.'
}

$scripts=@(
    Get-ChildItem -LiteralPath ([IO.Path]::Combine($root,'scripts')) `
        -File -Filter '*.ps1'
)

$reservedNames=@(
    'Host','HOME','PWD','PID','PSHOME','ShellId','Input','Args','Error',
    'Matches','LASTEXITCODE','MyInvocation','PSScriptRoot','PSCommandPath',
    'StackTrace','ExecutionContext','PSBoundParameters','PSVersionTable',
    'PSEdition','NestedPromptLevel','PSItem','_','this'
)
$reservedSet=[Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)
foreach($reservedName in $reservedNames){
    [void]$reservedSet.Add($reservedName)
}

foreach($scriptFile in $scripts){
    $tokens=$null
    $parseErrors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile(
        $scriptFile.FullName,
        [ref]$tokens,
        [ref]$parseErrors)

    if($parseErrors.Count -gt 0){
        $detail=@($parseErrors|ForEach-Object{
            "line=$($_.Extent.StartLineNumber) col=$($_.Extent.StartColumnNumber) $($_.Message)"
        }) -join ' | '
        throw "PowerShell parse failed: $($scriptFile.Name): $detail"
    }

    foreach($node in $ast.FindAll(
        {param($candidate)
            $candidate -is [Management.Automation.Language.AssignmentStatementAst]},
        $true))
    {
        if($node.Left -is [Management.Automation.Language.VariableExpressionAst]){
            $variableName=$node.Left.VariablePath.UserPath
            if($reservedSet.Contains($variableName)){
                throw "Reserved automatic-variable assignment: $($scriptFile.Name) -> $variableName"
            }
        }
    }

    foreach($node in $ast.FindAll(
        {param($candidate)
            $candidate -is [Management.Automation.Language.ParameterAst]},
        $true))
    {
        $variableName=$node.Name.VariablePath.UserPath
        if($reservedSet.Contains($variableName)){
            throw "Reserved automatic-variable parameter: $($scriptFile.Name) -> $variableName"
        }
    }

    foreach($node in $ast.FindAll(
        {param($candidate)
            $candidate -is [Management.Automation.Language.ForEachStatementAst]},
        $true))
    {
        $variableName=$node.Variable.VariablePath.UserPath
        if($reservedSet.Contains($variableName)){
            throw "Reserved automatic-variable foreach binder: $($scriptFile.Name) -> $variableName"
        }
    }
}

foreach($line in [IO.File]::ReadAllLines($manifest)){
    if([string]::IsNullOrWhiteSpace($line)){continue}

    if($line -notmatch '^([0-9A-Fa-f]{64})  (.+)$'){
        throw "Invalid manifest line: $line"
    }

    $expected=$matches[1].ToUpperInvariant()
    $relative=$matches[2].Replace('/','\')
    $path=[IO.Path]::Combine($root,$relative)

    if(-not [IO.File]::Exists($path)){
        throw "Manifest file missing: $relative"
    }

    $actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if($actual -ne $expected){
        throw "Manifest hash mismatch: $relative"
    }
}

Write-Host (
    "[V74.0.26.3] PACKAGE VALIDATION PASSED ({0} PowerShell scripts parsed; reserved-variable binder audit passed; manifest verified)." -f
    $scripts.Count
) -ForegroundColor Green
