param()
. (Join-Path $PSScriptRoot 'common.ps1')

$expected = @(
    'README_PT-BR.txt',
    'PARAMETER_CONTRACT.txt',
    'ARCHITECTURE_MERGE.txt',
    'RUN_1_VALIDATE_PACKAGE.cmd',
    'RUN_2_PRECHECK.cmd',
    'RUN_3_APPLY_BUILD.cmd',
    'RUN_4_DIAGNOSTIC.cmd',
    'RUN_5_ROLLBACK_LAST.cmd',
    'scripts\common.ps1',
    'scripts\validate.ps1',
    'scripts\precheck.ps1',
    'scripts\apply_build.ps1',
    'scripts\diagnostic.ps1',
    'scripts\rollback.ps1',
    'MANIFEST.sha256'
)

foreach ($r in $expected) {
    $p = Join-Path $PackageRoot $r
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        Fail "payload ausente: $r"
    }
}

$badPatterns = @(
    ('Invoke-' + 'WebRequest'),
    ('Start-' + 'BitsTransfer'),
    ('curl' + '.exe'),
    ('wget' + '.exe')
)

foreach ($f in Get-ChildItem -LiteralPath $PackageRoot -Recurse -File -Include *.ps1,*.cmd) {
    $txt = [IO.File]::ReadAllText($f.FullName)
    foreach ($bad in $badPatterns) {
        if ($txt.Contains($bad)) {
            Fail "downloader direto proibido: $($f.Name):$bad"
        }
    }

    if ($txt -match '(?im)^\s*\$Host\s*=') {
        Fail "read-only automatic variable assignment: $($f.Name):`$Host"
    }
}

$apply = [IO.File]::ReadAllText((Join-Path $PackageRoot 'scripts\apply_build.ps1'))
foreach ($m in @(
    'V76.3.21.4_AGC_PUBLISH_FAIRNESS_BEGIN',
    'NoteAgcBuilderV763214',
    'NoteAgcDriverSubmitV763214',
    'residuo V21.4 permaneceu apos rollback',
    '$preYieldCount',
    '$v214BlockYieldCount',
    '$expectedPostYieldCount',
    'Thread.Yield conservation falhou',
    '-t:Rebuild',
    '-c Debug',
    'BACKUP PASSED'
)) {
    if (-not $apply.Contains($m)) {
        Fail "apply rollback contract ausente: $m"
    }
}

$diag = [IO.File]::ReadAllText((Join-Path $PackageRoot 'scripts\diagnostic.ps1'))
foreach ($m in @(
    "SHARPEMU_V763214_DISABLE='1'",
    "SHARPEMU_TRACE_GEOMETRY_DRAWS='0'",
    'process_left_running=',
    'passed_v214_regression_threshold=',
    'gpu_drained=',
    'SharpEmu foi deixado ABERTO intencionalmente'
)) {
    if (-not $diag.Contains($m)) {
        Fail "diagnostic contract ausente: $m"
    }
}

if ($diag -match 'if\s*\(\s*-not\s+\$p\.HasExited\s*\)\s*\{\s*Stop-Process') {
    Fail 'diagnostic nao pode forcar fechamento no fim da coleta'
}

$manifest = Get-Content -LiteralPath (Join-Path $PackageRoot 'MANIFEST.sha256') |
    Where-Object { $_.Trim() }

foreach ($line in $manifest) {
    if ($line -notmatch '^([0-9a-f]{64})  (.+)$') {
        Fail "manifest line invalida: $line"
    }
    $want = $matches[1]
    $rel = $matches[2]
    $p = Join-Path $PackageRoot $rel
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        Fail "manifest target ausente: $rel"
    }
    $got = Get-HashLower $p
    if ($got -ne $want) {
        Fail "hash mismatch: $rel"
    }
}

Write-Host "[$Tag] VALIDATE PASSED files=$($expected.Count) manifest=$($manifest.Count)"
