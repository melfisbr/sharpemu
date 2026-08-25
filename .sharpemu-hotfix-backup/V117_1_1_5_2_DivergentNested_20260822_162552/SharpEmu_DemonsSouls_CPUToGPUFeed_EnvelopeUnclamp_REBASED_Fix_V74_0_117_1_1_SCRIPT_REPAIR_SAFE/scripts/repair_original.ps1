param()
. (Join-Path $PSScriptRoot 'common.ps1')
Assert-OriginalLayout

$o=OriginalRoot
$patchScript=Join-Path $o 'scripts\patch_envelope.ps1'

# Discover the actual parameter contract of the original patcher.
$cmd=Get-Command -LiteralPath $patchScript
$paramNames=@($cmd.Parameters.Keys)
if($paramNames -notcontains 'Source'){throw "$script:Tag patch_envelope.ps1 has no -Source parameter"}
if($paramNames -notcontains 'Out'){throw "$script:Tag patch_envelope.ps1 has no -Out parameter"}

$targets=Get-ChildItem -LiteralPath (Join-Path $o 'scripts') -File -Filter '*.ps1' |
    Where-Object {
        (Get-Content -LiteralPath $_.FullName -Raw).Contains('patch_envelope.ps1')
    }

if(-not$targets){throw "$script:Tag no caller of patch_envelope.ps1 found"}

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$backup=Join-Path (PatchesRoot) "SharpEmu_V74_0_117_1_1_SCRIPT_BACKUP_$stamp"
New-Item -ItemType Directory -Path $backup -Force|Out-Null
$changed=0

foreach($f in $targets){
    $text=Get-Content -LiteralPath $f.FullName -Raw
    $original=$text

    # The V117.1 failure was produced by a one-line invocation where validation
    # words such as pending_items remained after the valid -Out argument.
    # Keep the command through "-Out $variable" and discard only the residual
    # positional tail on that same invocation line.
    $lines=$text -split "`r?`n",-1
    for($i=0;$i-lt$lines.Count;$i++){
        $line=$lines[$i]
        if($line -notmatch 'patch_envelope\.ps1'){continue}

        # Expected V117.1 shape: ... -Source $s -Out $o <bad positional tail>
        $m=[regex]::Match(
            $line,
            '^(?<head>.*patch_envelope\.ps1''\)\s+-Source\s+\$[A-Za-z_][A-Za-z0-9_]*\s+-Out\s+\$[A-Za-z_][A-Za-z0-9_]*)(?<tail>.*)$'
        )
        if(-not$m.Success){
            throw "$script:Tag unsupported patch_envelope invocation shape in $($f.Name): $line"
        }

        $tail=$m.Groups['tail'].Value
        if(-not[string]::IsNullOrWhiteSpace($tail)){
            Write-Tag "Removing positional tail from $($f.Name): $($tail.Trim())"
            $lines[$i]=$m.Groups['head'].Value
        }
    }

    $new=[string]::Join("`r`n",$lines)
    if($new-ne$original){
        $dest=Join-Path $backup $f.Name
        Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
        Set-Content -LiteralPath $f.FullName -Value $new -Encoding UTF8 -NoNewline
        $changed++
    }
}

# If the repair already happened in a previous run, idempotence is okay.
Parse-PowerShellTree $o

# Verify no caller still has known positional validation tokens after the
# patch_envelope invocation.
foreach($f in $targets){
    foreach($line in Get-Content -LiteralPath $f.FullName){
        if($line -match 'patch_envelope\.ps1' -and
           $line -match '\bpending_items\b|\bpending_mb\b|\bmax_inflight\b|\bemergency_inflight\b'){
            throw "$script:Tag residual positional envelope token remains in $($f.Name): $line"
        }
    }
}

$state=Join-Path (PatchesRoot) 'SharpEmu_V74_0_117_1_1_SCRIPT_REPAIR_STATE.txt'
@(
    "timestamp=$stamp",
    "original_root=$o",
    "backup=$backup",
    "changed_scripts=$changed",
    "patcher_parameters=$($paramNames -join ',')",
    'binding_fix=PASS'
)|Set-Content -LiteralPath $state -Encoding UTF8

Write-Tag "SCRIPT REPAIR PASSED changed_scripts=$changed backup=$backup"
