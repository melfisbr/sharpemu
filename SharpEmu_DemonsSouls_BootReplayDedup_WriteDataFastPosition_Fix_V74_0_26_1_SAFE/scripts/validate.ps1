Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$root=[IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'..'))
$manifest=[IO.Path]::Combine($root,'SHA256SUMS.txt')
if(-not [IO.File]::Exists($manifest)){
    throw 'SHA256SUMS.txt missing.'
}

$scripts=@(
    Get-ChildItem -LiteralPath ([IO.Path]::Combine($root,'scripts')) `
        -File `
        -Filter '*.ps1'
)

$blockedAutomaticVariables=@(
    'Host',
    'PID',
    'PSVersionTable',
    'PSScriptRoot',
    'PSCommandPath',
    'PSHome',
    'HOME',
    'PWD'
)

foreach($scriptFile in $scripts){
    $tokens=$null
    $errors=$null
    $ast=[System.Management.Automation.Language.Parser]::ParseFile(
        $scriptFile.FullName,
        [ref]$tokens,
        [ref]$errors)

    if($errors.Count -gt 0){
        $detail=@(
            $errors | ForEach-Object {
                "line=$($_.Extent.StartLineNumber) col=$($_.Extent.StartColumnNumber) $($_.Message)"
            }
        ) -join ' | '
        throw "PowerShell parse failed: $($scriptFile.Name): $detail"
    }

    $assignments=@(
        $ast.FindAll(
            {
                param($node)
                $node -is [System.Management.Automation.Language.AssignmentStatementAst]
            },
            $true)
    )

    foreach($assignment in $assignments){
        if($assignment.Left -is [System.Management.Automation.Language.VariableExpressionAst]){
            $name=$assignment.Left.VariablePath.UserPath
            if($blockedAutomaticVariables -contains $name){
                throw (
                    "Reserved/automatic PowerShell variable assignment in {0}: ${1} at line {2}" -f
                    $scriptFile.Name,
                    $name,
                    $assignment.Extent.StartLineNumber)
            }
        }
    }
}

foreach($line in [IO.File]::ReadAllLines($manifest)){
    if([string]::IsNullOrWhiteSpace($line)){
        continue
    }

    if($line -notmatch '^([0-9A-Fa-f]{64})  (.+)$'){
        throw "Bad manifest line: $line"
    }

    $path=[IO.Path]::Combine(
        $root,
        $matches[2].Replace('/','\'))

    if(-not [IO.File]::Exists($path)){
        throw "Manifest file missing: $path"
    }

    $actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    $expected=$matches[1].ToUpperInvariant()

    if($actual -ne $expected){
        throw "Manifest hash mismatch: $path expected=$expected actual=$actual"
    }
}

Write-Host (
    "[V74.0.26.1] PACKAGE VALIDATION PASSED ({0} PowerShell scripts parsed; reserved-variable scan passed; manifest verified)." -f
    $scripts.Count
) -ForegroundColor Green
