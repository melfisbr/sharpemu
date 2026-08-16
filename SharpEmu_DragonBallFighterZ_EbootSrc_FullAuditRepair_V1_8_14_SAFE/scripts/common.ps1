$ErrorActionPreference = "Stop"

function Find-RepoRoot {
    $cursor = (Resolve-Path $PSScriptRoot).Path
    for ($i = 0; $i -lt 8; $i++) {
        $cli = Join-Path $cursor "src\SharpEmu.CLI\SharpEmu.CLI.csproj"
        $kernel = Join-Path $cursor "src\SharpEmu.Libs\Kernel\KernelMemoryCompatExports.cs"
        $ngs = Join-Path $cursor "src\SharpEmu.Libs\Ngs2\Ngs2Exports.cs"
        if ((Test-Path -LiteralPath $cli -PathType Leaf) -and
            (Test-Path -LiteralPath $kernel -PathType Leaf) -and
            (Test-Path -LiteralPath $ngs -PathType Leaf)) {
            return $cursor
        }
        $parent = Split-Path $cursor -Parent
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $cursor) { break }
        $cursor = $parent
    }
    throw "SharpEmu repository root not found."
}

function Get-KernelPath([string]$RepoRoot) {
    Join-Path $RepoRoot "src\SharpEmu.Libs\Kernel\KernelMemoryCompatExports.cs"
}
function Get-Ngs2Path([string]$RepoRoot) {
    Join-Path $RepoRoot "src\SharpEmu.Libs\Ngs2\Ngs2Exports.cs"
}
function Get-EbootPath {
    'F:\JOGOSPS5\[DLPSGAME.COM]-PPSA09790\[DLPSGAME.COM]-PPSA09790\PPSA09790-app\eboot.bin'
}
