param([Parameter(Mandatory=$true)][string]$PackageRoot)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$script:Tag='[V74.0.87.1]'
$PackageRoot=$PackageRoot.Trim().Trim([char]34).Trim([char]39)
$script:PackageRoot=(Resolve-Path -LiteralPath $PackageRoot).Path.TrimEnd('\')
$script:PatchesRoot=Split-Path -Parent $script:PackageRoot
$script:RepoRoot=Split-Path -Parent $script:PatchesRoot
$script:AgcRel='src\SharpEmu.Libs\Agc\AgcExports.cs'
$script:PresenterRel='src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$script:AgcPath=Join-Path $script:RepoRoot $script:AgcRel
$script:PresenterPath=Join-Path $script:RepoRoot $script:PresenterRel
$script:BackupRoot=Join-Path $script:RepoRoot '.sharpemu-hotfix-backup'
$script:StateFile=Join-Path $script:PackageRoot 'LAST_BACKUP_V87_1.txt'
$script:FieldMarkerV871='SHARPEMU_V74_0_87_1_COOPERATIVE_GATE_QUANTUM'
$script:YieldMarkerV871='SHARPEMU_V74_0_87_1_GATE_QUANTUM_YIELD'
$script:OldFieldMarkerV87='SHARPEMU_V74_0_87_COOPERATIVE_GATE_QUANTUM'
$script:OldYieldMarkerV87='SHARPEMU_V74_0_87_GATE_QUANTUM_YIELD'

function Get-Sha256([string]$Path){return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()}
function Read-Utf8([string]$Path){return [System.IO.File]::ReadAllText($Path,[System.Text.Encoding]::UTF8)}
function Write-Utf8NoBom([string]$Path,[string]$Text){$enc=New-Object System.Text.UTF8Encoding($false);[System.IO.File]::WriteAllText($Path,$Text,$enc)}
function Get-Count([string]$Text,[string]$Pattern){return ([regex]::Matches($Text,$Pattern,[System.Text.RegularExpressions.RegexOptions]::Multiline)).Count}
function Normalize-Nl([string]$Text,[string]$Nl){return $Text.Replace("`r`n","`n").Replace("`r","`n").Replace("`n",$Nl)}

# Returns lexical C# brace pairs while ignoring braces inside comments, chars,
# normal/verbatim/interpolated strings and raw string literals. This avoids the
# V87 bug where interpolated telemetry text could corrupt a naive brace count.
function Get-CSharpBracePairs([string]$Text){
    $stack=New-Object 'System.Collections.Generic.List[int]'
    $pairs=New-Object 'System.Collections.Generic.List[object]'
    $state=0 # 0 normal, 1 line-comment, 2 block-comment, 3 string, 4 verbatim, 5 char, 6 raw-string
    $rawQuotes=0
    $i=0
    while($i -lt $Text.Length){
        $ch=$Text[$i]
        $next=if($i+1 -lt $Text.Length){$Text[$i+1]}else{[char]0}
        if($state -eq 1){
            if($ch -eq "`n" -or $ch -eq "`r"){$state=0}
            $i++;continue
        }
        if($state -eq 2){
            if($ch -eq '*' -and $next -eq '/'){$state=0;$i+=2;continue}
            $i++;continue
        }
        if($state -eq 3){
            if($ch -eq [char]92){$i+=2;continue}
            if($ch -eq [char]34){$state=0}
            $i++;continue
        }
        if($state -eq 4){
            if($ch -eq [char]34){
                if($next -eq [char]34){$i+=2;continue}
                $state=0
            }
            $i++;continue
        }
        if($state -eq 5){
            if($ch -eq [char]92){$i+=2;continue}
            if($ch -eq [char]39){$state=0}
            $i++;continue
        }
        if($state -eq 6){
            if($ch -eq [char]34){
                $run=1
                while($i+$run -lt $Text.Length -and $Text[$i+$run] -eq [char]34){$run++}
                if($run -ge $rawQuotes){$state=0;$i+=$run;continue}
            }
            $i++;continue
        }

        if($ch -eq '/' -and $next -eq '/'){$state=1;$i+=2;continue}
        if($ch -eq '/' -and $next -eq '*'){$state=2;$i+=2;continue}
        if($ch -eq [char]39){$state=5;$i++;continue}
        if($ch -eq [char]34){
            $run=1
            while($i+$run -lt $Text.Length -and $Text[$i+$run] -eq [char]34){$run++}
            if($run -ge 3){$state=6;$rawQuotes=$run;$i+=$run;continue}
            $isVerbatim=($i -gt 0 -and $Text[$i-1] -eq '@') -or
                ($i -gt 1 -and $Text[$i-2] -eq '@' -and $Text[$i-1] -eq '$')
            $state=if($isVerbatim){4}else{3}
            $i++;continue
        }
        if($ch -eq '{'){$stack.Add($i);$i++;continue}
        if($ch -eq '}'){
            if($stack.Count -gt 0){
                $open=$stack[$stack.Count-1]
                $stack.RemoveAt($stack.Count-1)
                $pairs.Add([pscustomobject]@{Open=$open;Close=$i;Span=($i-$open)})
            }
            $i++;continue
        }
        $i++
    }
    return $pairs.ToArray()
}

# Given a lexical opening brace, classify it as a private C# method body when
# the immediately preceding declaration is a private method. No method-name or
# line-number anchor is hard-coded.
function Get-PrivateMethodHeaderForBrace([string]$Text,[int]$Brace){
    $windowStart=[Math]::Max(0,$Brace-8192)
    $prefix=$Text.Substring($windowStart,$Brace-$windowStart)
    $pattern='(?s)(?:^|[\r\n])[ \t]*private[ \t]+(?:(?:static|unsafe|async|partial|extern|new)[ \t]+)*[^;{}=]+?\b(?<Name>[A-Za-z_][A-Za-z0-9_]*)(?:[ \t]*<[^;{}()]+>)?[ \t]*\((?<Params>[^;{}]*?)\)[ \t\r\n]*(?:where[^{]+)?\z'
    $m=[regex]::Match($prefix,$pattern)
    if(-not $m.Success){return $null}
    $privateOffset=$m.Value.IndexOf('private',[System.StringComparison]::Ordinal)
    if($privateOffset -lt 0){return $null}
    $params=$m.Groups['Params'].Value
    $sp=[regex]::Match($params,'\bSubmittedGpuState\??[ \t\r\n]+(?<State>[A-Za-z_][A-Za-z0-9_]*)\b')
    return [pscustomobject]@{
        Start=($windowStart+$m.Index+$privateOffset)
        Brace=$Brace
        Name=$m.Groups['Name'].Value
        Params=$params
        StateParam=$(if($sp.Success){$sp.Groups['State'].Value}else{''})
    }
}

# V87 incorrectly inspected only IndexOf(marker), i.e. the first occurrence.
# V87.1 examines every marker occurrence and maps each one through lexical brace
# pairs to its containing private method. Only methods with SubmittedGpuState
# participate; duplicate marker occurrences in one method are de-duplicated.
function Get-GateOwnerCandidates([string]$Text){
    $marker='GATE_OWNER_WAIT_DRAIN'
    $positions=New-Object 'System.Collections.Generic.List[int]'
    $at=0
    while($at -lt $Text.Length){
        $mi=$Text.IndexOf($marker,$at,[System.StringComparison]::Ordinal)
        if($mi -lt 0){break}
        $positions.Add($mi)
        $at=$mi+$marker.Length
    }
    $pairs=@(Get-CSharpBracePairs $Text)
    $byBrace=@{}
    foreach($mi in $positions){
        $enclosing=@($pairs | Where-Object {$_.Open -lt $mi -and $_.Close -gt $mi} | Sort-Object Span)
        foreach($pair in $enclosing){
            $head=Get-PrivateMethodHeaderForBrace $Text $pair.Open
            if($null -eq $head){continue}
            if([string]::IsNullOrWhiteSpace($head.StateParam)){continue}
            $key=[string]$pair.Open
            if(-not $byBrace.ContainsKey($key)){
                $byBrace[$key]=[pscustomobject]@{
                    Start=$head.Start
                    Brace=$pair.Open
                    Close=$pair.Close
                    Length=($pair.Close-$head.Start+1)
                    Name=$head.Name
                    StateParam=$head.StateParam
                    MarkerIndex=$mi
                    MarkerHits=1
                }
            }else{
                $byBrace[$key].MarkerHits++
            }
            break
        }
    }
    return @($byBrace.Values | Sort-Object Start)
}

function Get-SingleGateOwnerCandidate([string]$Text,[bool]$Print=$false){
    $markers=Get-Count $Text 'GATE_OWNER_WAIT_DRAIN'
    $candidates=@(Get-GateOwnerCandidates $Text)
    if($Print){
        Write-Host "$script:Tag GateOwnerMarker=$markers"
        Write-Host "$script:Tag GateOwnerCandidateCount=$($candidates.Count)"
        for($i=0;$i -lt $candidates.Count;$i++){
            $c=$candidates[$i]
            Write-Host "$script:Tag GateOwnerCandidate[$i]=Name=$($c.Name) StateParam=$($c.StateParam) Start=$($c.Start) Brace=$($c.Brace) Close=$($c.Close) MarkerHits=$($c.MarkerHits)"
        }
    }
    if($markers -lt 1){throw "$script:Tag GATE_OWNER_WAIT_DRAIN nao existe no source."}
    if($candidates.Count -ne 1){throw "$script:Tag esperado exatamente 1 metodo candidato V72; encontrado=$($candidates.Count), markers=$markers."}
    return $candidates[0]
}

function Invoke-GateQuantumTransform([string]$Text){
    $newField=Get-Count $Text $script:FieldMarkerV871
    $newYield=Get-Count $Text $script:YieldMarkerV871
    $oldField=Get-Count $Text $script:OldFieldMarkerV87
    $oldYield=Get-Count $Text $script:OldYieldMarkerV87
    if(($newField -gt 0) -xor ($newYield -gt 0)){throw "$script:Tag estado V87.1 parcial detectado (field=$newField yield=$newYield)."}
    if(($oldField -gt 0) -xor ($oldYield -gt 0)){throw "$script:Tag estado V87 antigo parcial detectado (field=$oldField yield=$oldYield)."}
    if($newField -gt 0 -and $newYield -gt 0){
        $gate=Get-SingleGateOwnerCandidate $Text $false
        return [pscustomobject]@{Text=$Text;Gate=$gate;AlreadyApplied=$true;LegacyV87=$false}
    }
    if($oldField -gt 0 -and $oldYield -gt 0){
        $gate=Get-SingleGateOwnerCandidate $Text $false
        return [pscustomobject]@{Text=$Text;Gate=$gate;AlreadyApplied=$true;LegacyV87=$true}
    }

    $gate=Get-SingleGateOwnerCandidate $Text $false
    $nl=if($Text.Contains("`r`n")){"`r`n"}else{"`n"}
    $fields=@'
    // SHARPEMU_V74_0_87_1_COOPERATIVE_GATE_QUANTUM
    // V86.4 proved resident retention is not the dominant limiter. V71/V72 show
    // long starvation on gpuState.Gate. Bound ownership to short packet quanta
    // and hand the monitor to queued waiter/submit threads only after the V72
    // complete-packet drain hook. Environment 0/0 restores legacy ownership.
    private static readonly int _gateQuantumPacketsV740871 =
        int.TryParse(Environment.GetEnvironmentVariable("SHARPEMU_AGC_GATE_QUANTUM_PACKETS"), out var gateQuantumPacketsV740871) && gateQuantumPacketsV740871 >= 0
            ? gateQuantumPacketsV740871
            : 16;
    private static readonly long _gateQuantumTicksV740871 =
        (long.TryParse(Environment.GetEnvironmentVariable("SHARPEMU_AGC_GATE_QUANTUM_MS"), out var gateQuantumMsV740871) && gateQuantumMsV740871 >= 0
            ? gateQuantumMsV740871
            : 1L) * System.Diagnostics.Stopwatch.Frequency / 1000L;
    [ThreadStatic] private static int _gateQuantumPacketCountV740871;
    [ThreadStatic] private static long _gateQuantumStartTicksV740871;
    private static long _gateQuantumYieldTraceCountV740871;

'@
    $fields=Normalize-Nl $fields $nl
    $work=$Text.Insert($gate.Start,$fields)

    # Re-locate after class-scope field insertion because absolute indices moved.
    $gate=Get-SingleGateOwnerCandidate $work $false
    $sp=$gate.StateParam
    $yield=@'

        // SHARPEMU_V74_0_87_1_GATE_QUANTUM_YIELD
        // V72 is invoked at a complete PM4 packet boundary. Do not release the
        // monitor inside a packet or ordered side effect; always re-enter in finally.
        if ((_gateQuantumPacketsV740871 > 0 || _gateQuantumTicksV740871 > 0) &&
            System.Threading.Monitor.IsEntered(__STATE__.Gate))
        {
            var gateQuantumNowV740871 = System.Diagnostics.Stopwatch.GetTimestamp();
            if (_gateQuantumStartTicksV740871 == 0)
            {
                _gateQuantumStartTicksV740871 = gateQuantumNowV740871;
            }
            var gateQuantumPacketsSeenV740871 = ++_gateQuantumPacketCountV740871;
            var gateQuantumElapsedV740871 = gateQuantumNowV740871 - _gateQuantumStartTicksV740871;
            var gateQuantumDueV740871 =
                (_gateQuantumPacketsV740871 > 0 && gateQuantumPacketsSeenV740871 >= _gateQuantumPacketsV740871) ||
                (_gateQuantumTicksV740871 > 0 && gateQuantumElapsedV740871 >= _gateQuantumTicksV740871);
            if (gateQuantumDueV740871)
            {
                _gateQuantumPacketCountV740871 = 0;
                _gateQuantumStartTicksV740871 = 0;
                System.Threading.Monitor.Exit(__STATE__.Gate);
                try
                {
                    if (!System.Threading.Thread.Yield())
                    {
                        System.Threading.Thread.Sleep(0);
                    }
                }
                finally
                {
                    System.Threading.Monitor.Enter(__STATE__.Gate);
                }

                var gateQuantumYieldV740871 = System.Threading.Interlocked.Increment(
                    ref _gateQuantumYieldTraceCountV740871);
                if (gateQuantumYieldV740871 <= 256 ||
                    (gateQuantumYieldV740871 & (gateQuantumYieldV740871 - 1)) == 0)
                {
                    var gateQuantumUsV740871 = gateQuantumElapsedV740871 * 1000000.0 /
                        System.Diagnostics.Stopwatch.Frequency;
                    Console.Error.WriteLine(
                        $"[V74.0.87.1][GATE_QUANTUM_YIELD] count={gateQuantumYieldV740871} " +
                        $"packets={gateQuantumPacketsSeenV740871} elapsed_us={gateQuantumUsV740871:F1}");
                }
            }
        }
'@
    $yield=(Normalize-Nl $yield $nl).Replace('__STATE__',$sp)
    $work=$work.Insert($gate.Close,$yield)

    if((Get-Count $work $script:FieldMarkerV871) -ne 1){throw "$script:Tag V87.1 field marker count invalido apos dry-run."}
    if((Get-Count $work $script:YieldMarkerV871) -ne 1){throw "$script:Tag V87.1 yield marker count invalido apos dry-run."}
    $after=Get-SingleGateOwnerCandidate $work $false
    if($after.Name -ne $gate.Name -or $after.StateParam -ne $sp){throw "$script:Tag V72 method identity mudou apos transformacao."}
    return [pscustomobject]@{Text=$work;Gate=$after;AlreadyApplied=$false;LegacyV87=$false}
}

function Invoke-StructuralLocatorSelfTest{
    # Reproduces the V87 failure mode deliberately: four occurrences, but only
    # one is inside a private method that takes SubmittedGpuState. Includes
    # comments/interpolated/verbatim/raw strings with braces to exercise lexer.
    $fixture=@'
namespace Probe;
public static class AgcExports
{
    private const string MarkerOutsideMethod = "GATE_OWNER_WAIT_DRAIN";
    // GATE_OWNER_WAIT_DRAIN outside method { ignored }
    private static readonly string Braces = @"{not code}";
    private static readonly string RawBraces = """{raw not code}""";

    private static void Unrelated(SubmittedGpuState unrelated)
    {
        Console.WriteLine("no marker here { still string }");
    }

    private static int DrainAtPacketBoundary(
        CpuContext ctx,
        SubmittedGpuState gpuState,
        SubmittedDcbState state,
        ulong commandAddress,
        int dw)
    {
        var fake = $"prefix {{literal}} queue={state.QueueName}";
        // { comment brace must not affect method close }
        Console.Error.WriteLine(
            $"[V74.0.72][GATE_OWNER_WAIT_DRAIN] queue={state.QueueName} dw={dw}");
        return 0;
    }

    private static void TextOnly()
    {
        Console.WriteLine("GATE_OWNER_WAIT_DRAIN without SubmittedGpuState");
    }
}
'@
    if((Get-Count $fixture 'GATE_OWNER_WAIT_DRAIN') -ne 4){throw "$script:Tag SELFTEST fixture marker count drifted."}
    $c=@(Get-GateOwnerCandidates $fixture)
    if($c.Count -ne 1){throw "$script:Tag SELFTEST locator expected 1 candidate, got $($c.Count)."}
    if($c[0].Name -ne 'DrainAtPacketBoundary' -or $c[0].StateParam -ne 'gpuState'){throw "$script:Tag SELFTEST locator classified wrong method/state."}
    $x=Invoke-GateQuantumTransform $fixture
    if($x.AlreadyApplied){throw "$script:Tag SELFTEST first transform unexpectedly idempotent."}
    if((Get-Count $x.Text $script:FieldMarkerV871) -ne 1 -or (Get-Count $x.Text $script:YieldMarkerV871) -ne 1){throw "$script:Tag SELFTEST transform markers invalid."}
    $x2=Invoke-GateQuantumTransform $x.Text
    if(-not $x2.AlreadyApplied -or $x2.Text -ne $x.Text){throw "$script:Tag SELFTEST idempotence failed."}
    Write-Host "$script:Tag STRUCTURAL LOCATOR SELFTEST PASSED (4 markers -> 1 method; lexical braces; transform+idempotence)." -ForegroundColor Green
}

function Invoke-CheckoutStructuralDryRun{
    if(-not(Test-Path -LiteralPath $script:AgcPath -PathType Leaf)){
        Write-Host "$script:Tag CURRENT CHECKOUT DRY-RUN SKIPPED (AgcExports.cs not found relative to package)." -ForegroundColor Yellow
        return
    }
    $shaBefore=Get-Sha256 $script:AgcPath
    $a=Read-Utf8 $script:AgcPath
    $gate=Get-SingleGateOwnerCandidate $a $true
    $dry=Invoke-GateQuantumTransform $a
    $shaAfter=Get-Sha256 $script:AgcPath
    if($shaBefore -ne $shaAfter){throw "$script:Tag read-only dry-run modified AgcExports.cs unexpectedly."}
    if(-not $dry.AlreadyApplied){
        if($dry.Text -eq $a){throw "$script:Tag dry-run produced no transformed text."}
        if((Get-Count $dry.Text $script:FieldMarkerV871) -ne 1 -or (Get-Count $dry.Text $script:YieldMarkerV871) -ne 1){throw "$script:Tag dry-run output marker validation failed."}
    }
    Write-Host "$script:Tag CURRENT CHECKOUT STRUCTURAL DRY-RUN PASSED (read-only). Method=$($gate.Name) StateParam=$($gate.StateParam) SHA256=$shaBefore" -ForegroundColor Green
}

function Assert-Repo{
    if(-not(Test-Path -LiteralPath $script:AgcPath -PathType Leaf)){throw "$script:Tag AgcExports.cs ausente: $script:AgcPath"}
    if(-not(Test-Path -LiteralPath $script:PresenterPath -PathType Leaf)){throw "$script:Tag Presenter ausente: $script:PresenterPath"}
}

function Assert-StructuralContracts{
    Assert-Repo
    $a=Read-Utf8 $script:AgcPath
    $p=Read-Utf8 $script:PresenterPath
    $gate=Get-SingleGateOwnerCandidate $a $true
    $checks=[ordered]@{
        V812=(Get-Count $p 'SHARPEMU_V74_0_81_2_SEMANTIC_BOUNDARY_REPAIR')
        V82=(Get-Count $p 'SHARPEMU_V74_0_82_NONBLOCKING_VISIBILITY_DCC_INDEX')
        V84=(Get-Count $p 'SHARPEMU_V74_0_84_SUBMISSION_HEADROOM_ADAPTIVE')
        V85=(Get-Count $a 'SHARPEMU_V74_0_85_AGGRESSIVE_PM4_LOCAL_PAYLOAD_RELEASE_QUEUE')
        V864Agc=(Get-Count $a 'SHARPEMU_V74_0_86_4_RESIDENT_TEXTURE_RETENTION_SEMICOLON_ANCHOR')
        V864Presenter=(Get-Count $p 'SHARPEMU_V74_0_86_4_RESIDENT_TEXTURE_RETENTION_SEMICOLON_ANCHOR')
        V871Field=(Get-Count $a $script:FieldMarkerV871)
        V871Yield=(Get-Count $a $script:YieldMarkerV871)
        OldV87Field=(Get-Count $a $script:OldFieldMarkerV87)
        OldV87Yield=(Get-Count $a $script:OldYieldMarkerV87)
    }
    foreach($e in $checks.GetEnumerator()){Write-Host "$script:Tag $($e.Key)=$($e.Value)"}
    if($checks.V812 -lt 1 -or $checks.V82 -lt 1 -or $checks.V84 -lt 1 -or $checks.V85 -lt 1){throw "$script:Tag base V81.2/V82/V84/V85 incompleta."}
    if($checks.V864Agc -lt 1 -or $checks.V864Presenter -lt 1){throw "$script:Tag V86.4 nao detectada nos dois sources."}
    if(($checks.V871Field -gt 0) -xor ($checks.V871Yield -gt 0)){throw "$script:Tag V87.1 parcial no source."}
    if(($checks.OldV87Field -gt 0) -xor ($checks.OldV87Yield -gt 0)){throw "$script:Tag V87 antigo parcial no source."}
    return [pscustomobject]@{Agc=$a;Presenter=$p;Gate=$gate;Checks=$checks}
}

function New-Backup{
    if(-not(Test-Path -LiteralPath $script:BackupRoot)){New-Item -ItemType Directory -Path $script:BackupRoot|Out-Null}
    $dir=Join-Path $script:BackupRoot ("CooperativeGateQuantumV740871_"+(Get-Date -Format 'yyyyMMdd_HHmmss'))
    New-Item -ItemType Directory -Path $dir|Out-Null
    Copy-Item -LiteralPath $script:AgcPath -Destination (Join-Path $dir 'AgcExports.cs') -Force
    Write-Utf8NoBom $script:StateFile $dir
    return $dir
}
function Restore-Backup([string]$Dir){$x=Join-Path $Dir 'AgcExports.cs';if(-not(Test-Path -LiteralPath $x -PathType Leaf)){throw "$script:Tag backup AgcExports ausente: $x"};Copy-Item -LiteralPath $x -Destination $script:AgcPath -Force}
function Find-SharpEmuExe{$c=@((Join-Path $script:RepoRoot 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'),(Join-Path $script:RepoRoot 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.CLI.exe'));foreach($x in $c){if(Test-Path -LiteralPath $x -PathType Leaf){return $x}};return $null}
