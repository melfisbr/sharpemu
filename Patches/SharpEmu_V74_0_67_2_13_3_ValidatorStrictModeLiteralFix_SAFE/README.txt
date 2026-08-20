SharpEmu V74.0.67.2.13.3
Validator StrictMode Literal Fix SAFE

V2.13.2 failed in RUN_1 because validate_package.ps1 put the literal source
expression "$b.Contains(...)" inside a double-quoted PowerShell string while
common.ps1 enables Set-StrictMode -Version Latest. PowerShell expanded the
undefined variable $b before the validator could use the text.

V2.13.3 fixes this without any runtime source change.

The validator now performs:
- SHA256 validation for every manifest file;
- Windows PowerShell parser pass over every .ps1;
- reserved $host assignment scan;
- PowerShell 5.1 GetRelativePath scan;
- StrictMode unsafe double-quoted $b.Contains scan;
- RUN_1..RUN_5 existence and runner-target validation;
- exact diagnostic telemetry owner validation;
- V2.13 DLSS marker validation;
- V2.13 RAM marker validation;
- V74.0.64 multicache TTL owner validation;
- V2.12 BPE marker validation;
- native NGX FeatureCommonInfo/create/evaluate/last-error validation.

The validator self-scan uses a fragmented unsafe-token definition so it does
not recreate its own false positive.

V2.13.1 already built/applied the runtime code successfully. RUN_3 in V2.13.3
therefore performs deployment/export checks only and does not rebuild.

DLSS runtime proof:
  selected=dlss
  state=active
  dlss_dispatches>0

RAM runtime proof:
  ARRAY_CACHE_OWNER / ARRAY_SINGLEFLIGHT ttl_ms=120000
  plus lower alloc2s_mb / heap_mb / private_mb.
