param([Parameter(Mandatory=$true)][string]$PackageRoot)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$script:Tag='[V74.0.87.2]'
$PackageRoot=$PackageRoot.Trim().Trim([char]34).Trim([char]39)
$script:PackageRoot=(Resolve-Path -LiteralPath $PackageRoot).Path.TrimEnd('\')
$script:PatchesRoot=Split-Path -Parent $script:PackageRoot
$script:RepoRoot=Split-Path -Parent $script:PatchesRoot
$script:AgcRel='src\SharpEmu.Libs\Agc\AgcExports.cs'
$script:PresenterRel='src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$script:AgcPath=Join-Path $script:RepoRoot $script:AgcRel
$script:PresenterPath=Join-Path $script:RepoRoot $script:PresenterRel
$script:BackupRoot=Join-Path $script:RepoRoot '.sharpemu-hotfix-backup'
$script:StateFile=Join-Path $script:PackageRoot 'LAST_BACKUP_V87_2.txt'
$script:FieldMarkerV872='SHARPEMU_V74_0_87_2_COOPERATIVE_GATE_QUANTUM'
$script:YieldMarkerV872='SHARPEMU_V74_0_87_2_GATE_QUANTUM_YIELD'
$script:PrevFieldMarkerV871='SHARPEMU_V74_0_87_1_COOPERATIVE_GATE_QUANTUM'
$script:PrevYieldMarkerV871='SHARPEMU_V74_0_87_1_GATE_QUANTUM_YIELD'
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
# V87.2 examines every marker occurrence and maps each one through lexical brace
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
    $preferred=@($candidates | Where-Object {$_.Name -eq 'TryDrainPendingWaitersOnGateOwnerV74072'})
    $semantic=@($candidates | Where-Object {
        $_.Name -match '(?i)GateOwner' -and $_.Name -match '(?i)Drain'
    })
    $selected=$null
    $strategy='none'
    if($preferred.Count -eq 1){
        $selected=$preferred[0]
        $strategy='exact-dedicated-v72-helper'
    }elseif($preferred.Count -gt 1){
        throw "$script:Tag mais de um TryDrainPendingWaitersOnGateOwnerV74072 foi localizado."
    }elseif($semantic.Count -eq 1){
        $selected=$semantic[0]
        $strategy='semantic-gateowner-drain-helper'
    }elseif($candidates.Count -eq 1){
        # Compatibility fallback only for a future source that inlines/renames the
        # V72 helper and leaves one unambiguous SubmittedGpuState owner candidate.
        $selected=$candidates[0]
        $strategy='single-candidate-fallback'
    }
    if($Print){
        Write-Host "$script:Tag GateOwnerMarker=$markers"
        Write-Host "$script:Tag GateOwnerCandidateCount=$($candidates.Count)"
        for($i=0;$i -lt $candidates.Count;$i++){
            $c=$candidates[$i]
            $role=if($c.Name -eq 'TryDrainPendingWaitersOnGateOwnerV74072'){'dedicated-v72'}elseif($c.Name -match '(?i)GateOwner' -and $c.Name -match '(?i)Drain'){'semantic-drain'}else{'non-dedicated'}
            Write-Host "$script:Tag GateOwnerCandidate[$i]=Name=$($c.Name) StateParam=$($c.StateParam) Start=$($c.Start) Brace=$($c.Brace) Close=$($c.Close) MarkerHits=$($c.MarkerHits) Role=$role"
        }
        if($null -ne $selected){
            Write-Host "$script:Tag GateOwnerSelected=Name=$($selected.Name) StateParam=$($selected.StateParam) Strategy=$strategy"
        }
    }
    if($markers -lt 1){throw "$script:Tag GATE_OWNER_WAIT_DRAIN nao existe no source."}
    if($null -eq $selected){
        throw "$script:Tag nenhum helper GateOwner/Drain inequivoco foi selecionado; candidates=$($candidates.Count), preferred=$($preferred.Count), semantic=$($semantic.Count), markers=$markers."
    }
    # The current accumulated checkout is expected to expose both ParseSubmittedDcbCore
    # and the dedicated V72 drain helper. Never select the broad parser when the helper exists.
    if($selected.Name -eq 'ParseSubmittedDcbCore' -and ($preferred.Count -gt 0 -or $semantic.Count -gt 0)){
        throw "$script:Tag classificador tentou selecionar ParseSubmittedDcbCore apesar de helper V72 dedicado existente."
    }
    return [pscustomobject]@{
        Start=$selected.Start;Brace=$selected.Brace;Close=$selected.Close;Length=$selected.Length
        Name=$selected.Name;StateParam=$selected.StateParam;MarkerIndex=$selected.MarkerIndex
        MarkerHits=$selected.MarkerHits;SelectionStrategy=$strategy;CandidateCount=$candidates.Count
    }
}

function Invoke-GateQuantumTransform([string]$Text){
    $newField=Get-Count $Text $script:FieldMarkerV872
    $newYield=Get-Count $Text $script:YieldMarkerV872
    $prevField=Get-Count $Text $script:PrevFieldMarkerV871
    $prevYield=Get-Count $Text $script:PrevYieldMarkerV871
    $oldField=Get-Count $Text $script:OldFieldMarkerV87
    $oldYield=Get-Count $Text $script:OldYieldMarkerV87
    if(($newField -gt 0) -xor ($newYield -gt 0)){throw "$script:Tag estado V87.2 parcial detectado (field=$newField yield=$newYield)."}
    if(($prevField -gt 0) -xor ($prevYield -gt 0)){throw "$script:Tag estado V87.1 parcial detectado (field=$prevField yield=$prevYield)."}
    if(($oldField -gt 0) -xor ($oldYield -gt 0)){throw "$script:Tag estado V87 antigo parcial detectado (field=$oldField yield=$oldYield)."}
    if($newField -gt 0 -and $newYield -gt 0){
        $gate=Get-SingleGateOwnerCandidate $Text $false
        return [pscustomobject]@{Text=$Text;Gate=$gate;AlreadyApplied=$true;LegacyV87=$false;LegacyV871=$false}
    }
    if($prevField -gt 0 -and $prevYield -gt 0){
        $gate=Get-SingleGateOwnerCandidate $Text $false
        return [pscustomobject]@{Text=$Text;Gate=$gate;AlreadyApplied=$true;LegacyV87=$false;LegacyV871=$true}
    }
    if($oldField -gt 0 -and $oldYield -gt 0){
        $gate=Get-SingleGateOwnerCandidate $Text $false
        return [pscustomobject]@{Text=$Text;Gate=$gate;AlreadyApplied=$true;LegacyV87=$true;LegacyV871=$false}
    }

    $gate=Get-SingleGateOwnerCandidate $Text $false
    $nl=if($Text.Contains("`r`n")){"`r`n"}else{"`n"}
    $fields=@'
    // SHARPEMU_V74_0_87_2_COOPERATIVE_GATE_QUANTUM
    // V86.4 proved resident retention is not the dominant limiter. V71/V72 show
    // long starvation on gpuState.Gate. Bound ownership to short packet quanta
    // and hand the monitor to queued waiter/submit threads only after the V72
    // complete-packet drain hook. Environment 0/0 restores legacy ownership.
    private static readonly int _gateQuantumPacketsV740872 =
        int.TryParse(Environment.GetEnvironmentVariable("SHARPEMU_AGC_GATE_QUANTUM_PACKETS"), out var gateQuantumPacketsV740872) && gateQuantumPacketsV740872 >= 0
            ? gateQuantumPacketsV740872
            : 16;
    private static readonly long _gateQuantumTicksV740872 =
        (long.TryParse(Environment.GetEnvironmentVariable("SHARPEMU_AGC_GATE_QUANTUM_MS"), out var gateQuantumMsV740872) && gateQuantumMsV740872 >= 0
            ? gateQuantumMsV740872
            : 1L) * System.Diagnostics.Stopwatch.Frequency / 1000L;
    [ThreadStatic] private static int _gateQuantumPacketCountV740872;
    [ThreadStatic] private static long _gateQuantumStartTicksV740872;
    private static long _gateQuantumYieldTraceCountV740872;

'@
    $fields=Normalize-Nl $fields $nl
    $work=$Text.Insert($gate.Start,$fields)

    # Re-locate after class-scope field insertion because absolute indices moved.
    $gate=Get-SingleGateOwnerCandidate $work $false
    $sp=$gate.StateParam
    $yield=@'

        // SHARPEMU_V74_0_87_2_GATE_QUANTUM_YIELD
        // V72 is invoked at a complete PM4 packet boundary. Do not release the
        // monitor inside a packet or ordered side effect; always re-enter in finally.
        if ((_gateQuantumPacketsV740872 > 0 || _gateQuantumTicksV740872 > 0) &&
            System.Threading.Monitor.IsEntered(__STATE__.Gate))
        {
            var gateQuantumNowV740872 = System.Diagnostics.Stopwatch.GetTimestamp();
            if (_gateQuantumStartTicksV740872 == 0)
            {
                _gateQuantumStartTicksV740872 = gateQuantumNowV740872;
            }
            var gateQuantumPacketsSeenV740872 = ++_gateQuantumPacketCountV740872;
            var gateQuantumElapsedV740872 = gateQuantumNowV740872 - _gateQuantumStartTicksV740872;
            var gateQuantumDueV740872 =
                (_gateQuantumPacketsV740872 > 0 && gateQuantumPacketsSeenV740872 >= _gateQuantumPacketsV740872) ||
                (_gateQuantumTicksV740872 > 0 && gateQuantumElapsedV740872 >= _gateQuantumTicksV740872);
            if (gateQuantumDueV740872)
            {
                _gateQuantumPacketCountV740872 = 0;
                _gateQuantumStartTicksV740872 = 0;
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

                var gateQuantumYieldV740872 = System.Threading.Interlocked.Increment(
                    ref _gateQuantumYieldTraceCountV740872);
                if (gateQuantumYieldV740872 <= 256 ||
                    (gateQuantumYieldV740872 & (gateQuantumYieldV740872 - 1)) == 0)
                {
                    var gateQuantumUsV740872 = gateQuantumElapsedV740872 * 1000000.0 /
                        System.Diagnostics.Stopwatch.Frequency;
                    Console.Error.WriteLine(
                        $"[V74.0.87.2][GATE_QUANTUM_YIELD] count={gateQuantumYieldV740872} " +
                        $"packets={gateQuantumPacketsSeenV740872} elapsed_us={gateQuantumUsV740872:F1}");
                }
            }
        }
'@
    $yield=(Normalize-Nl $yield $nl).Replace('__STATE__',$sp)
    $work=$work.Insert($gate.Close,$yield)

    if((Get-Count $work $script:FieldMarkerV872) -ne 1){throw "$script:Tag V87.2 field marker count invalido apos dry-run."}
    if((Get-Count $work $script:YieldMarkerV872) -ne 1){throw "$script:Tag V87.2 yield marker count invalido apos dry-run."}
    $after=Get-SingleGateOwnerCandidate $work $false
    if($after.Name -ne $gate.Name -or $after.StateParam -ne $sp){throw "$script:Tag V72 method identity mudou apos transformacao."}
    return [pscustomobject]@{Text=$work;Gate=$after;AlreadyApplied=$false;LegacyV87=$false;LegacyV871=$false}
}

function Invoke-StructuralLocatorSelfTest{
    # Reproduces the exact current-checkout ambiguity discovered by V87.1:
    # four marker occurrences and TWO SubmittedGpuState method candidates.
    # The classifier must prefer the dedicated V72 gate-owner drain helper and
    # must never instrument the broad ParseSubmittedDcbCore method.
    $fixture=@'
namespace Probe;
public static class AgcExports
{
    private const string MarkerOutsideMethod = "GATE_OWNER_WAIT_DRAIN";

    private static void ParseSubmittedDcbCore(
        CpuContext ctx,
        SubmittedGpuState gpuState,
        SubmittedDcbState state)
    {
        var fake = $"parser {{literal}}";
        Console.Error.WriteLine("[V74.0.72][GATE_OWNER_WAIT_DRAIN] parser-call-site");
    }

    private static int TryDrainPendingWaitersOnGateOwnerV74072(
        CpuContext ctx,
        SubmittedGpuState gpuState,
        SubmittedDcbState state,
        ulong commandAddress,
        int dw)
    {
        var fake = @"{verbatim not code}";
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
    $all=@(Get-GateOwnerCandidates $fixture)
    if($all.Count -ne 2){throw "$script:Tag SELFTEST expected 2 raw candidates, got $($all.Count)."}
    $gate=Get-SingleGateOwnerCandidate $fixture $false
    if($gate.Name -ne 'TryDrainPendingWaitersOnGateOwnerV74072' -or $gate.StateParam -ne 'gpuState'){
        throw "$script:Tag SELFTEST dedicated-drain classifier selected wrong method/state: $($gate.Name)/$($gate.StateParam)."
    }
    if($gate.SelectionStrategy -ne 'exact-dedicated-v72-helper'){
        throw "$script:Tag SELFTEST selection strategy drifted: $($gate.SelectionStrategy)."
    }
    $x=Invoke-GateQuantumTransform $fixture
    if($x.AlreadyApplied){throw "$script:Tag SELFTEST first transform unexpectedly idempotent."}
    if((Get-Count $x.Text $script:FieldMarkerV872) -ne 1 -or (Get-Count $x.Text $script:YieldMarkerV872) -ne 1){throw "$script:Tag SELFTEST transform markers invalid."}
    $x2=Invoke-GateQuantumTransform $x.Text
    if(-not $x2.AlreadyApplied -or $x2.Text -ne $x.Text){throw "$script:Tag SELFTEST idempotence failed."}
    Write-Host "$script:Tag STRUCTURAL LOCATOR SELFTEST PASSED (4 markers -> 2 raw candidates -> dedicated V72 helper selected; transform+idempotence)." -ForegroundColor Green
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
        if((Get-Count $dry.Text $script:FieldMarkerV872) -ne 1 -or (Get-Count $dry.Text $script:YieldMarkerV872) -ne 1){throw "$script:Tag dry-run output marker validation failed."}
    }
    if($gate.Name -ne 'TryDrainPendingWaitersOnGateOwnerV74072'){throw "$script:Tag CURRENT CHECKOUT dry-run selected unexpected method: $($gate.Name)."}
    Write-Host "$script:Tag CURRENT CHECKOUT STRUCTURAL DRY-RUN PASSED (read-only). Method=$($gate.Name) StateParam=$($gate.StateParam) Strategy=$($gate.SelectionStrategy) Candidates=$($gate.CandidateCount) SHA256=$shaBefore" -ForegroundColor Green
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
        V872Field=(Get-Count $a $script:FieldMarkerV872)
        V872Yield=(Get-Count $a $script:YieldMarkerV872)
        PrevV871Field=(Get-Count $a $script:PrevFieldMarkerV871)
        PrevV871Yield=(Get-Count $a $script:PrevYieldMarkerV871)
        OldV87Field=(Get-Count $a $script:OldFieldMarkerV87)
        OldV87Yield=(Get-Count $a $script:OldYieldMarkerV87)
    }
    foreach($e in $checks.GetEnumerator()){Write-Host "$script:Tag $($e.Key)=$($e.Value)"}
    if($checks.V812 -lt 1 -or $checks.V82 -lt 1 -or $checks.V84 -lt 1 -or $checks.V85 -lt 1){throw "$script:Tag base V81.2/V82/V84/V85 incompleta."}
    if($checks.V864Agc -lt 1 -or $checks.V864Presenter -lt 1){throw "$script:Tag V86.4 nao detectada nos dois sources."}
    if(($checks.V872Field -gt 0) -xor ($checks.V872Yield -gt 0)){throw "$script:Tag V87.2 parcial no source."}
    if(($checks.PrevV871Field -gt 0) -xor ($checks.PrevV871Yield -gt 0)){throw "$script:Tag V87.1 parcial no source."}
    if(($checks.OldV87Field -gt 0) -xor ($checks.OldV87Yield -gt 0)){throw "$script:Tag V87 antigo parcial no source."}
    return [pscustomobject]@{Agc=$a;Presenter=$p;Gate=$gate;Checks=$checks}
}

function New-Backup{
    if(-not(Test-Path -LiteralPath $script:BackupRoot)){New-Item -ItemType Directory -Path $script:BackupRoot|Out-Null}
    $dir=Join-Path $script:BackupRoot ("CooperativeGateQuantumV740872_"+(Get-Date -Format 'yyyyMMdd_HHmmss'))
    New-Item -ItemType Directory -Path $dir|Out-Null
    Copy-Item -LiteralPath $script:AgcPath -Destination (Join-Path $dir 'AgcExports.cs') -Force
    Write-Utf8NoBom $script:StateFile $dir
    return $dir
}
function Restore-Backup([string]$Dir){$x=Join-Path $Dir 'AgcExports.cs';if(-not(Test-Path -LiteralPath $x -PathType Leaf)){throw "$script:Tag backup AgcExports ausente: $x"};Copy-Item -LiteralPath $x -Destination $script:AgcPath -Force}
function Find-SharpEmuExe{$c=@((Join-Path $script:RepoRoot 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'),(Join-Path $script:RepoRoot 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.CLI.exe'));foreach($x in $c){if(Test-Path -LiteralPath $x -PathType Leaf){return $x}};return $null}
