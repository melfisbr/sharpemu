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


function Get-NativeWorkerMaxDeclaration {
    param([string]$Text)

    $name='NativeWorkerMaxConcurrent'
    $hits=[regex]::Matches($Text,[regex]::Escape($name))
    if($hits.Count -lt 1){ return $null }

    foreach($hit in $hits){
        $lineStart=$Text.LastIndexOf("`n",$hit.Index)
        if($lineStart -lt 0){$lineStart=0}else{$lineStart++}
        $lineEnd=$Text.IndexOf("`n",$hit.Index)
        if($lineEnd -lt 0){$lineEnd=$Text.Length}
        $line=$Text.Substring($lineStart,$lineEnd-$lineStart)

        if($line -match 'PrewarmNativeGuestWorkers|Math\.(Max|Min)\s*\('){ continue }

        if($line -match '^\s*(?:private|internal|public|protected)?\s*(?:static\s+)?(?:readonly\s+|const\s+)?int\s+NativeWorkerMaxConcurrent\b' -or
           $line -match '^\s*(?:private|internal|public|protected)?\s*(?:static\s+)?int\s+NativeWorkerMaxConcurrent\s*=>'){
            return [pscustomobject]@{Start=$lineStart;End=$lineEnd;Text=$line;Kind='SingleLine'}
        }

        $scanStart=$lineStart
        for($i=0;$i -lt 4;$i++){
            $prev=$Text.LastIndexOf("`n",[Math]::Max(0,$scanStart-2))
            if($prev -lt 0){$scanStart=0;break}
            $scanStart=$prev+1
        }
        $semi=$Text.IndexOf(';',$hit.Index)
        if($semi -gt $hit.Index -and $semi-$scanStart -lt 1200){
            $candidate=$Text.Substring($scanStart,$semi+1-$scanStart)
            if($candidate -match '(?s)\b(?:const|readonly|static|private|internal|public|protected|int)\b.*?\bNativeWorkerMaxConcurrent\b'){
                return [pscustomobject]@{Start=$scanStart;End=$semi+1;Text=$candidate;Kind='MultiLine'}
            }
        }
    }

    return $null
}

function Convert-NativeWorkerMaxDeclarationTo16 {
    param([string]$Declaration)

    if($Declaration -match 'NativeWorkerMaxConcurrent\s*=\s*\d+\s*;'){
        return [regex]::Replace(
            $Declaration,
            'NativeWorkerMaxConcurrent\s*=\s*\d+\s*;',
            'NativeWorkerMaxConcurrent = 16;',
            1)
    }

    if($Declaration -match 'NativeWorkerMaxConcurrent\s*=>\s*[^;]+;'){
        return [regex]::Replace(
            $Declaration,
            'NativeWorkerMaxConcurrent\s*=>\s*[^;]+;',
            'NativeWorkerMaxConcurrent => 16;',
            1)
    }

    $m=[regex]::Match($Declaration,'(?s)(\bNativeWorkerMaxConcurrent\b\s*=)\s*.+?;')
    if($m.Success){
        return $Declaration.Substring(0,$m.Index) +
            $m.Groups[1].Value + ' 16;' +
            $Declaration.Substring($m.Index+$m.Length)
    }

    throw "Recognized NativeWorkerMaxConcurrent declaration but cannot safely rewrite it."
}

