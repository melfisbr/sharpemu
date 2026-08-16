$ErrorActionPreference="Stop"

function Find-RepoRoot {
    $cursor=(Resolve-Path $PSScriptRoot).Path
    for($i=0;$i -lt 8;$i++) {
        if((Test-Path -LiteralPath (Join-Path $cursor "src\SharpEmu.CLI\SharpEmu.CLI.csproj") -PathType Leaf) -and
           (Test-Path -LiteralPath (Join-Path $cursor "src\SharpEmu.Libs\Kernel\KernelMemoryCompatExports.cs") -PathType Leaf) -and
           (Test-Path -LiteralPath (Join-Path $cursor "src\SharpEmu.Libs\Ngs2\Ngs2Exports.cs") -PathType Leaf)) {
            return $cursor
        }
        $parent=Split-Path $cursor -Parent
        if([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $cursor){break}
        $cursor=$parent
    }
    throw "SharpEmu repository root not found."
}

function Find-SourceEvidence([string]$Repo,[string[]]$Patterns) {
    $hits=[System.Collections.Generic.List[string]]::new()
    foreach($f in Get-ChildItem -LiteralPath (Join-Path $Repo "src") -Recurse -File -Filter *.cs) {
        $t=Get-Content -LiteralPath $f.FullName -Raw
        foreach($p in $Patterns) {
            if($t.Contains($p)) {
                $hits.Add($f.FullName.Substring($Repo.Length+1))
                break
            }
        }
    }
    return @($hits | Sort-Object -Unique)
}
