Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$script:Tag='[V74.0.88.2]'

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

function CountText([string]$Text,[string]$Needle) {
    if([string]::IsNullOrEmpty($Needle)){return 0}
    $n=0;$offset=0
    while(($i=$Text.IndexOf($Needle,$offset,[StringComparison]::Ordinal)) -ge 0){
        $n++;$offset=$i+$Needle.Length
    }
    return $n
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

function Apply-SdlV74088([string]$Text) {
    if($Text.Contains('SHARPEMU_V74_0_88_IME_IN_WINDOW_SDL_INPUT')){return $Text}

    $span=FindMethodSpan $Text '(?m)^[ \t]*private void HandleKey\(SDL_KeyboardEvent keyEvent\)\s*$' 'HandleKey'
    $body=Body $Text $span
    $anchor='        var down = keyEvent.type == SDL_EventType.SDL_EVENT_KEY_DOWN;'
    if((CountText $body $anchor) -ne 1){throw "HandleKey down anchor count=$(CountText $body $anchor)"}
    $insert=@'
        var down = keyEvent.type == SDL_EventType.SDL_EVENT_KEY_DOWN;

        // SHARPEMU_V74_0_88_IME_IN_WINDOW_SDL_INPUT
        // libSceImeDialog owns keyboard/gamepad input while its system UI is up.
        if (SharpEmu.Libs.Ime.ImeInWindowOverlay.Active)
        {
            if (down && !keyEvent.repeat)
            {
                HandleInWindowImeKeyV74088(keyEvent);
            }
            return;
        }
'@
    $body=$body.Replace($anchor,(NL $insert).Trim("`n"))
    $Text=ReplaceBody $Text $span $body

    $toggle='    private void ToggleFullscreen()'
    if((CountText $Text $toggle) -ne 1){throw "ToggleFullscreen insertion anchor count=$(CountText $Text $toggle)"}
    $helper=@'
    private static void HandleInWindowImeKeyV74088(SDL_KeyboardEvent keyEvent)
    {
        var key = keyEvent.key;
        var shift = (keyEvent.mod & SDL_Keymod.SDL_KMOD_SHIFT) != 0;

        if (key >= SDL_Keycode.SDLK_A && key <= SDL_Keycode.SDLK_Z)
        {
            var offset = (int)(key - SDL_Keycode.SDLK_A);
            var value = (char)((shift ? 'A' : 'a') + offset);
            SharpEmu.Libs.Ime.ImeInWindowOverlay.InsertCharacter(value);
            return;
        }

        if (key >= SDL_Keycode.SDLK_0 && key <= SDL_Keycode.SDLK_9)
        {
            SharpEmu.Libs.Ime.ImeInWindowOverlay.InsertCharacter(
                (char)('0' + (int)(key - SDL_Keycode.SDLK_0)));
            return;
        }

        switch (key)
        {
            case SDL_Keycode.SDLK_BACKSPACE:
                SharpEmu.Libs.Ime.ImeInWindowOverlay.Backspace();
                break;
            case SDL_Keycode.SDLK_ESCAPE:
                SharpEmu.Libs.Ime.ImeInWindowOverlay.Cancel();
                break;
            case SDL_Keycode.SDLK_RETURN:
                SharpEmu.Libs.Ime.ImeInWindowOverlay.Confirm();
                break;
            case SDL_Keycode.SDLK_SPACE:
                SharpEmu.Libs.Ime.ImeInWindowOverlay.InsertSpace();
                break;
            case SDL_Keycode.SDLK_LEFT:
                SharpEmu.Libs.Ime.ImeInWindowOverlay.MoveSelection(-1, 0);
                break;
            case SDL_Keycode.SDLK_RIGHT:
                SharpEmu.Libs.Ime.ImeInWindowOverlay.MoveSelection(1, 0);
                break;
            case SDL_Keycode.SDLK_UP:
                SharpEmu.Libs.Ime.ImeInWindowOverlay.MoveSelection(0, -1);
                break;
            case SDL_Keycode.SDLK_DOWN:
                SharpEmu.Libs.Ime.ImeInWindowOverlay.MoveSelection(0, 1);
                break;
        }
    }

'@
    $Text=$Text.Replace($toggle,(NL $helper)+$toggle)

    $gamepad=FindMethodSpan $Text '(?m)^[ \t]*private void SampleGamepad\(\)\s*$' 'SampleGamepad'
    $gb=Body $Text $gamepad
    $stateAnchor=@'
            var state = SdlGamepadStateReader.Read(_gamepad) with
            {
                Motion = ReadMotion(),
                Touch = ReadTouch(),
            };
            HostWindowInput.SetGamepad(
'@
    $stateAnchor=(NL $stateAnchor).Trim("`n")
    if((CountText $gb $stateAnchor) -ne 1){throw "SampleGamepad state anchor count=$(CountText $gb $stateAnchor)"}
    $stateReplacement=@'
            var state = SdlGamepadStateReader.Read(_gamepad) with
            {
                Motion = ReadMotion(),
                Touch = ReadTouch(),
            };

            // SHARPEMU_V74_0_88_IME_IN_WINDOW_GAMEPAD_INPUT
            if (SharpEmu.Libs.Ime.ImeInWindowOverlay.Active)
            {
                SharpEmu.Libs.Ime.ImeInWindowOverlay.HandleGamepadButtons(state.Buttons);
                state = state with { Buttons = HostGamepadButtons.None };
            }

            HostWindowInput.SetGamepad(
'@
    $gb=$gb.Replace($stateAnchor,(NL $stateReplacement).Trim("`n"))
    return ReplaceBody $Text $gamepad $gb
}

function Apply-PresenterV74088([string]$Text) {
    if($Text.Contains('SHARPEMU_V74_0_88_UI_BINK_UINT_PLANE_CONTRACT')){return $Text}

    foreach($marker in @(
        'SHARPEMU_V74_0_84_2_1_UI_BINK_FRAME_OWNERSHIP',
        'SHARPEMU_V74_0_84_2_1_UI_BINK_STICKY_PLANE_INTEGRITY',
        'SHARPEMU_V74_0_86_DS_CHARACTER_CREATOR_TYPED_DCC',
        'FindLearnedUiBinkTextureBindingsV740842'))
    {
        if(-not $Text.Contains($marker)){throw "Presenter accumulated marker missing: $marker"}
    }

    $fieldAnchor='        private Image _overlayImage;'
    if((CountText $Text $fieldAnchor) -ne 1){throw "Presenter overlay field anchor count=$(CountText $Text $fieldAnchor)"}
    $fields=@'
        // SHARPEMU_V74_0_88_UI_BINK_UINT_PLANE_CONTRACT
        // Demon's Souls UI Bink shaders expose their decoded Y/UV textures as
        // R8Uint/R8G8Uint (guest format 1/3, NumberType=4). Keep the host plane
        // VkFormat identical to the shader's typed sampled-image contract.
        private uint _v74088HostMovieLumaNumberType;
        private uint _v74088HostMovieChromaNumberType;
        private uint _v74088CreatedHostMovieLumaNumberType = uint.MaxValue;
        private uint _v74088CreatedHostMovieChromaNumberType = uint.MaxValue;
        private long _v74088UiBinkUintPlaneBindCount;

'@
    $Text=$Text.Replace($fieldAnchor,(NL $fields)+$fieldAnchor)

    # Widen candidate contracts to NumberType 4. Host plane formats are fixed below.
    $Text=$Text.Replace(
        '                texture.NumberType != 0 ||',
        '                (texture.NumberType != 0 && texture.NumberType != 4) ||')
    $Text=$Text.Replace(
        '                   chroma.NumberType == 0 &&',
        '                   (chroma.NumberType == 0 || chroma.NumberType == 4) &&'+"`n"+
        '                   luma.NumberType == chroma.NumberType &&')

    # Remember the typed contract whenever an exact two-plane mapping is used.
    $remember=FindMethodSpan $Text '(?m)^[ \t]*private HostMovieTextureBindings RememberHostMovieTextureMappings\(' 'RememberHostMovieTextureMappings'
    $rb=Body $Text $remember
    $rememberAnchor='            _hostMovieLumaDstSelect = textures[lumaIndex].DstSelect;'
    if((CountText $rb $rememberAnchor) -ne 1){throw "RememberHostMovieTextureMappings anchor count=$(CountText $rb $rememberAnchor)"}
    $rememberReplacement=@'
            _v74088HostMovieLumaNumberType = textures[lumaIndex].NumberType;
            _v74088HostMovieChromaNumberType = textures[chromaIndex].NumberType;
            _hostMovieLumaDstSelect = textures[lumaIndex].DstSelect;
'@
    $rb=$rb.Replace($rememberAnchor,(NL $rememberReplacement).Trim("`n"))
    $Text=ReplaceBody $Text $remember $rb

    # Insert a one-plane bootstrap helper before FindHostMovieTextureBindings.
    $findDecl='        private HostMovieTextureBindings FindHostMovieTextureBindings('
    if((CountText $Text $findDecl) -ne 1){throw "FindHostMovieTextureBindings declaration count=$(CountText $Text $findDecl)"}
    $helper=@'
        private HostMovieTextureBindings FindTypedUiBinkPlaneBindingsV74088(
            IReadOnlyList<GuestDrawTexture> textures)
        {
            if (!HostMovieBridge.IsDemonSoulsUiBinkCompositePathV740841(
                    _hostMovieFramePath))
            {
                return HostMovieTextureBindings.None;
            }

            var lumaIndex = -1;
            var chromaIndex = -1;
            ulong lumaArea = 0;
            ulong chromaArea = 0;

            for (var index = 0; index < textures.Count; index++)
            {
                var texture = textures[index];
                if (texture.Address == 0 ||
                    texture.IsStorage ||
                    texture.IsFallback ||
                    texture.ArrayedView ||
                    texture.ArrayLayers > 1 ||
                    texture.NumberType != 4)
                {
                    continue;
                }

                var guestAspect = (ulong)texture.Width * _hostMovieFrameHeight;
                var hostAspect = (ulong)texture.Height * _hostMovieFrameWidth;
                var difference = guestAspect > hostAspect
                    ? guestAspect - hostAspect
                    : hostAspect - guestAspect;
                var sameAspect =
                    difference * 100 <= Math.Max(guestAspect, hostAspect) * 2;
                if (!sameAspect)
                {
                    continue;
                }

                var area = (ulong)texture.Width * texture.Height;
                if (texture.Format == 1 &&
                    texture.Width >= 1280 &&
                    texture.Height >= 720 &&
                    area > lumaArea)
                {
                    lumaIndex = index;
                    lumaArea = area;
                }
                else if (texture.Format == 3 &&
                         texture.Width >= 640 &&
                         texture.Height >= 360 &&
                         area > chromaArea)
                {
                    chromaIndex = index;
                    chromaArea = area;
                }
            }

            if (lumaIndex < 0 && chromaIndex < 0)
            {
                return HostMovieTextureBindings.None;
            }

            if (lumaIndex >= 0)
            {
                var luma = textures[lumaIndex];
                _v74088HostMovieLumaNumberType = luma.NumberType;
                _hostMovieLumaTextureAddress = luma.Address;
                _hostMovieLumaDstSelect = luma.DstSelect;
                _v740842LearnedUiBinkLumaAddresses.Add(luma.Address);
            }

            if (chromaIndex >= 0)
            {
                var chroma = textures[chromaIndex];
                _v74088HostMovieChromaNumberType = chroma.NumberType;
                _hostMovieChromaTextureAddress = chroma.Address;
                _hostMovieChromaDstSelect = chroma.DstSelect;
                _v740842LearnedUiBinkChromaAddresses.Add(chroma.Address);
            }

            var trace = Interlocked.Increment(ref _v74088UiBinkUintPlaneBindCount);
            if (trace <= 32 || (trace & (trace - 1)) == 0)
            {
                Console.Error.WriteLine(
                    "[V74.0.88][UI_BINK_UINT_PLANE_BIND] " +
                    $"count={trace} file='{Path.GetFileName(_hostMovieFramePath)}' " +
                    $"luma_index={lumaIndex} chroma_index={chromaIndex} " +
                    $"number_type=4 vk_y=R8Uint vk_uv=R8G8Uint " +
                    "mode=single-or-paired-plane-bootstrap");
            }

            return new HostMovieTextureBindings(lumaIndex, chromaIndex);
        }

'@
    $Text=$Text.Replace($findDecl,(NL $helper)+$findDecl)

    # Before the last return of FindHostMovieTextureBindings, try the typed
    # one-plane bootstrap. This is independent of accumulated final-return text.
    $find=FindMethodSpan $Text '(?m)^[ \t]*private HostMovieTextureBindings FindHostMovieTextureBindings\(' 'FindHostMovieTextureBindings'
    $fb=Body $Text $find
    $returns=[regex]::Matches($fb,'(?m)^(?<indent>[ \t]*)return\b[^\r\n;]*;[ \t]*$')
    if($returns.Count -lt 1){throw 'FindHostMovieTextureBindings final return not found'}
    $last=$returns[$returns.Count-1]
    $indent=$last.Groups['indent'].Value
    $typed=@'
var typedUiBindingV74088 = FindTypedUiBinkPlaneBindingsV74088(textures);
if (typedUiBindingV74088.Luma >= 0 || typedUiBindingV74088.Chroma >= 0)
{
    return typedUiBindingV74088;
}

'@
    $typedLines=((NL $typed).Trim("`n") -split "`n" | ForEach-Object {$indent+$_}) -join "`n"
    $fb=$fb.Substring(0,$last.Index)+$typedLines+"`n"+$fb.Substring($last.Index)
    $Text=ReplaceBody $Text $find $fb

    # Match host VkFormat to guest NumberType.
    $create=FindMethodSpan $Text '(?m)^[ \t]*private TextureResource CreateHostMovieTextureResource\(' 'CreateHostMovieTextureResource'
    $cb=Body $Text $create
    $ensureAnchor=@'
            EnsureHostMovieImages(
                _hostMovieFrameWidth,
'@
    $ensureAnchor=(NL $ensureAnchor).Trim("`n")
    if((CountText $cb $ensureAnchor) -ne 1){throw "CreateHostMovieTextureResource Ensure anchor count=$(CountText $cb $ensureAnchor)"}
    $ensureReplacement=@'
            if (isLuma)
            {
                _v74088HostMovieLumaNumberType = texture.NumberType;
            }
            else
            {
                _v74088HostMovieChromaNumberType = texture.NumberType;
            }

            EnsureHostMovieImages(
                _hostMovieFrameWidth,
'@
    $cb=$cb.Replace($ensureAnchor,(NL $ensureReplacement).Trim("`n"))
    $Text=ReplaceBody $Text $create $cb

    $ensure=FindMethodSpan $Text '(?m)^[ \t]*private void EnsureHostMovieImages\(' 'EnsureHostMovieImages'
    $eb=Body $Text $ensure
    $firstIf='            if (_hostMovieImage.Handle != 0 &&'
    if((CountText $eb $firstIf) -ne 1){throw "EnsureHostMovieImages first-if count=$(CountText $eb $firstIf)"}
    $formatPrelude=@'
            var desiredLumaFormatV74088 =
                GetTextureFormat(1, _v74088HostMovieLumaNumberType);
            var desiredChromaFormatV74088 =
                GetTextureFormat(3, _v74088HostMovieChromaNumberType);

            if (_hostMovieImage.Handle != 0 &&
'@
    $eb=$eb.Replace($firstIf,(NL $formatPrelude).Trim("`n"))
    $eb=$eb.Replace(
        '                _hostMovieImageFormat == Format.R8Unorm &&',
        '                _hostMovieImageFormat == desiredLumaFormatV74088 &&'+"`n"+
        '                _v74088CreatedHostMovieLumaNumberType == _v74088HostMovieLumaNumberType &&'+"`n"+
        '                _v74088CreatedHostMovieChromaNumberType == _v74088HostMovieChromaNumberType &&')
    $eb=$eb.Replace(
        '                Format.R8Unorm,',
        '                desiredLumaFormatV74088,')
    $eb=$eb.Replace(
        '                Format.R8G8Unorm,',
        '                desiredChromaFormatV74088,')
    $eb=$eb.Replace(
        '            _hostMovieImageFormat = Format.R8Unorm;',
        '            _hostMovieImageFormat = desiredLumaFormatV74088;'+"`n"+
        '            _v74088CreatedHostMovieLumaNumberType = _v74088HostMovieLumaNumberType;'+"`n"+
        '            _v74088CreatedHostMovieChromaNumberType = _v74088HostMovieChromaNumberType;')
    $Text=ReplaceBody $Text $ensure $eb

    # Reset created format contract when host movie images are destroyed.
    $destroy=FindMethodSpan $Text '(?m)^[ \t]*private void DestroyHostMovieImage\(\)\s*$' 'DestroyHostMovieImage'
    $db=Body $Text $destroy
    $reset='            _hostMovieImageFormat = Format.Undefined;'
    if((CountText $db $reset) -ne 1){throw "DestroyHostMovieImage reset anchor count=$(CountText $db $reset)"}
    $db=$db.Replace(
        $reset,
        $reset+"`n"+
        '            _v74088CreatedHostMovieLumaNumberType = uint.MaxValue;'+"`n"+
        '            _v74088CreatedHostMovieChromaNumberType = uint.MaxValue;')
    $Text=ReplaceBody $Text $destroy $db

    # Expand the existing performance-overlay transfer image so it can also
    # carry the centered IME panel. No graphics pipeline is added.
    $createOverlay=FindMethodSpan $Text '(?m)^[ \t]*private void CreateOverlayResources\(\)\s*$' 'CreateOverlayResources'
    $ob=Body $Text $createOverlay
    $bytes='            const ulong overlayBytes = PerfOverlay.PanelWidth * PerfOverlay.PanelHeight * 4;'
    if((CountText $ob $bytes) -ne 1){throw "CreateOverlayResources bytes anchor count=$(CountText $ob $bytes)"}
    $overlayAlloc=@'
            var overlayWidthV74088 = Math.Max(
                PerfOverlay.PanelWidth,
                SharpEmu.Libs.Ime.ImeInWindowOverlay.PanelWidth);
            var overlayHeightV74088 = Math.Max(
                PerfOverlay.PanelHeight,
                SharpEmu.Libs.Ime.ImeInWindowOverlay.PanelHeight);
            var overlayBytes = checked(
                (ulong)overlayWidthV74088 * (ulong)overlayHeightV74088 * 4UL);
'@
    $ob=$ob.Replace($bytes,(NL $overlayAlloc).Trim("`n"))
    $ob=$ob.Replace(
        '                Extent = new Extent3D(PerfOverlay.PanelWidth, PerfOverlay.PanelHeight, 1),',
        '                Extent = new Extent3D((uint)overlayWidthV74088, (uint)overlayHeightV74088, 1),')
    $Text=ReplaceBody $Text $createOverlay $ob

    $blit=FindMethodSpan $Text '(?m)^[ \t]*private void RecordOverlayBlit\(uint imageIndex, int frameSlot\)\s*$' 'RecordOverlayBlit'
    $bb=Body $Text $blit
    $fill=@'
            var pixels = new Span<byte>(
                (void*)_overlayStagingMapped[frameSlot],
                PerfOverlay.PanelWidth * PerfOverlay.PanelHeight * 4);
            PerfOverlay.Fill(pixels, pendingWork, _pendingGuestSubmissions.Count);
'@
    $fill=(NL $fill).Trim("`n")
    if((CountText $bb $fill) -ne 1){throw "RecordOverlayBlit fill block count=$(CountText $bb $fill)"}
    $fillNew=@'
            var imeActiveV74088 = SharpEmu.Libs.Ime.ImeInWindowOverlay.Active;
            var overlayWidthV74088 = imeActiveV74088
                ? SharpEmu.Libs.Ime.ImeInWindowOverlay.PanelWidth
                : PerfOverlay.PanelWidth;
            var overlayHeightV74088 = imeActiveV74088
                ? SharpEmu.Libs.Ime.ImeInWindowOverlay.PanelHeight
                : PerfOverlay.PanelHeight;
            var pixels = new Span<byte>(
                (void*)_overlayStagingMapped[frameSlot],
                overlayWidthV74088 * overlayHeightV74088 * 4);
            if (imeActiveV74088)
            {
                SharpEmu.Libs.Ime.ImeInWindowOverlay.Fill(pixels);
            }
            else
            {
                PerfOverlay.Fill(pixels, pendingWork, _pendingGuestSubmissions.Count);
            }
'@
    $bb=$bb.Replace($fill,(NL $fillNew).Trim("`n"))
    $bb=$bb.Replace(
        '                ImageExtent = new Extent3D(PerfOverlay.PanelWidth, PerfOverlay.PanelHeight, 1),',
        '                ImageExtent = new Extent3D((uint)overlayWidthV74088, (uint)overlayHeightV74088, 1),')
    $bb=$bb.Replace(
        '            var panelWidth = (int)Math.Min(PerfOverlay.PanelWidth, _extent.Width - margin);',
        '            var panelWidth = (int)Math.Min((uint)overlayWidthV74088, _extent.Width - margin);')
    $bb=$bb.Replace(
        '            var panelHeight = (int)Math.Min(PerfOverlay.PanelHeight, _extent.Height - margin);',
        '            var panelHeight = (int)Math.Min((uint)overlayHeightV74088, _extent.Height - margin);')
    $dst='                DstOffset = new Offset3D(margin, margin, 0),'
    if((CountText $bb $dst) -ne 1){throw "RecordOverlayBlit DstOffset count=$(CountText $bb $dst)"}
    $bb=$bb.Replace(
        $dst,
        '                DstOffset = new Offset3D('+"`n"+
        '                    imeActiveV74088 ? Math.Max(0, ((int)_extent.Width - panelWidth) / 2) : margin,'+"`n"+
        '                    imeActiveV74088 ? Math.Max(0, ((int)_extent.Height - panelHeight) / 2) : margin,'+"`n"+
        '                    0),')
    $Text=ReplaceBody $Text $blit $bb

    $presentCondition='            if (PerfOverlay.Enabled)'
    if((CountText $Text $presentCondition) -ne 1){throw "Presenter overlay condition count=$(CountText $Text $presentCondition)"}
    $Text=$Text.Replace(
        $presentCondition,
        '            if (PerfOverlay.Enabled || SharpEmu.Libs.Ime.ImeInWindowOverlay.Active)')

    return $Text
}

function Apply-HostMovieV74088([string]$Text) {
    if($Text.Contains('SHARPEMU_V74_0_88_UI_BINK_GUEST_OWNED_LOOP')){return $Text}
    if(-not $Text.Contains('IsDemonSoulsUiBinkCompositePathV740841')){
        throw 'HostMovieBridge V84.1 UI-Bink classifier missing'
    }

    $tryDecl='    internal static bool TryDecodeNextFrame('
    if((CountText $Text $tryDecl) -ne 1){
        throw "TryDecodeNextFrame declaration count=$(CountText $Text $tryDecl)"
    }

    $helper=@'
    // SHARPEMU_V74_0_88_UI_BINK_GUEST_OWNED_LOOP
    // main_menu*.bk2 and logo_intro_loop.bk2 are persistent UI texture
    // producers. Rewind the host decoder at EOF without closing the logical
    // guest movie or pulsing the guest completion wait.
    private static bool TryRestartDemonSoulsUiBinkLoopV74088(
        string? hostPath)
    {
        if (string.IsNullOrWhiteSpace(hostPath) ||
            !IsDemonSoulsUiBinkCompositePathV740841(hostPath) ||
            string.Equals(
                Environment.GetEnvironmentVariable("SHARPEMU_DS_UI_BINK_LOOP"),
                "0",
                StringComparison.Ordinal))
        {
            return false;
        }

        if (!NihavBink2Decoder.TryOpen(
                hostPath,
                _presentationWidth,
                _presentationHeight,
                out var source) ||
            source is null)
        {
            Console.Error.WriteLine(
                $"[V74.0.88][UI_BINK_LOOP_RESTART] file='{Path.GetFileName(hostPath)}' result=open-failed");
            return false;
        }

        var info = new Bink2MovieInfo(
            source.Width,
            source.Height,
            source.FramesPerSecondNumerator,
            source.FramesPerSecondDenominator);
        if (!IsValid(info))
        {
            source.Dispose();
            return false;
        }

        _playback?.Dispose();
        _playback = new MediaFramePlayback(source);
        _activePath = hostPath;
        _activeInfo = info;

        Console.Error.WriteLine(
            $"[V74.0.88][UI_BINK_LOOP_RESTART] file='{Path.GetFileName(hostPath)}' " +
            $"result=rewound size={info.Width}x{info.Height} guest_movie_remains_open=True");
        return true;
    }

'@
    $Text=$Text.Replace($tryDecl,(NL $helper)+$tryDecl)

    $span=FindMethodSpan $Text '(?m)^[ \t]*internal static bool TryDecodeNextFrame\(' 'TryDecodeNextFrame'
    $body=Body $Text $span

    $finishedToken='if (_playback.IsFinished)'
    $finishedIndex=$body.IndexOf($finishedToken,[StringComparison]::Ordinal)
    if($finishedIndex -lt 0){
        throw 'TryDecodeNextFrame _playback.IsFinished branch not found'
    }
    if($body.IndexOf($finishedToken,$finishedIndex+$finishedToken.Length,[StringComparison]::Ordinal) -ge 0){
        throw 'TryDecodeNextFrame _playback.IsFinished branch is ambiguous'
    }

    $completedToken='var completedPath'
    $completedIndex=$body.IndexOf($completedToken,$finishedIndex,[StringComparison]::Ordinal)
    if($completedIndex -lt 0){
        throw 'TryDecodeNextFrame completedPath declaration not found after _playback.IsFinished'
    }

    $closeToken='CloseActiveLocked();'
    $closeIndex=$body.IndexOf($closeToken,$completedIndex,[StringComparison]::Ordinal)
    if($closeIndex -lt 0){
        throw 'TryDecodeNextFrame CloseActiveLocked not found after playback completion'
    }

    # Do not trust the accumulated whitespace or the exact log/progress layout.
    # Insert immediately before the close call that follows the managed playback
    # completion branch.
    $lineStart=$body.LastIndexOf("`n",$closeIndex)
    if($lineStart -lt 0){$lineStart=0}else{$lineStart++}
    $indent=''
    for($i=$lineStart;$i -lt $closeIndex;$i++){
        $ch=$body[$i]
        if($ch -eq ' ' -or $ch -eq "`t"){$indent+=$ch}else{break}
    }

    $restart=@'
if (TryRestartDemonSoulsUiBinkLoopV74088(completedPath))
{
    return false;
}

'@
    $restartLines=((NL $restart).Trim("`n") -split "`n" | ForEach-Object {$indent+$_}) -join "`n"
    $body=$body.Substring(0,$lineStart)+$restartLines+"`n"+$body.Substring($lineStart)

    return ReplaceBody $Text $span $body
}

function Assert-V74088([string]$Repo) {
    $p=Paths
    $ime=NL([IO.File]::ReadAllText($p.Ime))
    $overlay=NL([IO.File]::ReadAllText($p.ImeOverlay))
    $sdl=NL([IO.File]::ReadAllText($p.Sdl))
    $presenter=NL([IO.File]::ReadAllText($p.Presenter))
    $hostMovieText=NL([IO.File]::ReadAllText($p.Host))
    $missing=@()

    foreach($m in @('SHARPEMU_V74_0_88_IME_IN_WINDOW_SYSTEM_UI','ImeInWindowOverlay.Open')) {
        if(-not $ime.Contains($m)){$missing+="IME:$m"}
    }
    foreach($m in @('backend=sdl-vulkan-overlay','HandleGamepadButtons','PanelWidth = 900')) {
        if(-not $overlay.Contains($m)){$missing+="OVERLAY:$m"}
    }
    foreach($m in @('SHARPEMU_V74_0_88_IME_IN_WINDOW_SDL_INPUT','SHARPEMU_V74_0_88_IME_IN_WINDOW_GAMEPAD_INPUT')) {
        if(-not $sdl.Contains($m)){$missing+="SDL:$m"}
    }
    foreach($m in @(
        'SHARPEMU_V74_0_88_UI_BINK_UINT_PLANE_CONTRACT',
        'FindTypedUiBinkPlaneBindingsV74088',
        '[V74.0.88][UI_BINK_UINT_PLANE_BIND]',
        'desiredLumaFormatV74088',
        'desiredChromaFormatV74088',
        'ImeInWindowOverlay.Active')) {
        if(-not $presenter.Contains($m)){$missing+="PRESENTER:$m"}
    }
    foreach($m in @('SHARPEMU_V74_0_88_UI_BINK_GUEST_OWNED_LOOP','[V74.0.88][UI_BINK_LOOP_RESTART]')) {
        if(-not $hostMovieText.Contains($m)){$missing+="HOST:$m"}
    }

    if($missing.Count -gt 0){throw ('post-apply markers missing: '+($missing -join '; '))}
}
