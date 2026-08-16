. (Join-Path $PSScriptRoot "common.ps1")
$repo=Find-RepoRoot
$target=Join-Path $repo "src\SharpEmu.Libs\Kernel\KernelPthreadExtendedCompatExports.cs"
$t=Get-Content -LiteralPath $target -Raw

$get=Find-MethodBlock -Text $t -Signature 'public static int PosixPthreadGetspecific(CpuContext ctx)'
$set=Find-MethodBlock -Text $t -Signature 'public static int PosixPthreadSetspecific(CpuContext ctx)'
$des=Find-MethodBlock -Text $t -Signature 'public static void RunThreadLocalDestructors(CpuContext ctx)'

$checks=[ordered]@{
 marker=$t.Contains('SHARPEMU_DBFZ_PTHREAD_TLS_HOTPATH_V1_8_20')
 cache_handle=$t.Contains('_pthreadTlsFastThreadHandle')
 cache_values=$t.Contains('_pthreadTlsFastValues')
 get_method=($null -ne $get)
 get_no_tlskey_contains=($null -ne $get -and -not $get.Text.Contains('_tlsKeys.ContainsKey(key)'))
 get_inner_lookup=($null -ne $get -and $get.Text.Contains('values.TryGetValue(key, out var storedValue)'))
 set_updates_cache=($null -ne $set -and $set.Text.Contains('_pthreadTlsFastValues = values;'))
 destructor_clears_cache=($null -ne $des -and $des.Text.Contains('_pthreadTlsFastValues = null;'))
 getspecific_nid=$t.Contains('Nid = "eoht7mQOCmo"')
 setspecific_nid=$t.Contains('Nid = "+BzXYkqYeLE"')
}
foreach($kv in $checks.GetEnumerator()){
    Write-Host "[DBFZ-TLS-1820] $($kv.Key)=$($kv.Value)"
    if(-not $kv.Value){throw "Post-audit failed: $($kv.Key)"}
}
Write-Host "[DBFZ-TLS-1820] POST-AUDIT PASSED."
