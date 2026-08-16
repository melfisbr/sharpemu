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

$reserved=@(
    'Host','HOME','PWD','PID','PSHOME','ShellId','Input','Args','Error',
    'Matches','LASTEXITCODE','MyInvocation','PSScriptRoot','PSCommandPath',
    'StackTrace','ExecutionContext','PSBoundParameters','PSVersionTable',
    'PSEdition','NestedPromptLevel','PSItem','_','this'
)
$reservedSet=[Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)
foreach($name in $reserved){[void]$reservedSet.Add($name)}

foreach($scriptFile in $scripts){
    $tokens=$null
    $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile(
        $scriptFile.FullName,[ref]$tokens,[ref]$errors)

    if($errors.Count -gt 0){
        $detail=@($errors|ForEach-Object{
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
            $name=$node.Left.VariablePath.UserPath
            if($reservedSet.Contains($name)){
                throw "Reserved automatic-variable assignment: $($scriptFile.Name) -> $name"
            }
        }
    }

    foreach($node in $ast.FindAll(
        {param($candidate)
            $candidate -is [Management.Automation.Language.ParameterAst]},
        $true))
    {
        $name=$node.Name.VariablePath.UserPath
        if($reservedSet.Contains($name)){
            throw "Reserved automatic-variable parameter: $($scriptFile.Name) -> $name"
        }
    }

    foreach($node in $ast.FindAll(
        {param($candidate)
            $candidate -is [Management.Automation.Language.ForEachStatementAst]},
        $true))
    {
        $name=$node.Variable.VariablePath.UserPath
        if($reservedSet.Contains($name)){
            throw "Reserved automatic-variable foreach binder: $($scriptFile.Name) -> $name"
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
    "[V74.0.26.2] PACKAGE VALIDATION PASSED ({0} PowerShell scripts parsed; reserved-variable binder audit passed; manifest verified)." -f
    $scripts.Count
) -ForegroundColor Green
