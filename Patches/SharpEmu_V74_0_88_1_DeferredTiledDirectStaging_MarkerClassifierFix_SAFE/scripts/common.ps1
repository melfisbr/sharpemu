param([Parameter(Mandatory=$true)][string]$PackageRoot)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$script:Tag='[V74.0.88.1]'
$PackageRoot=$PackageRoot.Trim().Trim([char]34).Trim([char]39)
$script:PackageRoot=(Resolve-Path -LiteralPath $PackageRoot).Path.TrimEnd('\')
$script:PatchesRoot=Split-Path -Parent $script:PackageRoot
$script:RepoRoot=Split-Path -Parent $script:PatchesRoot
$script:PatchRoot=Join-Path $script:PackageRoot 'patch'
$script:BackupRoot=Join-Path $script:RepoRoot '.sharpemu-hotfix-backup'
$script:StateFile=Join-Path $script:PackageRoot 'LAST_BACKUP_V88_1.txt'
$script:GuestRel='src\SharpEmu.Libs\Gpu\GuestGpuTypes.cs'
$script:AgcRel='src\SharpEmu.Libs\Agc\AgcExports.cs'
$script:DetileRel='src\SharpEmu.Libs\VideoOut\VulkanDetilePass.cs'
$script:PresenterRel='src\SharpEmu.Libs\VideoOut\VulkanVideoPresenter.cs'
$script:GuestPath=Join-Path $script:RepoRoot $script:GuestRel
$script:AgcPath=Join-Path $script:RepoRoot $script:AgcRel
$script:DetilePath=Join-Path $script:RepoRoot $script:DetileRel
$script:PresenterPath=Join-Path $script:RepoRoot $script:PresenterRel
$script:GuestPatches=@('guest_01')
$script:AgcPatches=@('agc_01','agc_02','agc_03')
$script:DetilePatches=@('detile_01','detile_02')
$script:PresenterPatches=@('presenter_01','presenter_02','presenter_03','presenter_04','presenter_05')

function Read-Utf8([string]$Path){return [System.IO.File]::ReadAllText($Path,[System.Text.Encoding]::UTF8)}
function Write-Utf8NoBom([string]$Path,[string]$Text){$enc=New-Object System.Text.UTF8Encoding($false);[System.IO.File]::WriteAllText($Path,$Text,$enc)}
function Get-Sha256([string]$Path){return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()}
function Get-Count([string]$Text,[string]$Pattern){return ([regex]::Matches($Text,$Pattern,[System.Text.RegularExpressions.RegexOptions]::Multiline)).Count}
function Get-ExactCommentMarkerCount([string]$Text,[string]$Marker){
    $pattern='(?m)^\s*//\s*'+[regex]::Escape($Marker)+'\s*$'
    return ([regex]::Matches($Text,$pattern)).Count
}
function To-Lf([string]$Text){return $Text.Replace("`r`n","`n").Replace("`r","`n")}
function Restore-Nl([string]$Original,[string]$Lf){if($Original.Contains("`r`n")){return $Lf.Replace("`n","`r`n")};return $Lf}
function Read-Patch([string]$Name,[string]$Kind){return To-Lf (Read-Utf8 (Join-Path $script:PatchRoot ($Name+'.'+$Kind+'.txt')))}

function Apply-UniquePatch([string]$Lf,[string]$Name){
    $old=Read-Patch $Name 'old'
    $new=Read-Patch $Name 'new'
    $count=([regex]::Matches($Lf,[regex]::Escape($old))).Count
    if($count -ne 1){throw "$script:Tag patch '$Name' anchor count=$count (expected 1). Source diverged; no write performed."}
    $idx=$Lf.IndexOf($old,[System.StringComparison]::Ordinal)
    if($idx -lt 0){throw "$script:Tag patch '$Name' anchor not found."}
    return $Lf.Substring(0,$idx)+$new+$Lf.Substring($idx+$old.Length)
}

function Assert-V88MarkerState([string]$Text,[string]$Kind){
    if($Kind -eq 'guest'){
        $m=Get-ExactCommentMarkerCount $Text 'SHARPEMU_V74_0_88_DEFERRED_TILED_GUEST_SOURCE'
        if($m -eq 0){return 'Ready'};if($m -eq 1){return 'Applied'};throw "$script:Tag guest V88 marker count=$m"
    }
    if($Kind -eq 'agc'){
        $a=Get-ExactCommentMarkerCount $Text 'SHARPEMU_V74_0_88_DEFER_LARGE_TILED_GUEST_READ'
        $b=Get-ExactCommentMarkerCount $Text 'SHARPEMU_V74_0_88_DEFERRED_TILED_ARRAY'
        $c=Get-ExactCommentMarkerCount $Text 'SHARPEMU_V74_0_88_DEFERRED_TILED_SINGLE'
        if($a -eq 0 -and $b -eq 0 -and $c -eq 0){return 'Ready'}
        if($a -eq 1 -and $b -eq 1 -and $c -eq 1){return 'Applied'}
        throw "$script:Tag AGC V88 partial state fields=$a array=$b single=$c"
    }
    if($Kind -eq 'detile'){
        $a=Get-ExactCommentMarkerCount $Text 'SHARPEMU_V74_0_88_DIRECT_GUEST_DETILE_STAGING'
        $b=Get-ExactCommentMarkerCount $Text 'SHARPEMU_V74_0_88_DIRECT_GUEST_STAGING_PREPARE'
        if($a -eq 0 -and $b -eq 0){return 'Ready'}
        if($a -eq 1 -and $b -eq 1){return 'Applied'}
        throw "$script:Tag Detile V88 partial state method=$a prepare=$b"
    }
    if($Kind -eq 'presenter'){
        $a=Get-ExactCommentMarkerCount $Text 'SHARPEMU_V74_0_88_DIRECT_GUEST_STAGING_TRACE'
        $b=Get-ExactCommentMarkerCount $Text 'SHARPEMU_V74_0_88_DEFERRED_TILED_HELPERS'
        $c=Get-ExactCommentMarkerCount $Text 'SHARPEMU_V74_0_88_DIRECT_GUEST_STAGING'
        if($a -eq 0 -and $b -eq 0 -and $c -eq 0){return 'Ready'}
        if($a -eq 1 -and $b -eq 1 -and $c -eq 1){return 'Applied'}
        throw "$script:Tag Presenter V88 partial state trace=$a helpers=$b direct=$c"
    }
    throw "$script:Tag unknown marker state kind=$Kind"
}

function Invoke-V88MarkerClassifierSelfTest{
    $fixture=@'
    // SHARPEMU_V74_0_88_DIRECT_GUEST_STAGING_TRACE
    // SHARPEMU_V74_0_88_DEFERRED_TILED_HELPERS
    // SHARPEMU_V74_0_88_DIRECT_GUEST_STAGING
'@
    $broad=Get-Count $fixture 'SHARPEMU_V74_0_88_DIRECT_GUEST_STAGING'
    $trace=Get-ExactCommentMarkerCount $fixture 'SHARPEMU_V74_0_88_DIRECT_GUEST_STAGING_TRACE'
    $helpers=Get-ExactCommentMarkerCount $fixture 'SHARPEMU_V74_0_88_DEFERRED_TILED_HELPERS'
    $direct=Get-ExactCommentMarkerCount $fixture 'SHARPEMU_V74_0_88_DIRECT_GUEST_STAGING'
    if($broad -ne 2 -or $trace -ne 1 -or $helpers -ne 1 -or $direct -ne 1){
        throw "$script:Tag V88 marker classifier regression failed broad=$broad trace=$trace helpers=$helpers direct=$direct"
    }
    if((Assert-V88MarkerState $fixture 'presenter') -ne 'Applied'){
        throw "$script:Tag V88 marker classifier failed to recognize Applied presenter fixture"
    }
    if((Assert-V88MarkerState '// baseline without V88 marker' 'presenter') -ne 'Ready'){
        throw "$script:Tag V88 marker classifier failed to recognize Ready presenter fixture"
    }
    Write-Host "$script:Tag MARKER CLASSIFIER SELFTEST PASSED (prefix collision broad=2; exact trace=1 helpers=1 direct=1)." -ForegroundColor Green
}

function Invoke-PatchListTransform([string]$Text,[string[]]$Patches,[string]$Kind){
    $state=Assert-V88MarkerState $Text $Kind
    if($state -eq 'Applied'){return [pscustomobject]@{Text=$Text;AlreadyApplied=$true;Kind=$Kind}}
    $lf=To-Lf $Text
    foreach($name in $Patches){$lf=Apply-UniquePatch $lf $name}
    $result=Restore-Nl $Text $lf
    $post=Assert-V88MarkerState $result $Kind
    if($post -ne 'Applied'){throw "$script:Tag transform $Kind did not reach Applied state."}
    return [pscustomobject]@{Text=$result;AlreadyApplied=$false;Kind=$Kind}
}
function Transform-Guest([string]$Text){return Invoke-PatchListTransform $Text $script:GuestPatches 'guest'}
function Transform-Agc([string]$Text){return Invoke-PatchListTransform $Text $script:AgcPatches 'agc'}
function Transform-Detile([string]$Text){return Invoke-PatchListTransform $Text $script:DetilePatches 'detile'}
function Transform-Presenter([string]$Text){return Invoke-PatchListTransform $Text $script:PresenterPatches 'presenter'}

# Lexical C# curly-brace validator. It intentionally ignores braces in line/block
# comments, char literals, ordinary strings, verbatim strings and raw strings.
function Assert-CSharpBraceBalance([string]$Text,[string]$Label){
    $depth=0;$state=0;$rawQuotes=0;$i=0
    while($i -lt $Text.Length){
        $ch=$Text[$i];$next=if($i+1 -lt $Text.Length){$Text[$i+1]}else{[char]0}
        if($state -eq 1){if($ch -eq "`n" -or $ch -eq "`r"){$state=0};$i++;continue}
        if($state -eq 2){if($ch -eq '*' -and $next -eq '/'){$state=0;$i+=2;continue};$i++;continue}
        if($state -eq 3){if($ch -eq [char]92){$i+=2;continue};if($ch -eq [char]34){$state=0};$i++;continue}
        if($state -eq 4){if($ch -eq [char]34){if($next -eq [char]34){$i+=2;continue};$state=0};$i++;continue}
        if($state -eq 5){if($ch -eq [char]92){$i+=2;continue};if($ch -eq [char]39){$state=0};$i++;continue}
        if($state -eq 6){if($ch -eq [char]34){$run=1;while($i+$run -lt $Text.Length -and $Text[$i+$run] -eq [char]34){$run++};if($run -ge $rawQuotes){$state=0;$i+=$run;continue}};$i++;continue}
        if($ch -eq '/' -and $next -eq '/'){$state=1;$i+=2;continue}
        if($ch -eq '/' -and $next -eq '*'){$state=2;$i+=2;continue}
        if($ch -eq [char]39){$state=5;$i++;continue}
        if($ch -eq [char]34){
            $run=1;while($i+$run -lt $Text.Length -and $Text[$i+$run] -eq [char]34){$run++}
            if($run -ge 3){$state=6;$rawQuotes=$run;$i+=$run;continue}
            $isVerbatim=($i -gt 0 -and $Text[$i-1] -eq '@') -or ($i -gt 1 -and $Text[$i-2] -eq '@' -and $Text[$i-1] -eq '$')
            $state=if($isVerbatim){4}else{3};$i++;continue
        }
        if($ch -eq '{'){$depth++}elseif($ch -eq '}'){$depth--;if($depth -lt 0){throw "$script:Tag C# brace underflow in $Label at char=$i"}}
        $i++
    }
    if($depth -ne 0){throw "$script:Tag C# brace imbalance in $Label depth=$depth"}
}

function Assert-Repo{
    foreach($p in @($script:GuestPath,$script:AgcPath,$script:DetilePath,$script:PresenterPath)){if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw "$script:Tag source missing: $p"}}
}

function Get-SourceBundle{
    Assert-Repo
    return [pscustomobject]@{
        Guest=Read-Utf8 $script:GuestPath
        Agc=Read-Utf8 $script:AgcPath
        Detile=Read-Utf8 $script:DetilePath
        Presenter=Read-Utf8 $script:PresenterPath
    }
}

function Assert-CumulativeBase([object]$S){
    $checks=[ordered]@{
        V812=(Get-Count $S.Presenter 'SHARPEMU_V74_0_81_2_SEMANTIC_BOUNDARY_REPAIR')
        V82=(Get-Count $S.Presenter 'SHARPEMU_V74_0_82_NONBLOCKING_VISIBILITY_DCC_INDEX')
        V84=(Get-Count $S.Presenter 'SHARPEMU_V74_0_84_SUBMISSION_HEADROOM_ADAPTIVE')
        V85=(Get-Count $S.Agc 'SHARPEMU_V74_0_85_AGGRESSIVE_PM4_LOCAL_PAYLOAD_RELEASE_QUEUE')
        V864Agc=(Get-Count $S.Agc 'SHARPEMU_V74_0_86_4_RESIDENT_TEXTURE_RETENTION_SEMICOLON_ANCHOR')
        V864Presenter=(Get-Count $S.Presenter 'SHARPEMU_V74_0_86_4_RESIDENT_TEXTURE_RETENTION_SEMICOLON_ANCHOR')
        V872Field=(Get-Count $S.Agc 'SHARPEMU_V74_0_87_2_COOPERATIVE_GATE_QUANTUM')
        V872Yield=(Get-Count $S.Agc 'SHARPEMU_V74_0_87_2_GATE_QUANTUM_YIELD')
    }
    foreach($e in $checks.GetEnumerator()){Write-Host "$script:Tag $($e.Key)=$($e.Value)"}
    foreach($k in @('V812','V82','V84','V85','V864Agc','V864Presenter','V872Field','V872Yield')){if($checks[$k] -lt 1){throw "$script:Tag cumulative base missing $k"}}
    return $checks
}

function Invoke-CheckoutDryRun([bool]$Print=$true){
    $s=Get-SourceBundle
    $checks=Assert-CumulativeBase $s
    $states=[ordered]@{
        Guest=Assert-V88MarkerState $s.Guest 'guest'
        Agc=Assert-V88MarkerState $s.Agc 'agc'
        Detile=Assert-V88MarkerState $s.Detile 'detile'
        Presenter=Assert-V88MarkerState $s.Presenter 'presenter'
    }
    foreach($e in $states.GetEnumerator()){Write-Host "$script:Tag V88$($e.Key)State=$($e.Value)"}
    $ready=@($states.Values | Where-Object {$_ -eq 'Ready'}).Count
    $applied=@($states.Values | Where-Object {$_ -eq 'Applied'}).Count
    if($ready -ne 0 -and $applied -ne 0){throw "$script:Tag V88 partial cross-file state Ready=$ready Applied=$applied"}
    if($applied -eq 4){
        if($Print){Write-Host "$script:Tag CURRENT CHECKOUT DRY-RUN: AlreadyApplied on all 4 files." -ForegroundColor Yellow}
        return [pscustomobject]@{State='Applied';Source=$s;Checks=$checks;Transformed=$s}
    }
    $tg=Transform-Guest $s.Guest;$ta=Transform-Agc $s.Agc;$td=Transform-Detile $s.Detile;$tp=Transform-Presenter $s.Presenter
    # Idempotence: every second transform must be byte-identical.
    if((Transform-Guest $tg.Text).Text -cne $tg.Text){throw "$script:Tag guest transform idempotence failed"}
    if((Transform-Agc $ta.Text).Text -cne $ta.Text){throw "$script:Tag AGC transform idempotence failed"}
    if((Transform-Detile $td.Text).Text -cne $td.Text){throw "$script:Tag Detile transform idempotence failed"}
    if((Transform-Presenter $tp.Text).Text -cne $tp.Text){throw "$script:Tag Presenter transform idempotence failed"}
    Assert-CSharpBraceBalance $tg.Text 'GuestGpuTypes.cs transformed'
    Assert-CSharpBraceBalance $ta.Text 'AgcExports.cs transformed'
    Assert-CSharpBraceBalance $td.Text 'VulkanDetilePass.cs transformed'
    Assert-CSharpBraceBalance $tp.Text 'VulkanVideoPresenter.cs transformed'
    if((Get-Count $tg.Text 'DeferredTiledGuestRead = false') -ne 1){throw "$script:Tag GuestDrawTexture deferred field contract missing"}
    if((Get-Count $ta.Text 'DeferredTiledGuestRead: true') -ne 2){throw "$script:Tag AGC must create exactly two deferred texture forms (array + single)"}
    if((Get-Count $td.Text 'public bool RecordDetileGuestMemory\s*\(') -ne 1){throw "$script:Tag direct detile method definition count mismatch"}
    if((Get-Count $tp.Text 'RecordDetileGuestMemory\s*\(') -ne 1){throw "$script:Tag presenter direct detile call count mismatch"}
    if((Get-Count $ta.Text 'SHARPEMU_DEFER_LARGE_TILED_GUEST_READ') -ne 1){throw "$script:Tag V88 env rollback switch count mismatch"}
    if($Print){
        Write-Host "$script:Tag CURRENT CHECKOUT STRUCTURAL DRY-RUN PASSED (4 files, read-only, idempotent, lexical braces balanced)." -ForegroundColor Green
        Write-Host "$script:Tag V88Plan=AGC guest-reference -> Vulkan mapped staging; threshold_default_mb=8; env_0_restores_legacy"
        Write-Host "$script:Tag V88Contracts=GuestDrawTexture+Agc(array,single)+Presenter+VulkanDetilePass"
    }
    $t=[pscustomobject]@{Guest=$tg.Text;Agc=$ta.Text;Detile=$td.Text;Presenter=$tp.Text}
    return [pscustomobject]@{State='Ready';Source=$s;Checks=$checks;Transformed=$t}
}

function Invoke-PatchDataSelfTest{
    Invoke-V88MarkerClassifierSelfTest
    $all=@($script:GuestPatches+$script:AgcPatches+$script:DetilePatches+$script:PresenterPatches)
    foreach($name in $all){
        $old=Read-Patch $name 'old';$new=Read-Patch $name 'new'
        if([string]::IsNullOrEmpty($old) -or [string]::IsNullOrEmpty($new) -or $old -ceq $new){throw "$script:Tag invalid patch data $name"}
        $fixture='PRE'+"`n"+$old+'POST'+"`n"
        if(([regex]::Matches($fixture,[regex]::Escape($old))).Count -ne 1){throw "$script:Tag patch fixture uniqueness failed $name"}
        $idx=$fixture.IndexOf($old,[System.StringComparison]::Ordinal)
        $changed=$fixture.Substring(0,$idx)+$new+$fixture.Substring($idx+$old.Length)
        if(-not $changed.Contains($new)){throw "$script:Tag patch fixture replace failed $name"}
    }
    Write-Host "$script:Tag PATCH DATA SELFTEST PASSED ($($all.Count) structural hunks)." -ForegroundColor Green
}

function New-Backup{
    if(-not(Test-Path -LiteralPath $script:BackupRoot)){New-Item -ItemType Directory -Path $script:BackupRoot|Out-Null}
    $dir=Join-Path $script:BackupRoot ("DeferredTiledDirectStagingV740881_"+(Get-Date -Format 'yyyyMMdd_HHmmss'))
    New-Item -ItemType Directory -Path $dir|Out-Null
    Copy-Item -LiteralPath $script:GuestPath -Destination (Join-Path $dir 'GuestGpuTypes.cs') -Force
    Copy-Item -LiteralPath $script:AgcPath -Destination (Join-Path $dir 'AgcExports.cs') -Force
    Copy-Item -LiteralPath $script:DetilePath -Destination (Join-Path $dir 'VulkanDetilePass.cs') -Force
    Copy-Item -LiteralPath $script:PresenterPath -Destination (Join-Path $dir 'VulkanVideoPresenter.cs') -Force
    Write-Utf8NoBom $script:StateFile $dir
    return $dir
}
function Restore-Backup([string]$Dir){
    $map=@{'GuestGpuTypes.cs'=$script:GuestPath;'AgcExports.cs'=$script:AgcPath;'VulkanDetilePass.cs'=$script:DetilePath;'VulkanVideoPresenter.cs'=$script:PresenterPath}
    foreach($name in $map.Keys){$src=Join-Path $Dir $name;if(-not(Test-Path -LiteralPath $src -PathType Leaf)){throw "$script:Tag backup missing $src"};Copy-Item -LiteralPath $src -Destination $map[$name] -Force}
}
function Find-SharpEmuExe{$c=@((Join-Path $script:RepoRoot 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'),(Join-Path $script:RepoRoot 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.CLI.exe'));foreach($x in $c){if(Test-Path -LiteralPath $x -PathType Leaf){return $x}};return $null}
