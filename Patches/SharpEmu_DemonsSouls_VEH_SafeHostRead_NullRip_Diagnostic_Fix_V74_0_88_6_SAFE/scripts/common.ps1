Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$script:Tag='[V74.0.88.6]'

function PackageRoot { return (Split-Path -Parent $PSScriptRoot) }
function Patches { return (Split-Path -Parent (PackageRoot)) }
function RepoRoot { return (Split-Path -Parent (Patches)) }
function Sha([string]$p) { return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToUpperInvariant() }
function NL([string]$s) { return $s.Replace("`r`n","`n").Replace("`r","`n") }

function Paths {
    $repo=RepoRoot
    return [pscustomobject]@{
        Repo=$repo
        NativeDir=Join-Path $repo 'src\SharpEmu.Core\Cpu\Native'
        Cli=Join-Path $repo 'src\SharpEmu.CLI\SharpEmu.CLI.csproj'
        Exe=Join-Path $repo 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'
        Presenter=Join-Path $repo 'src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
        HostMovie=Join-Path $repo 'src\SharpEmu.Libs\Media\HostMovieBridge.cs'
        ImeOverlay=Join-Path $repo 'src\SharpEmu.Libs\Ime\ImeInWindowOverlay.cs'
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
                    DeclarationLength=$decl.Length
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

function ReplaceBody([string]$Text,$Span,[string]$NewBody) {
    return $Text.Substring(0,$Span.BodyStart)+$NewBody+$Text.Substring($Span.CloseBrace)
}

function Find-DirectBackendFiles {
    $p=Paths
    if(-not(Test-Path -LiteralPath $p.NativeDir)){throw "Native directory missing: $($p.NativeDir)"}
    return @(Get-ChildItem -LiteralPath $p.NativeDir -Filter 'DirectExecutionBackend*.cs' -File | Sort-Object FullName)
}

function Locate-Method([string]$Name,[string]$DeclarationRegex) {
    $hits=@()
    foreach($file in Find-DirectBackendFiles){
        $text=NL([IO.File]::ReadAllText($file.FullName))
        if([regex]::IsMatch($text,$DeclarationRegex,[Text.RegularExpressions.RegexOptions]::Multiline)){
            $hits += [pscustomobject]@{ File=$file.FullName; Text=$text }
        }
    }
    if($hits.Count -ne 1){
        throw "$Name source file count=$($hits.Count); expected exactly 1"
    }
    $span=FindMethodSpan $hits[0].Text $DeclarationRegex $Name
    return [pscustomobject]@{
        File=$hits[0].File
        Text=$hits[0].Text
        Span=$span
        Body=(Body $hits[0].Text $span)
    }
}

function Locate-TryReadHostQword {
    return Locate-Method 'TryReadHostQword' '(?m)^[ \t]*private[ \t]+(?:unsafe[ \t]+)?static[ \t]+bool[ \t]+TryReadHostQword[ \t]*\([ \t]*ulong[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*,[ \t]*out[ \t]+ulong[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*\)'
}

function Locate-VectoredHandler {
    return Locate-Method 'VectoredHandler' '(?m)^[ \t]*private[ \t]+(?:unsafe[ \t]+)?int[ \t]+VectoredHandler[ \t]*\([ \t]*void\*[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*\)'
}

function Export-MethodDiagnostic([string]$Reason) {
    $patches=Patches
    $stamp=Get-Date -Format yyyyMMdd_HHmmss
    $out=Join-Path $patches ("SharpEmu_V74_0_88_6_METHOD_DIAGNOSTIC_"+$stamp+".txt")
    $lines=@()
    $lines+="$script:Tag $Reason"
    foreach($file in Find-DirectBackendFiles){
        $text=NL([IO.File]::ReadAllText($file.FullName))
        if($text.Contains('TryReadHostQword') -or $text.Contains('VectoredHandler')){
            $lines+="FILE=$($file.FullName)"
            $lines+="SHA256=$(Sha $file.FullName)"
            $lines+='--- relevant lines ---'
            $arr=$text -split "`n"
            for($i=0;$i -lt $arr.Length;$i++){
                if($arr[$i] -match 'TryReadHostQword|VectoredHandler|Marshal\.ReadInt64'){
                    $start=[Math]::Max(0,$i-12)
                    $end=[Math]::Min($arr.Length-1,$i+36)
                    for($j=$start;$j -le $end;$j++){
                        $lines+=("{0,6}: {1}" -f ($j+1),$arr[$j])
                    }
                    $lines+='---'
                }
            }
        }
    }
    $lines|Set-Content -LiteralPath $out -Encoding UTF8
    Write-Host "$script:Tag DiagnosticExport=$out" -ForegroundColor Yellow
    return $out
}

function Apply-SafeHostQwordV740886([string]$Text,$Span) {
    if($Text.Contains('SHARPEMU_V74_0_88_6_VEH_SAFE_HOST_QWORD')){
        return $Text
    }

    $newBody=@'

        // SHARPEMU_V74_0_88_6_VEH_SAFE_HOST_QWORD
        // This helper is called from the Windows VEH diagnostic/recovery path.
        // Never dereference a host pointer until the complete qword lies inside
        // a committed, readable, non-guarded region.  A managed
        // AccessViolationException raised inside VEH is process-fatal and
        // prevents the emulator from reporting/recovering the original guest
        // exception.
        value = 0;

        if (address == 0 || address > (ulong)nint.MaxValue)
        {
            Console.Error.WriteLine(
                $"[V74.0.88.6][VEH_SAFE_READ_REJECT] addr=0x{address:X16} reason=range");
            return false;
        }

        if (VirtualQuery(
                (void*)address,
                out var memoryInfoV740886,
                (nuint)sizeof(MEMORY_BASIC_INFORMATION64)) == 0 ||
            memoryInfoV740886.RegionSize < sizeof(ulong))
        {
            Console.Error.WriteLine(
                $"[V74.0.88.6][VEH_SAFE_READ_REJECT] addr=0x{address:X16} reason=query");
            return false;
        }

        const uint MemCommitV740886 = 0x00001000;
        const uint PageNoAccessV740886 = 0x00000001;
        const uint PageGuardV740886 = 0x00000100;

        if (memoryInfoV740886.State != MemCommitV740886 ||
            memoryInfoV740886.Protect == 0 ||
            (memoryInfoV740886.Protect &
                (PageNoAccessV740886 | PageGuardV740886)) != 0)
        {
            Console.Error.WriteLine(
                $"[V74.0.88.6][VEH_SAFE_READ_REJECT] addr=0x{address:X16} " +
                $"reason=protect state=0x{memoryInfoV740886.State:X8} " +
                $"protect=0x{memoryInfoV740886.Protect:X8}");
            return false;
        }

        var regionStartV740886 = memoryInfoV740886.BaseAddress;
        var regionEndV740886 =
            regionStartV740886 > ulong.MaxValue - memoryInfoV740886.RegionSize
                ? ulong.MaxValue
                : regionStartV740886 + memoryInfoV740886.RegionSize;

        if (address < regionStartV740886 ||
            regionEndV740886 < sizeof(ulong) ||
            address > regionEndV740886 - sizeof(ulong))
        {
            Console.Error.WriteLine(
                $"[V74.0.88.6][VEH_SAFE_READ_REJECT] addr=0x{address:X16} reason=boundary");
            return false;
        }

        // The page is committed/readable and the whole qword fits in it.
        value = unchecked((ulong)Marshal.ReadInt64((nint)address));
        return true;

'@
    return ReplaceBody $Text $Span ((NL $newBody).TrimEnd("`n"))
}

function Assert-V740886 {
    $read=Locate-TryReadHostQword
    $handler=Locate-VectoredHandler
    $text=NL([IO.File]::ReadAllText($read.File))
    $missing=@()
    foreach($marker in @(
        'SHARPEMU_V74_0_88_6_VEH_SAFE_HOST_QWORD',
        '[V74.0.88.6][VEH_SAFE_READ_REJECT]',
        'VirtualQuery(',
        'MemCommitV740886',
        'PageNoAccessV740886',
        'PageGuardV740886',
        'regionEndV740886'))
    {
        if(-not $text.Contains($marker)){$missing+="READ:$marker"}
    }

    $body=Body $text (FindMethodSpan $text '(?m)^[ \t]*private[ \t]+(?:unsafe[ \t]+)?static[ \t]+bool[ \t]+TryReadHostQword[ \t]*\([ \t]*ulong[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*,[ \t]*out[ \t]+ulong[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*\)' 'TryReadHostQword')
    if(-not $body.Contains('Marshal.ReadInt64')){$missing+='READ:Marshal.ReadInt64 final read missing'}
    if($body.IndexOf('VirtualQuery(') -gt $body.IndexOf('Marshal.ReadInt64')){
        $missing+='READ:validation does not precede Marshal.ReadInt64'
    }

    if($missing.Count -gt 0){
        throw ('V74.0.88.6 validation failed: '+($missing -join '; '))
    }

    return [pscustomobject]@{
        ReadFile=$read.File
        HandlerFile=$handler.File
    }
}
