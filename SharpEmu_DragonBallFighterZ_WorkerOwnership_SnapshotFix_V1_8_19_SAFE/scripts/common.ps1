$ErrorActionPreference="Stop"

function Find-RepoRoot {
    $cursor=(Resolve-Path $PSScriptRoot).Path
    for($i=0;$i -lt 8;$i++){
        $main=Join-Path $cursor "src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.cs"
        $worker=Join-Path $cursor "src\SharpEmu.Core\Cpu\Native\DirectExecutionBackend.NativeWorker.cs"
        $cli=Join-Path $cursor "src\SharpEmu.CLI\SharpEmu.CLI.csproj"
        if((Test-Path -LiteralPath $main -PathType Leaf) -and
           (Test-Path -LiteralPath $worker -PathType Leaf) -and
           (Test-Path -LiteralPath $cli -PathType Leaf)){ return $cursor }
        $parent=Split-Path $cursor -Parent
        if([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $cursor){ break }
        $cursor=$parent
    }
    throw "SharpEmu repository root not found."
}

function Get-WorkerCap {
    param([string]$Text)
    $m=[regex]::Match($Text,'(?m)^\s*(?:private|internal|public|protected)?\s*(?:static\s+)?(?:readonly\s+|const\s+)?int\s+NativeWorkerMaxConcurrent\s*=\s*(?<v>\d+)\s*;')
    if(-not $m.Success){ return $null }
    return [pscustomobject]@{ Start=$m.Index; Length=$m.Length; Text=$m.Value; Value=[int]$m.Groups['v'].Value }
}
