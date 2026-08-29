param()
. (Join-Path $PSScriptRoot 'common.ps1')
Ensure-Repo

$tr=[IO.File]::ReadAllText($TranslatorPath)
$already=$tr.Contains('V76.3.19.0_SHADER_FRONTEND_SET_ASSOC_L2')

if(-not$already){
 foreach($m in @(
  'private const int V11710ThreadCacheSlots = 4096;',
  'private static bool TryGetProgramV11710(',
  'private static void PutProgramV11710(',
  'private static bool TryGetMetadataV11710(',
  'private static void PutMetadataV11710(',
  'V7636ProgramL2ConflictEvictions',
  'V7636MetadataL2ConflictEvictions'
 )){if(-not$tr.Contains($m)){Fail "translator anchor ausente: $m"}}
}

$presenter=[IO.File]::ReadAllText($PresenterPath)
foreach($m in @(
 '[V76.3.18.0][QUEUE_ARCHITECTURE]',
 'MaxRecycledGuestCommandBuffers = 256',
 '_computeQueueTimelineSemaphoreV1131',
 '_computeChainMaxV763171'
)){if(-not$presenter.Contains($m)){Fail "V18 Presenter contract ausente: $m"}}

$agc=[IO.File]::ReadAllText($AgcPath)
foreach($m in @(
 'V76.3.17.0_ASYNC_AGC_COMMAND_PROCESSOR',
 'QueueAsyncAgcSubmissionV763170'
)){if(-not$agc.Contains($m)){Fail "Async AGC ausente: $m"}}

$cli=[IO.File]::ReadAllText($CliPath)
foreach($m in @(
 '[V76.3.18.0][RPCS3_QUEUE_MERGE]',
 'Set("SHARPEMU_AGC_ASYNC_COMMAND_PROCESSOR", "1");',
 'Set("SHARPEMU_COMPUTE_CHAIN_MAX_V763171", "4");',
 'Set("SHARPEMU_HOST_ONLY_SIDEBAND", "0");',
 'Set("SHARPEMU_ORDERED_ACTION_MICROBATCH", "1");',
 'Set("SHARPEMU_DS_SAFE_MEMCOPY_V763151", "1");'
)){if(-not$cli.Contains($m)){Fail "V18 merged CLI contract ausente: $m"}}

$dotnet=(Get-Command dotnet.exe -ErrorAction SilentlyContinue).Source
if(-not$dotnet){$dotnet=(Get-Command dotnet -ErrorAction SilentlyContinue).Source}
if(-not$dotnet){Fail 'dotnet nao encontrado'}

Write-Host "[$Tag] PRECHECK PASSED base=V18 translator_mode=$(if($already){'already-v19'}else{'direct-map-v11710'})"
