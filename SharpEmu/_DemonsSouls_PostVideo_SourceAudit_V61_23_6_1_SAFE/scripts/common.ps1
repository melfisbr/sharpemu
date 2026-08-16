Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Resolve-RepoRoot([string]$RepositoryRoot) {
    if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
        return (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
    }
    return (Resolve-Path $RepositoryRoot).Path
}
function Add-Matches([Collections.Generic.List[string]]$Out,[string]$Path,[string[]]$Patterns,[int]$Context=8) {
    if (!(Test-Path -LiteralPath $Path)) { return }
    $lines=[IO.File]::ReadAllLines($Path)
    $seen=[Collections.Generic.HashSet[int]]::new()
    foreach($pattern in $Patterns) {
        for($i=0;$i -lt $lines.Length;$i++) {
            if ($lines[$i].IndexOf($pattern,[StringComparison]::Ordinal) -ge 0) {
                $a=[Math]::Max(0,$i-$Context); $b=[Math]::Min($lines.Length-1,$i+$Context)
                $Out.Add("===== $Path pattern='$pattern' line=$($i+1) =====")
                for($j=$a;$j -le $b;$j++) { $Out.Add(('{0,6}: {1}' -f ($j+1),$lines[$j])) }
            }
        }
    }
}
