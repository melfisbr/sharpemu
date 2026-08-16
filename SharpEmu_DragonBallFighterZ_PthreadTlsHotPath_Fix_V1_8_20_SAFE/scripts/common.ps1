$ErrorActionPreference="Stop"

function Find-RepoRoot {
    $cursor=(Resolve-Path $PSScriptRoot).Path
    for($i=0;$i -lt 8;$i++){
        $target=Join-Path $cursor "src\SharpEmu.Libs\Kernel\KernelPthreadExtendedCompatExports.cs"
        $cli=Join-Path $cursor "src\SharpEmu.CLI\SharpEmu.CLI.csproj"
        if((Test-Path -LiteralPath $target -PathType Leaf) -and
           (Test-Path -LiteralPath $cli -PathType Leaf)){ return $cursor }
        $parent=Split-Path $cursor -Parent
        if([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $cursor){ break }
        $cursor=$parent
    }
    throw "SharpEmu repository root not found."
}

function Find-MethodBlock {
    param([string]$Text,[string]$Signature)
    $s=$Text.IndexOf($Signature,[StringComparison]::Ordinal)
    if($s -lt 0){ return $null }
    $open=$Text.IndexOf('{',$s)
    if($open -lt 0){ return $null }
    $depth=0
    $inString=$false
    $escape=$false
    for($i=$open;$i -lt $Text.Length;$i++){
        $c=$Text[$i]
        if($inString){
            if($escape){$escape=$false;continue}
            if($c -eq '\'){$escape=$true;continue}
            if($c -eq '"'){$inString=$false}
            continue
        }
        if($c -eq '"'){$inString=$true;continue}
        if($c -eq '{'){$depth++}
        elseif($c -eq '}'){
            $depth--
            if($depth -eq 0){
                return [pscustomobject]@{Start=$s;Open=$open;End=$i+1;Text=$Text.Substring($s,$i+1-$s)}
            }
        }
    }
    return $null
}
