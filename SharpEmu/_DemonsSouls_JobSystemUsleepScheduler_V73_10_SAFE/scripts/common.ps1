Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-RepoRoot {
    param([string]$RepositoryRoot)
    if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
        return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path
    }
    return (Resolve-Path -LiteralPath $RepositoryRoot).Path
}

function Get-PackageRoot {
    return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
}

function Test-ContainsOrdinal {
    param([string]$Text,[string]$Pattern)
    if ($null -eq $Text -or $null -eq $Pattern) { return $false }
    return $Text.IndexOf($Pattern,[StringComparison]::Ordinal) -ge 0
}

function Write-Utf8Lines {
    param([string]$Path,[System.Collections.IEnumerable]$Lines)
    $items=New-Object System.Collections.Generic.List[string]
    foreach($line in $Lines){$items.Add([string]$line)}
    [IO.File]::WriteAllLines($Path,$items.ToArray(),[Text.UTF8Encoding]::new($false))
}

function Get-MaxPageShare821 {
    param([string[]]$Lines)
    $max=0.0
    foreach($line in $Lines){
        $m=[regex]::Match($line,'0x800821000\(app\+0x821000\)=([0-9]+(?:[\.,][0-9]+)?)%')
        if(-not $m.Success){continue}
        $text=$m.Groups[1].Value.Replace(',','.')
        $value=0.0
        if([double]::TryParse(
            $text,
            [Globalization.NumberStyles]::Float,
            [Globalization.CultureInfo]::InvariantCulture,
            [ref]$value) -and $value -gt $max){
            $max=$value
        }
    }
    return $max
}
