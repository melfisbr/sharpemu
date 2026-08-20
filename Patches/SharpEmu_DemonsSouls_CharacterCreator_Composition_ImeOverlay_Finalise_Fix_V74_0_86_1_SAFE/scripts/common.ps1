Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$script:Tag='[V74.0.86.1]'
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
function MethodBody([string]$Text,$Span){ return $Text.Substring($Span.BodyStart,$Span.BodyLength) }
function ReplaceMethodBody([string]$Text,$Span,[string]$Body){ return $Text.Substring(0,$Span.BodyStart)+$Body+$Text.Substring($Span.CloseBrace) }
function InsertTextBefore([string]$Text,[string]$Needle,[string]$Insert,[string]$Label){
    $count=CountText $Text $Needle
    if($count -ne 1){ throw "$Label anchor count=$count" }
    $idx=$Text.IndexOf($Needle,[StringComparison]::Ordinal)
    return $Text.Substring(0,$idx)+$Insert+$Text.Substring($idx)
}

function Apply-PresenterV740861([string]$Text) {
    if($Text.Contains('SHARPEMU_V74_0_86_1_DS_UI_BINK_CHARACTER_CREATOR_COMPOSITE')){ return $Text }

    if(-not $Text.Contains('SHARPEMU_V74_0_86_DS_CHARACTER_CREATOR_TYPED_DCC')){
        throw 'V74.0.86 typed DCC marker missing; install V74.0.86 first.'
    }

    $fieldNeedle='        private long _v740841UiBinkChromaTraceCount;'
    if((CountText $Text $fieldNeedle) -ne 1){ throw "Presenter field locator count=$(CountText $Text $fieldNeedle)" }
    $fieldAt=$Text.IndexOf($fieldNeedle,[StringComparison]::Ordinal)+$fieldNeedle.Length
    $Text=$Text.Substring(0,$fieldAt)+"`n`n"+(ReadPatch 'Presenter.fields.insert.txt').Trim("`n")+$Text.Substring($fieldAt)

    $findDecl='        private HostMovieTextureBindings FindHostMovieTextureBindings('
    if((CountText $Text $findDecl) -ne 1){ throw 'FindHostMovieTextureBindings declaration changed' }
    $idx=$Text.IndexOf($findDecl,[StringComparison]::Ordinal)
    $Text=$Text.Substring(0,$idx)+(ReadPatch 'Presenter.helpers.insert.txt')+$Text.Substring($idx)

    $pump=FindMethodSpan $Text '(?m)^[ \t]*private void PumpHostMovieFrame\(\)\s*$' 'PumpHostMovieFrame'
    $pb=MethodBody $Text $pump
    $resetNeedle=NL(@'
                _hostMovieLumaUploadedFrameSerial = -1;
                _hostMovieChromaUploadedFrameSerial = -1;
'@).Trim("`n")
    if((CountText $pb $resetNeedle) -ne 1){ throw "Pump reset anchor count=$(CountText $pb $resetNeedle)" }
    $resetReplacement=NL(@'
                _hostMovieLumaUploadedFrameSerial = -1;
                _hostMovieChromaUploadedFrameSerial = -1;
                _v740861LearnedUiBinkLumaAddresses.Clear();
                _v740861LearnedUiBinkChromaAddresses.Clear();
'@).Trim("`n")
    $pb=$pb.Replace($resetNeedle,$resetReplacement)

    $frameNeedle=NL(@'
            _hostMovieFramePixels = pixels;
            _hostMovieFrameWidth = width;
            _hostMovieFrameHeight = height;
            _hostMovieFrameSerial = frameSerial;
'@).Trim("`n")
    if((CountText $pb $frameNeedle) -ne 1){ throw "Pump frame assignment anchor count=$(CountText $pb $frameNeedle)" }
    $frameReplacement=NL(@'
            if (HostMovieBridge.IsDemonSoulsUiBinkCompositePathV740841(hostPath))
            {
                if (_v740861OwnedUiBinkFramePixels is null ||
                    _v740861OwnedUiBinkFramePixels.Length != pixels.Length)
                {
                    _v740861OwnedUiBinkFramePixels = new byte[pixels.Length];
                }
                pixels.AsSpan().CopyTo(_v740861OwnedUiBinkFramePixels);
                _hostMovieFramePixels = _v740861OwnedUiBinkFramePixels;

                var snapshot = Interlocked.Increment(
                    ref _v740861UiBinkFrameSnapshotCount);
                if (snapshot <= 16 || (snapshot & (snapshot - 1)) == 0)
                {
                    Console.Error.WriteLine(
                        "[V74.0.86.1][UI_BINK_FRAME_SNAPSHOT] " +
                        $"count={snapshot} file='{Path.GetFileName(hostPath)}' " +
                        $"serial={frameSerial} bytes={pixels.Length} " +
                        "source=decoder-buffer copy=presenter-owned");
                }
            }
            else
            {
                _hostMovieFramePixels = pixels;
            }
            _hostMovieFrameWidth = width;
            _hostMovieFrameHeight = height;
            _hostMovieFrameSerial = frameSerial;
'@).Trim("`n")
    $pb=$pb.Replace($frameNeedle,$frameReplacement)
    $Text=ReplaceMethodBody $Text $pump $pb

    $find=FindMethodSpan $Text '(?m)^[ \t]*private HostMovieTextureBindings FindHostMovieTextureBindings\(' 'FindHostMovieTextureBindings'
    $fb=MethodBody $Text $find
    $noneRx=[regex]::new('(?m)^(?<indent>[ \t]*)return HostMovieTextureBindings\.None;[ \t]*$')
    $noneMatches=$noneRx.Matches($fb)
    if($noneMatches.Count -lt 2) { throw "FindHostMovieTextureBindings None-return count=$($noneMatches.Count); expected at least 2" }
    $lastNone=$noneMatches[$noneMatches.Count-1]
    $noneIndent=$lastNone.Groups['indent'].Value
    $fallback=$noneIndent+'return FindLearnedUiBinkTextureBindingsV740861(textures);'
    $fb=$fb.Substring(0,$lastNone.Index)+$fallback+$fb.Substring($lastNone.Index+$lastNone.Length)
    $Text=ReplaceMethodBody $Text $find $fb

    $remember=FindMethodSpan $Text '(?m)^[ \t]*private HostMovieTextureBindings RememberHostMovieTextureMappings\(' 'RememberHostMovieTextureMappings'
    $rb=MethodBody $Text $remember
    $rememberReturnRx=[regex]::new('(?m)^(?<indent>[ \t]*)return new HostMovieTextureBindings\(lumaIndex, chromaIndex\);[ \t]*$')
    $rememberReturns=$rememberReturnRx.Matches($rb)
    if($rememberReturns.Count -ne 1) { throw "RememberHostMovieTextureMappings return count=$($rememberReturns.Count)" }
    $rr=$rememberReturns[0]
    $ri=$rr.Groups['indent'].Value
    $learn=NL(@'
            if (IsUiBinkStickyPlaneEnabledV740861() &&
                HostMovieBridge.IsDemonSoulsUiBinkCompositePathV740841(
                    _hostMovieFramePath))
            {
                var learnedLuma = _v740861LearnedUiBinkLumaAddresses.Add(
                    textures[lumaIndex].Address);
                var learnedChroma = _v740861LearnedUiBinkChromaAddresses.Add(
                    textures[chromaIndex].Address);
                if (learnedLuma || learnedChroma)
                {
                    var trace = Interlocked.Increment(
                        ref _v740861UiBinkPlaneLearnCount);
                    Console.Error.WriteLine(
                        "[V74.0.86.1][UI_BINK_PLANE_LEARN] " +
                        $"count={trace} file='{Path.GetFileName(_hostMovieFramePath)}' " +
                        $"y=0x{textures[lumaIndex].Address:X16} " +
                        $"uv=0x{textures[chromaIndex].Address:X16} " +
                        $"learned_y={_v740861LearnedUiBinkLumaAddresses.Count} " +
                        $"learned_uv={_v740861LearnedUiBinkChromaAddresses.Count}");
                }
            }

'@)
    $learnLines=$learn.Trim("`n") -split "`n"
    $learnAdjusted=($learnLines | ForEach-Object { if($_.Length -ge 12){ $ri+$_.Substring(12) } else { $ri+$_ } }) -join "`n"
    $rb=$rb.Substring(0,$rr.Index)+$learnAdjusted+"`n"+$rb.Substring($rr.Index)
    $Text=ReplaceMethodBody $Text $remember $rb

    return $Text
}

function Assert-V740861([string]$Repo) {
    $it=NL([IO.File]::ReadAllText((Join-Path $Repo $script:ImeRel)))
    $pt=NL([IO.File]::ReadAllText((Join-Path $Repo $script:PresenterRel)))
    $missing=@()
    foreach($m in @('SHARPEMU_V74_0_86_1_IME_OSK_OVERLAY','host_panel_spawn','SharpEmu - Text Input','ABC','Done')){if(-not$it.Contains($m)){$missing+="IME:$m"}}
    foreach($m in @('SHARPEMU_V74_0_86_1_DS_UI_BINK_CHARACTER_CREATOR_COMPOSITE','[V74.0.86.1][UI_BINK_FRAME_SNAPSHOT]','[V74.0.86.1][UI_BINK_STICKY_PLANE]','[V74.0.86.1][UI_BINK_PLANE_LEARN]','SHARPEMU_DS_UI_BINK_STICKY_PLANES')){if(-not$pt.Contains($m)){$missing+="Presenter:$m"}}
    if($missing.Count -gt 0){throw ('post-apply markers missing: '+($missing -join '; '))}
}
