param()
. (Join-Path $PSScriptRoot 'common.ps1')

$manifest=Join-Path $script:PackageRoot 'manifest.sha256'
if(-not(Test-Path -LiteralPath $manifest -PathType Leaf)){
    throw "$script:Tag manifest missing"
}

$entries=@(
    Get-Content -LiteralPath $manifest |
        Where-Object { $_ -and (-not $_.StartsWith('#')) }
)

foreach($line in $entries){
    if($line -notmatch '^([0-9A-Fa-f]{64})  (.+)$'){
        throw "$script:Tag malformed manifest line: $line"
    }
    $expected=$matches[1].ToUpperInvariant()
    $relative=$matches[2]
    $path=Join-Path $script:PackageRoot $relative.Replace('/','\')
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){
        throw "$script:Tag manifest file missing: $relative"
    }
    $actual=(Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToUpperInvariant()
    if($actual -ne $expected){
        throw "$script:Tag manifest mismatch: $relative"
    }
}

$parseFailures=@()
foreach($file in Get-ChildItem -LiteralPath $PSScriptRoot -File -Filter '*.ps1'){
    $tokens=$null
    $parseErrors=$null
    [void][Management.Automation.Language.Parser]::ParseFile(
        $file.FullName,
        [ref]$tokens,
        [ref]$parseErrors)
    if(@($parseErrors).Count -ne 0){
        $messages=@($parseErrors|ForEach-Object{$_.Message}) -join '; '
        $parseFailures += "$($file.Name): $messages"
    }
}
if($parseFailures.Count -ne 0){
    throw "$script:Tag PowerShell parse failed: $($parseFailures -join ' | ')"
}

Write-Tag "PACKAGE VALIDATION PASSED ($($entries.Count) hashed files; PowerShell parsed)."
