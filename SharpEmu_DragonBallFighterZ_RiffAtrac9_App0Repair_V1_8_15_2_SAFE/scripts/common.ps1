$ErrorActionPreference="Stop"
function Find-RepoRoot {
    $cursor=(Resolve-Path $PSScriptRoot).Path
    for($i=0;$i -lt 8;$i++){
        $cli=Join-Path $cursor "src\SharpEmu.CLI\SharpEmu.CLI.csproj"
        $ngs=Join-Path $cursor "src\SharpEmu.Libs\Ngs2\Ngs2Exports.cs"
        $kernel=Join-Path $cursor "src\SharpEmu.Libs\Kernel\KernelMemoryCompatExports.cs"
        if((Test-Path -LiteralPath $cli -PathType Leaf) -and
           (Test-Path -LiteralPath $ngs -PathType Leaf) -and
           (Test-Path -LiteralPath $kernel -PathType Leaf)){return $cursor}
        $parent=Split-Path $cursor -Parent
        if([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $cursor){break}
        $cursor=$parent
    }
    throw "SharpEmu repository root not found."
}
