Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Resolve-RepoRoot([string]$RepositoryRoot) {
    if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
        return (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
    }
    return (Resolve-Path -LiteralPath $RepositoryRoot).Path
}

function Has-OrdinalIgnoreCase([string]$Text,[string]$Pattern) {
    if ($null -eq $Text -or $null -eq $Pattern) { return $false }
    return $Text.IndexOf($Pattern,[StringComparison]::OrdinalIgnoreCase) -ge 0
}

function Read-BinaryStrings([string]$Path) {
    $bytes=[IO.File]::ReadAllBytes($Path)
    return @(
        [Text.Encoding]::ASCII.GetString($bytes),
        [Text.Encoding]::Unicode.GetString($bytes)
    )
}

function Add-Matches(
    [Collections.Generic.List[string]]$Out,
    [string]$Path,
    [string[]]$Patterns,
    [int]$Context=18)
{
    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $lines=[IO.File]::ReadAllLines($Path)
    foreach($pattern in $Patterns) {
        for($i=0;$i -lt $lines.Length;$i++) {
            if ($lines[$i].IndexOf($pattern,[StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $a=[Math]::Max(0,$i-$Context)
                $b=[Math]::Min($lines.Length-1,$i+$Context)
                $Out.Add("===== $Path pattern='$pattern' line=$($i+1) =====")
                for($j=$a;$j -le $b;$j++) {
                    $Out.Add(('{0,6}: {1}' -f ($j+1),$lines[$j]))
                }
            }
        }
    }
}
