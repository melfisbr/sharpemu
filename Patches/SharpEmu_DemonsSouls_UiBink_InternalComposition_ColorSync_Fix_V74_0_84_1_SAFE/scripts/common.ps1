$ErrorActionPreference='Stop'
function PackageRoot { (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path }
function RepoRoot {
    $pkg = PackageRoot
    $patches = Split-Path -Parent $pkg
    $repo = Split-Path -Parent $patches
    if (-not (Test-Path -LiteralPath (Join-Path $repo 'src\SharpEmu.Libs\SharpEmu.Libs.csproj'))) {
        throw "SharpEmu repo not found: $repo"
    }
    $repo
}
function Patches { Split-Path -Parent (PackageRoot) }
function Host { Join-Path (RepoRoot) 'src\SharpEmu.Libs\Media\HostMovieBridge.cs' }
function Assist { Join-Path (RepoRoot) 'src\SharpEmu.Libs\Media\BinkHostPlaybackAssist.cs' }
function Presenter { Join-Path (RepoRoot) 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs' }
function Sha([string]$p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToUpperInvariant() }
function NL([string]$s) { $s.Replace("`r`n","`n").Replace("`r","`n") }
function CountExact([string]$s,[string]$n) {
    $c=0; $p=0
    while ($true) {
        $i=$s.IndexOf($n,$p,[StringComparison]::Ordinal)
        if ($i -lt 0) { break }
        $c++
        $p=$i+$n.Length
    }
    $c
}
function Patch([string]$name) {
    $path = Join-Path (PackageRoot) ("patch\"+$name)
    $raw = [IO.File]::ReadAllText($path)
    NL $raw
}
function FindMethodSpan([string]$text,[string]$declPattern,[string]$label) {
    $rx=[regex]::new($declPattern,[Text.RegularExpressions.RegexOptions]::Multiline)
    $ms=$rx.Matches($text)
    if ($ms.Count -ne 1) { throw "$label declaration count=$($ms.Count)" }
    $decl=$ms[0]
    $open=$text.IndexOf('{',$decl.Index+$decl.Length)
    if ($open -lt 0) { throw "$label opening brace missing" }
    $depth=0; $line=$false; $block=$false; $str=$false; $verb=$false; $chr=$false; $esc=$false
    for ($i=$open; $i -lt $text.Length; $i++) {
        $c=$text[$i]
        $n=if ($i+1 -lt $text.Length) { $text[$i+1] } else { [char]0 }
        if ($line) { if ($c -eq "`n") { $line=$false }; continue }
        if ($block) { if ($c -eq '*' -and $n -eq '/') { $block=$false; $i++ }; continue }
        if ($str) {
            if ($verb) { if ($c -eq '"') { if ($n -eq '"') { $i++; continue }; $str=$false; $verb=$false }; continue }
            if ($esc) { $esc=$false; continue }
            if ($c -eq '\') { $esc=$true; continue }
            if ($c -eq '"') { $str=$false }
            continue
        }
        if ($chr) {
            if ($esc) { $esc=$false; continue }
            if ($c -eq '\') { $esc=$true; continue }
            if ($c -eq "'") { $chr=$false }
            continue
        }
        if ($c -eq '/' -and $n -eq '/') { $line=$true; $i++; continue }
        if ($c -eq '/' -and $n -eq '*') { $block=$true; $i++; continue }
        if ($c -eq '@' -and $n -eq '"') { $str=$true; $verb=$true; $i++; continue }
        if ($c -eq '"') { $str=$true; continue }
        if ($c -eq "'") { $chr=$true; continue }
        if ($c -eq '{') { $depth++; continue }
        if ($c -eq '}') {
            $depth--
            if ($depth -eq 0) {
                return [pscustomobject]@{
                    Decl=$decl.Index; Open=$open; Close=$i; BodyStart=$open+1; BodyLen=$i-$open-1
                }
            }
        }
    }
    throw "$label closing brace missing"
}
function Body([string]$text,$span) { $text.Substring($span.BodyStart,$span.BodyLen) }
function ReplaceBody([string]$text,$span,[string]$body) { $text.Substring(0,$span.BodyStart)+$body+$text.Substring($span.Close) }
function InsertBodyStart([string]$text,[string]$pattern,[string]$label,[string]$insert) {
    $s=FindMethodSpan $text $pattern $label
    $b=Body $text $s
    ReplaceBody $text $s ("`n"+$insert.Trim("`n")+$b)
}
function WritePreserving([string]$path,[string]$text) {
    $bytes=[IO.File]::ReadAllBytes($path)
    $bom=$bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $raw=[IO.File]::ReadAllText($path)
    $lf=[regex]::Matches($raw,"`n").Count
    $crlf=[regex]::Matches($raw,"`r`n").Count
    $out=if ($crlf -ge [Math]::Max(1,[int]($lf*0.8))) { $text.Replace("`n","`r`n") } else { $text }
    [IO.File]::WriteAllText($path,$out,(New-Object Text.UTF8Encoding($bom)))
}
function GetBaseChromaOrder([string]$presenterText) {
    $span=FindMethodSpan $presenterText '(?m)^[ \t]*internal static void ConvertBgraToYuv420\(' 'ConvertBgraToYuv420'
    $b=Body $presenterText $span
    $cb='((-29 * red - 99 * green + 128 * blue + 128) >> 8) + 128'
    $cr='((128 * red - 116 * green - 12 * blue + 128) >> 8) + 128'
    $u=$b.IndexOf($cb,[StringComparison]::Ordinal)
    $v=$b.IndexOf($cr,[StringComparison]::Ordinal)
    if ($u -lt 0 -or $v -lt 0) { throw 'Unable to classify current BGRA->YUV chroma formulas.' }
    if ($u -lt $v) { return 'UV' }
    return 'VU'
}
