Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'

$script:Tag='[V74.0.86.1.4]'
$script:ImeRel='src\SharpEmu.Libs\Ime\ImeDialogExports.cs'
$script:PresenterRel='src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'

function PackageRoot { return (Split-Path -Parent $PSScriptRoot) }
function Patches { return (Split-Path -Parent (PackageRoot)) }
function RepoRoot { return (Split-Path -Parent (Patches)) }
function ImeDialogSource { return (Join-Path (RepoRoot) $script:ImeRel) }
function PresenterSource { return (Join-Path (RepoRoot) $script:PresenterRel) }
function CliProject { return (Join-Path (RepoRoot) 'src\SharpEmu.CLI\SharpEmu.CLI.csproj') }
function ExePath { return (Join-Path (RepoRoot) 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe') }
function ImePayload { return (Join-Path (PackageRoot) 'payload\ImeDialogExports.cs') }
function NL([string]$s) { return $s.Replace("`r`n","`n").Replace("`r","`n") }
function Sha([string]$p) { return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToUpperInvariant() }

function WritePreserving([string]$Path,[string]$Text) {
    $bytes=[IO.File]::ReadAllBytes($Path)
    $bom=$bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $raw=[IO.File]::ReadAllText($Path)
    $lf=[regex]::Matches($raw,"`n").Count
    $crlf=[regex]::Matches($raw,"`r`n").Count
    $useCrlf=$crlf -ge [Math]::Max(1,[int]($lf*0.8))
    $outText=if($useCrlf){$Text.Replace("`n","`r`n")}else{$Text}
    [IO.File]::WriteAllText($Path,$outText,(New-Object Text.UTF8Encoding($bom)))
}

function FindMethodSpan([string]$Text,[string]$DeclarationRegex,[string]$Label) {
    $rx=[regex]::new($DeclarationRegex,[Text.RegularExpressions.RegexOptions]::Multiline)
    $matches=$rx.Matches($Text)
    if($matches.Count -ne 1){ throw "$Label declaration count=$($matches.Count)" }
    $decl=$matches[0]
    $open=$Text.IndexOf('{',$decl.Index+$decl.Length)
    if($open -lt 0){ throw "$Label opening brace not found" }

    $depth=0
    $inString=$false
    $verbatim=$false
    $inChar=$false
    $escape=$false
    $lineComment=$false
    $blockComment=$false

    for($i=$open;$i -lt $Text.Length;$i++){
        $ch=$Text[$i]
        $next=if($i+1 -lt $Text.Length){$Text[$i+1]}else{[char]0}

        if($lineComment){
            if($ch -eq "`n"){$lineComment=$false}
            continue
        }
        if($blockComment){
            if($ch -eq '*' -and $next -eq '/'){$blockComment=$false;$i++}
            continue
        }
        if($inString){
            if($verbatim){
                if($ch -eq '"'){
                    if($next -eq '"'){$i++;continue}
                    $inString=$false
                    $verbatim=$false
                }
                continue
            }
            if($escape){$escape=$false;continue}
            if($ch -eq '\'){$escape=$true;continue}
            if($ch -eq '"'){$inString=$false}
            continue
        }
        if($inChar){
            if($escape){$escape=$false;continue}
            if($ch -eq '\'){$escape=$true;continue}
            if($ch -eq "'"){$inChar=$false}
            continue
        }

        if($ch -eq '/' -and $next -eq '/'){$lineComment=$true;$i++;continue}
        if($ch -eq '/' -and $next -eq '*'){$blockComment=$true;$i++;continue}
        if($ch -eq '@' -and $next -eq '"'){$inString=$true;$verbatim=$true;$i++;continue}
        if($ch -eq '"'){$inString=$true;continue}
        if($ch -eq "'"){$inChar=$true;continue}

        if($ch -eq '{'){$depth++;continue}
        if($ch -eq '}'){
            $depth--
            if($depth -eq 0){
                return [pscustomobject]@{
                    DeclarationStart=$decl.Index
                    OpenBrace=$open
                    CloseBrace=$i
                    BodyStart=$open+1
                    BodyLength=$i-$open-1
                }
            }
        }
    }

    throw "$Label closing brace not found"
}

function MethodBody([string]$Text,$Span) {
    return $Text.Substring($Span.BodyStart,$Span.BodyLength)
}

function ReplaceMethodBody([string]$Text,$Span,[string]$Body) {
    return $Text.Substring(0,$Span.BodyStart)+$Body+$Text.Substring($Span.CloseBrace)
}

function Find-LastTopLevelReturnLine([string]$Body) {
    $rx=[regex]::new('(?m)^(?<indent>[ \t]*)return\b[^\r\n;]*;[ \t]*$')
    $matches=$rx.Matches($Body)
    if($matches.Count -lt 1){
        throw "FindHostMovieTextureBindings has no simple return statement"
    }
    return $matches[$matches.Count-1]
}

function Apply-PresenterV7408614([string]$Text) {
    if($Text.Contains('SHARPEMU_V74_0_86_1_4_UI_BINK_FINAL_RETURN_LEARN')){
        return $Text
    }

    foreach($required in @(
        'SHARPEMU_V74_0_86_DS_CHARACTER_CREATOR_TYPED_DCC',
        'SHARPEMU_V74_0_84_2_1_UI_BINK_FRAME_OWNERSHIP',
        'SHARPEMU_V74_0_84_2_1_UI_BINK_STICKY_PLANE_INTEGRITY',
        '_v740842LearnedUiBinkLumaAddresses',
        '_v740842LearnedUiBinkChromaAddresses',
        '_v740842UiBinkPlaneLearnCount',
        'IsUiBinkStickyPlaneEnabledV740842()'))
    {
        if(-not $Text.Contains($required)){
            throw "Required accumulated marker missing: $required"
        }
    }

    $span=FindMethodSpan $Text '(?m)^[ \t]*private HostMovieTextureBindings FindHostMovieTextureBindings\(' 'FindHostMovieTextureBindings'
    $body=MethodBody $Text $span

    foreach($requiredLocal in @(
        'bestLumaIndex',
        'bestChromaIndex',
        'textures'))
    {
        if(-not $body.Contains($requiredLocal)){
            throw "FindHostMovieTextureBindings local token missing: $requiredLocal"
        }
    }

    $lastReturn=Find-LastTopLevelReturnLine $body
    $indent=$lastReturn.Groups['indent'].Value

    $hook=@'
if (bestLumaIndex >= 0 &&
    bestChromaIndex >= 0 &&
    IsUiBinkStickyPlaneEnabledV740842() &&
    HostMovieBridge.IsDemonSoulsUiBinkCompositePathV740841(
        _hostMovieFramePath))
{
    // SHARPEMU_V74_0_86_1_4_UI_BINK_FINAL_RETURN_LEARN
    // Structural fix: do not assume the exact text of the accumulated
    // assignment block or final return. At the final method exit the selected
    // bestLumaIndex/bestChromaIndex values are already stable, so record those
    // addresses into the existing V84.2.1 sticky-plane sets.
    var lumaAddressV7408614 = textures[bestLumaIndex].Address;
    var chromaAddressV7408614 = textures[bestChromaIndex].Address;
    var learnedLumaV7408614 =
        _v740842LearnedUiBinkLumaAddresses.Add(lumaAddressV7408614);
    var learnedChromaV7408614 =
        _v740842LearnedUiBinkChromaAddresses.Add(chromaAddressV7408614);

    if (learnedLumaV7408614 || learnedChromaV7408614)
    {
        var traceV7408614 = Interlocked.Increment(
            ref _v740842UiBinkPlaneLearnCount);
        Console.Error.WriteLine(
            "[V74.0.86.1.4][UI_BINK_FINAL_RETURN_LEARN] " +
            $"count={traceV7408614} file='{Path.GetFileName(_hostMovieFramePath)}' " +
            $"luma_index={bestLumaIndex} y=0x{lumaAddressV7408614:X16} " +
            $"chroma_index={bestChromaIndex} uv=0x{chromaAddressV7408614:X16} " +
            $"learned_y={_v740842LearnedUiBinkLumaAddresses.Count} " +
            $"learned_uv={_v740842LearnedUiBinkChromaAddresses.Count}");
    }
}
'@

    $hook=NL($hook).Trim("`n")
    $hookLines=$hook -split "`n"
    $hookIndented=($hookLines | ForEach-Object { $indent+$_ }) -join "`n"

    $body=$body.Substring(0,$lastReturn.Index)+$hookIndented+"`n"+$body.Substring($lastReturn.Index)
    return ReplaceMethodBody $Text $span $body
}

function Assert-V7408614([string]$Repo) {
    $it=NL([IO.File]::ReadAllText((Join-Path $Repo $script:ImeRel)))
    $pt=NL([IO.File]::ReadAllText((Join-Path $Repo $script:PresenterRel)))

    $missing=@()

    foreach($m in @(
        'SHARPEMU_V74_0_86_1_IME_OSK_OVERLAY',
        'SHARPEMU_V74_0_86_1_4_IME_OSK_BASE64_PAYLOAD',
        'SharpEmu - Text Input',
        'Done'))
    {
        if(-not $it.Contains($m)){
            $missing+="IME:$m"
        }
    }

    foreach($m in @(
        'SHARPEMU_V74_0_86_1_4_UI_BINK_FINAL_RETURN_LEARN',
        '[V74.0.86.1.4][UI_BINK_FINAL_RETURN_LEARN]',
        'SHARPEMU_V74_0_84_2_1_UI_BINK_FRAME_OWNERSHIP',
        'SHARPEMU_V74_0_84_2_1_UI_BINK_STICKY_PLANE_INTEGRITY',
        'SHARPEMU_V74_0_86_DS_CHARACTER_CREATOR_TYPED_DCC',
        '_v740842LearnedUiBinkLumaAddresses.Add(lumaAddressV7408614)',
        '_v740842LearnedUiBinkChromaAddresses.Add(chromaAddressV7408614)'))
    {
        if(-not $pt.Contains($m)){
            $missing+="Presenter:$m"
        }
    }

    if($missing.Count -gt 0){
        throw ('post-apply markers missing: '+($missing -join '; '))
    }
}
