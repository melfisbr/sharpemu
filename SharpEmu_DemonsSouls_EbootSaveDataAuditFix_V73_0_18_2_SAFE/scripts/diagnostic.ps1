param(
    [Parameter(Mandatory=$true)][string]$RepoRoot,
    [string]$Eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$repo=[IO.Path]::GetFullPath($RepoRoot)
if(-not(Test-Path -LiteralPath $Eboot -PathType Leaf)){
    throw "EBOOT missing: $Eboot"
}
$eh=(Get-FileHash -LiteralPath $Eboot -Algorithm SHA256).Hash
if($eh -ne '22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E'){
    throw "EBOOT diferente do auditado: $eh"
}

$exe=$null
foreach($candidate in @(
    (Join-Path $repo 'artifacts\bin\Debug\net10.0\win-x64\SharpEmu.exe'),
    (Join-Path $repo 'artifacts\bin\Debug\net10.0\SharpEmu.exe')
)){
    if(Test-Path -LiteralPath $candidate -PathType Leaf){
        $exe=$candidate
        break
    }
}
if($null -eq $exe){throw 'SharpEmu.exe not found.'}

$stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$out=Join-Path $repo (
    "SharpEmu_V73_0_18_2_EBOOT_SAVEDATA_RESULT_$stamp"
)
New-Item -ItemType Directory -Force -Path $out | Out-Null
$stdout=Join-Path $out 'demons_stdout.log'
$stderr=Join-Path $out 'demons_stderr.log'

$vars=@(
    'SHARPEMU_LOG_SAVEDATA',
    'SHARPEMU_LOG_ALL_IMPORTS',
    'SHARPEMU_LOG_IMPORT_FILTER',
    'SHARPEMU_RENDER_CHECKPOINTS',
    'SHARPEMU_TRACE_SCANOUT_LINEAGE',
    'SHARPEMU_SCANOUT_RECOVERY'
)
$old=@{}
foreach($v in $vars){
    $old[$v]=[Environment]::GetEnvironmentVariable($v,'Process')
}

try{
    $env:SHARPEMU_LOG_SAVEDATA='1'
    $env:SHARPEMU_LOG_ALL_IMPORTS='1'
    $env:SHARPEMU_LOG_IMPORT_FILTER='SaveData'
    $env:SHARPEMU_RENDER_CHECKPOINTS='1'
    $env:SHARPEMU_TRACE_SCANOUT_LINEAGE='1'
    $env:SHARPEMU_SCANOUT_RECOVERY='off'

    Write-Host '[V73.0.18.2] Executando Demon''s Souls com SaveData auditado.' -ForegroundColor Cyan
    Write-Host '[V73.0.18.2] Deixe passar o segundo video e aguarde o ponto onde trava; depois feche a janela.'

    $p=Start-Process `
        -FilePath $exe `
        -ArgumentList @($Eboot) `
        -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr `
        -PassThru

    $p.WaitForExit()
    $p.WaitForExit()
    try{$exitCode=$p.ExitCode}catch{$exitCode='unavailable'}
}
finally{
    foreach($v in $vars){
        if($null -eq $old[$v]){
            Remove-Item ('Env:'+$v) -ErrorAction SilentlyContinue
        } else {
            [Environment]::SetEnvironmentVariable(
                $v,
                [string]$old[$v],
                'Process'
            )
        }
    }
}

$so=@()
$se=@()
if(Test-Path -LiteralPath $stdout){
    $so=@([IO.File]::ReadAllLines($stdout))
}
if(Test-Path -LiteralPath $stderr){
    $se=@([IO.File]::ReadAllLines($stderr))
}

function Match([string[]]$l,[string]$n){
    @($l | Where-Object {
        $_.IndexOf(
            $n,
            [StringComparison]::OrdinalIgnoreCase
        ) -ge 0
    })
}

$save=@(Match $se 'savedata.')
$backup=@(Match $se 'savedata.backup')
$prepare=@(Match $se 'savedata.prepare')
$mount=@(Match $se 'savedata.mount3')
$search=@(Match $se 'savedata.dirname_search')
$commit=@(Match $se 'savedata.commit')
$dialog=@(Match $se 'save_data_dialog.')
$wait=@(Match $se 'agc.wait_suspended')
$resume=@(Match $se 'wait_resumed')
$workTimeout=@(Match $se '[V73.0.17][WORK_TIMEOUT]')
$queueVis=@(Match $se '[V73.0.17][QUEUE_VISIBILITY]')
$indirectVis=@(Match $se '[V73.0.17][INDIRECT_ARGS_VISIBILITY]')
$flip=@(Match $se '[V16][CP4_FLIP]')
$guest=@(Match $se 'Vulkan VideoOut presented guest frame')
$scan=@(Match $se 'agc.scanout_lineage')
$unresolved=@(Match $se 'unresolved:')
$lost=@(Match $se 'deviceLost=True')
$gather=@(Match $so 'ResourcePool::GatherResourceFileInfo')

foreach($pair in @(
    @('SAVEDATA_TRACE.txt',$save),
    @('BACKUP.txt',$backup),
    @('PREPARE.txt',$prepare),
    @('MOUNT3.txt',$mount),
    @('DIRNAME_SEARCH.txt',$search),
    @('COMMIT.txt',$commit),
    @('DIALOG.txt',$dialog),
    @('WAIT_SUSPENDED.txt',$wait),
    @('WAIT_RESUMED.txt',$resume),
    @('WORK_TIMEOUT.txt',$workTimeout)
)){
    [IO.File]::WriteAllLines(
        (Join-Path $out $pair[0]),
        [string[]]$pair[1],
        [Text.UTF8Encoding]::new($false)
    )
}

$summary=@(
    'version=73.0.18.2',
    'eboot_sha256=22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E',
    "exit_code=$exitCode",
    "savedata_trace=$($save.Count)",
    "backup_calls=$($backup.Count)",
    "prepare_calls=$($prepare.Count)",
    "mount3_calls=$($mount.Count)",
    "dirname_search_calls=$($search.Count)",
    "commit_calls=$($commit.Count)",
    "dialog_lines=$($dialog.Count)",
    "gather_resource=$($gather.Count)",
    "wait_suspended=$($wait.Count)",
    "wait_resumed=$($resume.Count)",
    "v73017_work_timeout=$($workTimeout.Count)",
    "v73017_queue_visibility=$($queueVis.Count)",
    "v73017_indirect_args_visibility=$($indirectVis.Count)",
    "flip_checkpoints=$($flip.Count)",
    "guest_frames=$($guest.Count)",
    "scanout_lineage=$($scan.Count)",
    "runtime_unresolved=$($unresolved.Count)",
    "device_lost=$($lost.Count)"
)

[IO.File]::WriteAllLines(
    (Join-Path $out 'SUMMARY.txt'),
    $summary,
    [Text.UTF8Encoding]::new($false)
)

$zip=$out+'.zip'
Compress-Archive `
    -Path (Join-Path $out '*') `
    -DestinationPath $zip `
    -Force

Write-Host "[V73.0.18.2] RESULT: $zip" -ForegroundColor Green
Write-Host ($summary -join ' | ')
