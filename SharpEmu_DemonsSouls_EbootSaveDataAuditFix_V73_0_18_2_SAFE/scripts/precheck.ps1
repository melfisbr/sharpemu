param(
    [Parameter(Mandatory=$true)][string]$RepoRoot,
    [string]$Eboot='F:\JOGOSPS5\PPSA01341\eboot.bin'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$repo=[IO.Path]::GetFullPath($RepoRoot)
$base=$null
foreach($c in @([IO.Path]::Combine($repo,'src'),$repo)){
    $candidate=[IO.Path]::Combine(
        $c,
        'SharpEmu.Libs\SaveData\SaveDataExports.cs'
    )
    if([IO.File]::Exists($candidate)){
        $base=$c
        break
    }
}
if($null -eq $base){throw 'Source layout nao reconhecido.'}

$src=[IO.Path]::Combine(
    $base,
    'SharpEmu.Libs\SaveData\SaveDataExports.cs'
)
$h=(Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash
$t=[IO.File]::ReadAllText($src)

$alreadyPatched=
    $t.Contains('SHARPEMU_DEMONSSOULS_EBOOT_SAVEDATA_BLOCK_64K_V73_0_18') -and
    $t.Contains('Nid = "z1JA8-iJt3k"') -and
    $t.Contains('SHARPEMU_DEMONSSOULS_EBOOT_SAVEDATA_PREPARE_RSI_V73_0_18')

if($h -ne '9CC3F444B8375F582E1A8AD29F89A127FB0DF8358152915374C07E9911B13735' -and -not $alreadyPatched){
    # A newer accumulated source is acceptable only if all structural anchors
    # required for a non-destructive patch are still present.
    $anchors=@(
        'DefaultBlockSize',
        'public static int SaveDataPrepare(CpuContext ctx)',
        '// ---- params (metadata shown in the save UI) ----',
        'sceSaveDataCreateTransactionResource',
        'sceSaveDataMount3',
        'sceSaveDataCommit'
    )
    foreach($a in $anchors){
        if(-not $t.Contains($a)){
            throw "Baseline divergente e anchor ausente: $a hash=$h"
        }
    }

    Write-Host "[V73.0.18.2] Newer structural baseline accepted: $h" -ForegroundColor Yellow
} else {
    Write-Host "SaveDataExports hash reconhecido: $h"
}

if(-not(Test-Path -LiteralPath $Eboot -PathType Leaf)){
    throw "EBOOT ausente: $Eboot"
}
$eh=(Get-FileHash -LiteralPath $Eboot -Algorithm SHA256).Hash
if($eh -ne '22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E'){
    throw "EBOOT diferente do PPSA01341 auditado: $eh"
}

# Preserve known accumulated Demon's Souls transaction-resource fix.
if(-not $t.Contains('sceSaveDataCreateTransactionResource')){
    throw 'CreateTransactionResource ausente.'
}

Write-Host "Source layout: $base" -ForegroundColor Cyan
Write-Host "EBOOT SHA256 OK: $eh" -ForegroundColor Cyan
if($alreadyPatched){
    Write-Host '[V73.0.18.2] SaveData corrections ja presentes.' -ForegroundColor Yellow
}
Write-Host '[V73.0.18.2] PRECHECK PASSED.' -ForegroundColor Green
