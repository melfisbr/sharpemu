Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$script:Tag='[V74.0.86.1.1]'
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
function Sha([string]$p) { return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToUpperInvariant() }
function NL([string]$s) { return $s.Replace("`r`n","`n").Replace("`r","`n") }
function CountText([string]$text,[string]$needle) {
    if([string]::IsNullOrEmpty($needle)){ return 0 }
    $count=0; $start=0
    while(($i=$text.IndexOf($needle,$start,[StringComparison]::Ordinal)) -ge 0){ $count++; $start=$i+$needle.Length }
    return $count
}
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
    $depth=0; $inString=$false; $verbatim=$false; $inChar=$false; $escape=$false; $lineComment=$false; $blockComment=$false
    for($i=$open;$i -lt $Text.Length;$i++){
        $ch=$Text[$i]; $next=if($i+1 -lt $Text.Length){$Text[$i+1]}else{[char]0}
        if($lineComment){ if($ch -eq "`n"){$lineComment=$false}; continue }
        if($blockComment){ if($ch -eq '*' -and $next -eq '/'){$blockComment=$false;$i++}; continue }
        if($inString){
            if($verbatim){ if($ch -eq '"'){ if($next -eq '"'){$i++;continue}; $inString=$false;$verbatim=$false }; continue }
            if($escape){$escape=$false;continue}; if($ch -eq '\'){$escape=$true;continue}; if($ch -eq '"'){$inString=$false}; continue
        }
        if($inChar){ if($escape){$escape=$false;continue}; if($ch -eq '\'){$escape=$true;continue}; if($ch -eq "'"){$inChar=$false}; continue }
        if($ch -eq '/' -and $next -eq '/'){$lineComment=$true;$i++;continue}
        if($ch -eq '/' -and $next -eq '*'){$blockComment=$true;$i++;continue}
        if($ch -eq '@' -and $next -eq '"'){$inString=$true;$verbatim=$true;$i++;continue}
        if($ch -eq '"'){$inString=$true;continue}
        if($ch -eq "'"){$inChar=$true;continue}
        if($ch -eq '{'){$depth++;continue}
        if($ch -eq '}'){$depth--; if($depth -eq 0){ return [pscustomobject]@{DeclarationStart=$decl.Index;OpenBrace=$open;CloseBrace=$i;BodyStart=$open+1;BodyLength=$i-$open-1} }}
    }
    throw "$Label closing brace not found"
}
function MethodBody([string]$Text,$Span){ return $Text.Substring($Span.BodyStart,$Span.BodyLength) }
function ReplaceMethodBody([string]$Text,$Span,[string]$Body){ return $Text.Substring(0,$Span.BodyStart)+$Body+$Text.Substring($Span.CloseBrace) }

function Apply-PresenterV7408611([string]$Text) {
    if($Text.Contains('SHARPEMU_V74_0_86_1_1_UI_BINK_DISCOVERY_REMEMBER')){ return $Text }

    if(-not $Text.Contains('SHARPEMU_V74_0_86_DS_CHARACTER_CREATOR_TYPED_DCC')){
        throw 'V74.0.86 typed-DCC marker missing.'
    }
    if(-not $Text.Contains('SHARPEMU_V74_0_84_2_1_UI_BINK_FRAME_OWNERSHIP')){
        throw 'V74.0.84.2.1 frame-ownership marker missing. Current checkout differs from the validated runtime.'
    }
    if(-not $Text.Contains('SHARPEMU_V74_0_84_2_1_UI_BINK_STICKY_PLANE_INTEGRITY')){
        throw 'V74.0.84.2.1 sticky-plane marker missing. Current checkout differs from the validated runtime.'
    }

    $find=FindMethodSpan $Text '(?m)^[ \t]*private HostMovieTextureBindings FindHostMovieTextureBindings\(' 'FindHostMovieTextureBindings'
    $body=MethodBody $Text $find

    $old='            return new HostMovieTextureBindings(bestLumaIndex, bestChromaIndex);'
    $already='            return RememberHostMovieTextureMappings(textures, bestLumaIndex, bestChromaIndex);'
    $oldCount=CountText $body $old
    $alreadyCount=CountText $body $already
    if($alreadyCount -eq 1){
        $marker="`n            // SHARPEMU_V74_0_86_1_1_UI_BINK_DISCOVERY_REMEMBER`n"
        $pos=$body.IndexOf($already,[StringComparison]::Ordinal)
        $body=$body.Substring(0,$pos)+$marker+$body.Substring($pos)
        return ReplaceMethodBody $Text $find $body
    }
    if($oldCount -ne 1){
        throw "FindHostMovieTextureBindings discovery return count=$oldCount; expected 1"
    }

    $replacement=@'
            // SHARPEMU_V74_0_86_1_1_UI_BINK_DISCOVERY_REMEMBER
            // The discovery path used to return the pair directly. That bypassed
            // RememberHostMovieTextureMappings(), so V74.0.84.2.1 never learned
            // newly discovered Bluepoint Y/UV addresses and its sticky fallback
            // could never activate. Route discovery through Remember() too.
            return RememberHostMovieTextureMappings(
                textures,
                bestLumaIndex,
                bestChromaIndex);
'@
    $replacement=NL($replacement).Trim("`n")
    $body=$body.Replace($old,$replacement)
    return ReplaceMethodBody $Text $find $body
}

function Assert-V7408611([string]$Repo) {
    $it=NL([IO.File]::ReadAllText((Join-Path $Repo $script:ImeRel)))
    $pt=NL([IO.File]::ReadAllText((Join-Path $Repo $script:PresenterRel)))
    $missing=@()
    foreach($m in @('SHARPEMU_V74_0_86_1_IME_OSK_OVERLAY','SharpEmu - Text Input','Done')){if(-not$it.Contains($m)){$missing+="IME:$m"}}
    foreach($m in @(
        'SHARPEMU_V74_0_86_1_1_UI_BINK_DISCOVERY_REMEMBER',
        'SHARPEMU_V74_0_84_2_1_UI_BINK_FRAME_OWNERSHIP',
        'SHARPEMU_V74_0_84_2_1_UI_BINK_STICKY_PLANE_INTEGRITY',
        'RememberHostMovieTextureMappings(',
        'SHARPEMU_V74_0_86_DS_CHARACTER_CREATOR_TYPED_DCC')){if(-not$pt.Contains($m)){$missing+="Presenter:$m"}}
    if($missing.Count -gt 0){throw ('post-apply markers missing: '+($missing -join '; '))}
}
