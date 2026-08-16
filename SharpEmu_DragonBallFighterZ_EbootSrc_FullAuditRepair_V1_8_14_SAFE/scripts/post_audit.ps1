. (Join-Path $PSScriptRoot "common.ps1")
$repo=Find-RepoRoot
$kernel=Get-KernelPath $repo
$ngs=Get-Ngs2Path $repo
$kt=Get-Content -LiteralPath $kernel -Raw
$nt=Get-Content -LiteralPath $ngs -Raw
$checks=@(
    @("kernel_title_bridge",$kt.Contains('CurrentApplicationTitleId => Volatile.Read(ref _applicationTitleId)')),
    @("kernel_dbfz_saved",$kt.Contains('SHARPEMU_DBFZ_SAVED_APP0_AUTO_V1_8_14')),
    @("kernel_saved_scope",$kt.Contains('"/app0/red/saved/"')),
    @("ngs_dbfz_parse",$nt.Contains('SHARPEMU_DBFZ_NGS2_PARSE_AUTO_V1_8_14')),
    @("ngs_record_size",$nt.Contains('stackalloc byte[0x240]')),
    @("ngs_title_scope",$nt.Contains('"PPSA09790"')),
    @("ngs_default_error_preserved",$nt.Contains('return SetReturn(ctx, unchecked((int)0x80020016));')),
    @("apr_preserved",$kt.Contains('Nid = "gEpBkcwxUjw"')),
    @("mkdir_preserved",$kt.Contains('Nid = "1-LFLmRFxxM"')),
    @("open_preserved",$kt.Contains('Nid = "1G3lF1Gg1k8"'))
)
foreach($c in $checks) {
    Write-Host "[DBFZ-AUDIT-1814] $($c[0])=$($c[1])"
    if(-not $c[1]) { throw "Post-audit failed: $($c[0])" }
}
Write-Host "[DBFZ-AUDIT-1814] POST-AUDIT PASSED."
