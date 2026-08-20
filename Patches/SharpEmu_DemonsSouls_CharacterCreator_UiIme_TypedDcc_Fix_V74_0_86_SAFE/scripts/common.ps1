Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$script:Tag='[V74.0.86]'
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
function ReadPatch([string]$Name) { return (NL([IO.File]::ReadAllText((Join-Path (PackageRoot) ('patch\'+$Name))))) }
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
function Get-DccAliasSpan([string]$Text) {
    return FindMethodSpan $Text '(?m)^[ \t]*private bool TryResolveGuestImageMetadataAliasV7405632\(\s*$' 'TryResolveGuestImageMetadataAliasV7405632'
}
function MethodBody([string]$Text,$Span){ return $Text.Substring($Span.BodyStart,$Span.BodyLength) }
function ReplaceMethodBody([string]$Text,$Span,[string]$Body){ return $Text.Substring(0,$Span.BodyStart)+$Body+$Text.Substring($Span.CloseBrace) }

function Apply-PresenterV74086([string]$Text) {
    if($Text.Contains('SHARPEMU_V74_0_86_DS_CHARACTER_CREATOR_TYPED_DCC')){ return $Text }
    $fieldNeedle='        private static long _v7405632DccMetadataAliasMissCount;'
    if((CountText $Text $fieldNeedle) -ne 1){ throw "Presenter field locator count=$(CountText $Text $fieldNeedle)" }
    $fieldAt=$Text.IndexOf($fieldNeedle,[StringComparison]::Ordinal)+$fieldNeedle.Length
    $Text=$Text.Substring(0,$fieldAt)+"`n`n"+(ReadPatch 'Presenter.fields.insert.txt').Trim("`n")+$Text.Substring($fieldAt)

    $span=Get-DccAliasSpan $Text
    $body=MethodBody $Text $span
    $missCounter='ref _v7405632DccMetadataAliasMissCount'
    $missCounterPos=$body.LastIndexOf($missCounter,[StringComparison]::Ordinal)
    if($missCounterPos -lt 0){ throw 'DCC alias miss counter not found inside method' }
    $missNeedle='            if (best is null)'
    $insertPos=$body.LastIndexOf($missNeedle,$missCounterPos,[StringComparison]::Ordinal)
    if($insertPos -lt 0){ throw 'final DCC alias miss branch not found before miss counter' }
    $body=$body.Substring(0,$insertPos)+(ReadPatch 'Presenter.final_typed_guard.insert.txt')+$body.Substring($insertPos)
    return ReplaceMethodBody $Text $span $body
}

function Assert-V74086([string]$Repo) {
    $it=NL([IO.File]::ReadAllText((Join-Path $Repo $script:ImeRel)))
    $pt=NL([IO.File]::ReadAllText((Join-Path $Repo $script:PresenterRel)))
    $missing=@()
    foreach($m in @('SHARPEMU_V74_0_86_IME_VISIBLE_HOST_TEXT_INPUT','host_panel_spawn','CreateNoWindow = false','WindowStyle = ProcessWindowStyle.Normal','SHARPEMU_IME_RESULT_PATH')){if(-not$it.Contains($m)){$missing+="IME:$m"}}
    foreach($m in @('SHARPEMU_V74_0_86_DS_CHARACTER_CREATOR_TYPED_DCC','[V74.0.86][DS_DCC_TYPED_REJECT]','[V74.0.86][DS_DCC_EXACT_REPLACEMENT]','SHARPEMU_DS_DCC_EXACT_FORMAT')){if(-not$pt.Contains($m)){$missing+="Presenter:$m"}}
    if($missing.Count -gt 0){throw ('post-apply markers missing: '+($missing -join '; '))}
}
