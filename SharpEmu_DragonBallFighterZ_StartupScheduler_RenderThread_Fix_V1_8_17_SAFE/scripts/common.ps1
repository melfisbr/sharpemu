$ErrorActionPreference="Stop"

function Find-RepoRoot {
    $cursor=(Resolve-Path $PSScriptRoot).Path
    for($i=0;$i -lt 8;$i++){
        $cli=Join-Path $cursor "src\SharpEmu.CLI\SharpEmu.CLI.csproj"
        $main=Join-Path $cursor "src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.cs"
        $worker=Join-Path $cursor "src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.NativeWorker.cs"
        if((Test-Path -LiteralPath $cli -PathType Leaf) -and
           (Test-Path -LiteralPath $main -PathType Leaf) -and
           (Test-Path -LiteralPath $worker -PathType Leaf)){return $cursor}
        $parent=Split-Path $cursor -Parent
        if([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $cursor){break}
        $cursor=$parent
    }
    throw "SharpEmu repository root not found."
}
