Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$script:Tag='[V74.0.88.5]'

function PackageRoot { return (Split-Path -Parent $PSScriptRoot) }
function Patches { return (Split-Path -Parent (PackageRoot)) }
function RepoRoot { return (Split-Path -Parent (Patches)) }
function Sha([string]$p) { return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToUpperInvariant() }
function NL([string]$s) { return $s.Replace("`r`n","`n").Replace("`r","`n") }

function Paths {
    $repo=RepoRoot
    return [pscustomobject]@{
        Repo=$repo
        Ime=Join-Path $repo 'src\SharpEmu.Libs\Ime\ImeDialogExports.cs'
        ImeOverlay=Join-Path $repo 'src\SharpEmu.Libs\Ime\ImeInWindowOverlay.cs'
        Sdl=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\SdlHostWindow.cs'
        Presenter=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
        Host=Join-Path $repo 'src\SharpEmu.Libs\Media\HostMovieBridge.cs'
        Cli=Join-Path $repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
        Exe=Join-Path $repo 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'
    }
}

function WritePreserving([string]$Path,[string]$Text) {
    $bytes=[IO.File]::ReadAllBytes($Path)
    $bom=$bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $raw=[IO.File]::ReadAllText($Path)
    $lf=[regex]::Matches($raw,"`n").Count
    $crlf=[regex]::Matches($raw,"`r`n").Count
    $useCrlf=$crlf -ge [Math]::Max(1,[int]($lf*0.8))
    $out=if($useCrlf){$Text.Replace("`n","`r`n")}else{$Text}
    [IO.File]::WriteAllText($Path,$out,(New-Object Text.UTF8Encoding($bom)))
}

function FindMethodSpan([string]$Text,[string]$Regex,[string]$Label) {
    $rx=[regex]::new($Regex,[Text.RegularExpressions.RegexOptions]::Multiline)
    $matches=$rx.Matches($Text)
    if($matches.Count -ne 1){throw "$Label declaration count=$($matches.Count)"}
    $decl=$matches[0]
    $open=$Text.IndexOf('{',$decl.Index+$decl.Length)
    if($open -lt 0){throw "$Label opening brace not found"}

    $depth=0;$inString=$false;$verbatim=$false;$inChar=$false;$escape=$false
    $lineComment=$false;$blockComment=$false
    for($i=$open;$i -lt $Text.Length;$i++){
        $ch=$Text[$i]
        $next=if($i+1 -lt $Text.Length){$Text[$i+1]}else{[char]0}

        if($lineComment){if($ch -eq "`n"){$lineComment=$false};continue}
        if($blockComment){if($ch -eq '*' -and $next -eq '/'){$blockComment=$false;$i++};continue}
        if($inString){
            if($verbatim){
                if($ch -eq '"'){
                    if($next -eq '"'){$i++;continue}
                    $inString=$false;$verbatim=$false
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

function Body([string]$Text,$Span) {
    return $Text.Substring($Span.BodyStart,$Span.BodyLength)
}

function ReplaceBody([string]$Text,$Span,[string]$Body) {
    return $Text.Substring(0,$Span.BodyStart)+$Body+$Text.Substring($Span.CloseBrace)
}

function Apply-PostIntroLoopScopeV740883([string]$Text) {
    if($Text.Contains('SHARPEMU_V74_0_88_3_MAIN_MENU_ONLY_LOOP_SCOPE')){
        return $Text
    }

    if(-not $Text.Contains('SHARPEMU_V74_0_88_UI_BINK_GUEST_OWNED_LOOP')){
        throw 'V74.0.88 guest-owned UI-Bink loop marker missing'
    }

    $span=FindMethodSpan $Text '(?m)^[ \t]*private static bool TryRestartDemonSoulsUiBinkLoopV74088\(' 'TryRestartDemonSoulsUiBinkLoopV74088'
    $body=Body $Text $span

    $old='!IsDemonSoulsUiBinkCompositePathV740841(hostPath) ||'
    $count=([regex]::Matches($body,[regex]::Escape($old))).Count
    if($count -ne 1){
        throw "V74.0.88 loop-scope classifier count=$count; expected 1"
    }

    $new=@'
            // SHARPEMU_V74_0_88_3_MAIN_MENU_ONLY_LOOP_SCOPE
            // Only persistent NEW GAME / menu textures may rewind at EOF.
            // logo_intro_loop.bk2 participates in the boot/title handoff and
            // must retain its normal completion semantics.
            (!string.Equals(
                 Path.GetFileName(hostPath),
                 "main_menu.bk2",
                 StringComparison.OrdinalIgnoreCase) &&
             !string.Equals(
                 Path.GetFileName(hostPath),
                 "main_menu_ngp.bk2",
                 StringComparison.OrdinalIgnoreCase)) ||
'@
    $body=$body.Replace($old,(NL $new).Trim("`n"))

    # Make the runtime evidence unambiguous for this repair.
    $body=$body.Replace(
        '[V74.0.88][UI_BINK_LOOP_RESTART]',
        '[V74.0.88.3][MAIN_MENU_LOOP_RESTART]')

    return ReplaceBody $Text $span $body
}

function Assert-V740883([string]$Repo) {
    $p=Paths
    $missing=@()

    foreach($path in @($p.Ime,$p.ImeOverlay,$p.Sdl,$p.Presenter,$p.Host,$p.Cli)){
        if(-not(Test-Path -LiteralPath $path)){$missing+="FILE:$path"}
    }
    if($missing.Count -gt 0){throw ($missing -join '; ')}

    $ime=NL([IO.File]::ReadAllText($p.Ime))
    $overlay=NL([IO.File]::ReadAllText($p.ImeOverlay))
    $sdl=NL([IO.File]::ReadAllText($p.Sdl))
    $presenter=NL([IO.File]::ReadAllText($p.Presenter))
    $hostMovieText=NL([IO.File]::ReadAllText($p.Host))

    foreach($marker in @(
        'SHARPEMU_V74_0_88_IME_IN_WINDOW_SYSTEM_UI',
        'ImeInWindowOverlay.Open'))
    {
        if(-not $ime.Contains($marker)){$missing+="IME:$marker"}
    }
    foreach($marker in @('backend=sdl-vulkan-overlay','HandleGamepadButtons')){
        if(-not $overlay.Contains($marker)){$missing+="OVERLAY:$marker"}
    }
    foreach($marker in @(
        'SHARPEMU_V74_0_88_IME_IN_WINDOW_SDL_INPUT',
        'SHARPEMU_V74_0_88_IME_IN_WINDOW_GAMEPAD_INPUT'))
    {
        if(-not $sdl.Contains($marker)){$missing+="SDL:$marker"}
    }
    foreach($marker in @(
        'SHARPEMU_V74_0_88_UI_BINK_UINT_PLANE_CONTRACT',
        'FindTypedUiBinkPlaneBindingsV74088',
        'SHARPEMU_V74_0_84_2_1_UI_BINK_FRAME_OWNERSHIP',
        'SHARPEMU_V74_0_86_DS_CHARACTER_CREATOR_TYPED_DCC'))
    {
        if(-not $presenter.Contains($marker)){$missing+="PRESENTER:$marker"}
    }
    foreach($marker in @(
        'SHARPEMU_V74_0_88_UI_BINK_GUEST_OWNED_LOOP',
        'SHARPEMU_V74_0_88_3_MAIN_MENU_ONLY_LOOP_SCOPE',
        '[V74.0.88.3][MAIN_MENU_LOOP_RESTART]',
        '"main_menu.bk2"',
        '"main_menu_ngp.bk2"'))
    {
        if(-not $hostMovieText.Contains($marker)){$missing+="HOST:$marker"}
    }

    $loopSpan=FindMethodSpan $hostMovieText '(?m)^[ \t]*private static bool TryRestartDemonSoulsUiBinkLoopV74088\(' 'TryRestartDemonSoulsUiBinkLoopV74088'
    $loopBody=Body $hostMovieText $loopSpan
    if($loopBody.Contains('!IsDemonSoulsUiBinkCompositePathV740841(hostPath)')){
        $missing+='HOST:legacy-wide-loop-scope-still-active'
    }
    if($loopBody.Contains('"logo_intro_loop.bk2"')){
        $missing+='HOST:logo_intro_loop-explicitly-looped'
    }

    if($missing.Count -gt 0){
        throw ('V74.0.88.3 validation failed: '+($missing -join '; '))
    }
}


function Apply-StableHostMoviePlaneLifetimeV740885([string]$Text) {
    if($Text.Contains('SHARPEMU_V74_0_88_5_STABLE_HOST_PLANE_FORMAT')){
        return $Text
    }

    foreach($required in @(
        'SHARPEMU_V74_0_88_UI_BINK_UINT_PLANE_CONTRACT',
        '_v74088HostMovieLumaNumberType',
        '_v74088HostMovieChromaNumberType',
        '_v74088CreatedHostMovieLumaNumberType',
        '_v74088CreatedHostMovieChromaNumberType',
        'FindTypedUiBinkPlaneBindingsV74088'))
    {
        if(-not $Text.Contains($required)){
            throw "V74.0.88 presenter baseline marker missing: $required"
        }
    }

    $ensure=FindMethodSpan $Text '(?m)^[ \t]*private void EnsureHostMovieImages\(' 'EnsureHostMovieImages'
    $body=Body $Text $ensure

    $dynamicFormats=@'
            var desiredLumaFormatV74088 =
                GetTextureFormat(1, _v74088HostMovieLumaNumberType);
            var desiredChromaFormatV74088 =
                GetTextureFormat(3, _v74088HostMovieChromaNumberType);
'@
    $dynamicFormats=(NL $dynamicFormats).Trim("`n")
    if(-not $body.Contains($dynamicFormats)){
        throw 'EnsureHostMovieImages V88 dynamic-format block not found'
    }

    $stableFormats=@'
            // SHARPEMU_V74_0_88_5_STABLE_HOST_PLANE_FORMAT
            // The host decoder produces byte-normalized Y/UV planes. Keep one
            // Vulkan image format for the lifetime of the active host movie.
            // V74.0.88 changed this per guest descriptor NumberType (n0/n4),
            // which could destroy/recreate host images while already-translated
            // draws still referenced the previous VkImage handle.
            var desiredLumaFormatV74088 = Format.R8Unorm;
            var desiredChromaFormatV74088 = Format.R8G8Unorm;
'@
    $body=$body.Replace($dynamicFormats,(NL $stableFormats).Trim("`n"))

    $lumaGeneration=
        '                _v74088CreatedHostMovieLumaNumberType == _v74088HostMovieLumaNumberType &&'
    $chromaGeneration=
        '                _v74088CreatedHostMovieChromaNumberType == _v74088HostMovieChromaNumberType &&'

    if(-not $body.Contains($lumaGeneration)){
        throw 'EnsureHostMovieImages V88 luma-number-type lifetime condition missing'
    }
    if(-not $body.Contains($chromaGeneration)){
        throw 'EnsureHostMovieImages V88 chroma-number-type lifetime condition missing'
    }

    # NumberType still participates in guest-plane discovery, but no longer
    # controls VkImage destruction/recreation.
    $body=$body.Replace($lumaGeneration,'                true && // V74.0.88.5: guest NumberType does not invalidate host VkImage')
    $body=$body.Replace($chromaGeneration,'                true && // V74.0.88.5: guest NumberType does not invalidate host VkImage')

    $Text=ReplaceBody $Text $ensure $body

    # Clarify the bootstrap log: n4 is the guest descriptor contract; host
    # replacement storage is normalized because the converted frame contains
    # normalized byte YUV, and keeping its format stable prevents stale VkImage
    # references across translated draws.
    $Text=$Text.Replace(
        'number_type=4 vk_y=R8Uint vk_uv=R8G8Uint ',
        'guest_number_type=4 host_vk_y=R8Unorm host_vk_uv=R8G8Unorm ')

    return $Text
}

function Apply-HostMovieUploadTraceV740885([string]$Text) {
    if($Text.Contains('SHARPEMU_V74_0_88_5_HOST_MOVIE_UPLOAD_TRACE')){
        return $Text
    }

    $span=FindMethodSpan $Text '(?m)^[ \t]*private void RecordTextureUploads\(' 'RecordTextureUploads'
    $body=Body $Text $span

    $anchor=@'
                var copyRegion = new BufferImageCopy
                {
                    BufferRowLength = texture.RowLength > texture.Width
'@
    $anchor=(NL $anchor).Trim("`n")
    if(-not $body.Contains($anchor)){
        throw 'RecordTextureUploads copyRegion anchor not found'
    }

    $insert=@'
                // SHARPEMU_V74_0_88_5_HOST_MOVIE_UPLOAD_TRACE
                if (texture.IsHostMovie)
                {
                    Console.Error.WriteLine(
                        "[V74.0.88.5][HOST_MOVIE_UPLOAD] " +
                        $"plane={texture.HostMoviePlane} serial={texture.HostMovieFrameSerial} " +
                        $"staging=0x{texture.StagingBuffer.Handle:X16} image=0x{texture.Image.Handle:X16} " +
                        $"extent={texture.Width}x{texture.Height}x{texture.Depth} " +
                        $"row={texture.RowLength} mip={texture.MipLevel} layers={texture.Layers}");

                    if (texture.StagingBuffer.Handle == 0 ||
                        texture.Image.Handle == 0 ||
                        texture.Width == 0 ||
                        texture.Height == 0 ||
                        texture.Depth == 0 ||
                        texture.Layers == 0)
                    {
                        Console.Error.WriteLine(
                            "[V74.0.88.5][HOST_MOVIE_UPLOAD_INVALID] " +
                            $"plane={texture.HostMoviePlane} serial={texture.HostMovieFrameSerial} " +
                            $"staging=0x{texture.StagingBuffer.Handle:X16} image=0x{texture.Image.Handle:X16} " +
                            $"extent={texture.Width}x{texture.Height}x{texture.Depth} layers={texture.Layers}");
                        continue;
                    }
                }

                var copyRegion = new BufferImageCopy
                {
                    BufferRowLength = texture.RowLength > texture.Width
'@
    $body=$body.Replace($anchor,(NL $insert).Trim("`n"))
    return ReplaceBody $Text $span $body
}

function Assert-V740885([string]$Repo) {
    Assert-V740883 $Repo
    $p=Paths
    $presenter=NL([IO.File]::ReadAllText($p.Presenter))
    $missing=@()

    foreach($marker in @(
        'SHARPEMU_V74_0_88_5_STABLE_HOST_PLANE_FORMAT',
        'var desiredLumaFormatV74088 = Format.R8Unorm;',
        'var desiredChromaFormatV74088 = Format.R8G8Unorm;',
        'V74.0.88.5: guest NumberType does not invalidate host VkImage',
        'SHARPEMU_V74_0_88_5_HOST_MOVIE_UPLOAD_TRACE',
        '[V74.0.88.5][HOST_MOVIE_UPLOAD]'))
    {
        if(-not $presenter.Contains($marker)){
            $missing+="PRESENTER:$marker"
        }
    }

    if($presenter.Contains('var desiredLumaFormatV74088 ='+
        "`n                GetTextureFormat(1, _v74088HostMovieLumaNumberType);"))
    {
        $missing+='PRESENTER:dynamic-luma-format-still-active'
    }

    if($missing.Count -gt 0){
        throw ('V74.0.88.5 validation failed: '+($missing -join '; '))
    }
}
