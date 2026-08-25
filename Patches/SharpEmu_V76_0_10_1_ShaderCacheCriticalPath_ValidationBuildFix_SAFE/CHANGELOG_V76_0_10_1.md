# V76.0.10.1
- SPIR-V cache generation bumped to V76.0.10-r1.
- Old V76.0.5 cache binaries cannot be reused by the new translator generation.
- Non-semantic telemetry no longer fragments shader cache keys.
- Disk cache writes are serialized asynchronously off the shader compile critical path.
- Added Vulkan host-level handling for S_CLAUSE and S_WAITCNT_DEPCTR.
- Added Metal S_WAITCNT_DEPCTR parity.

- Validation BuildFix: exclude `scripts/validate.ps1` from its own downloader-token scan while preserving manifest/parser validation and scanning every other script/doc.
- C# payload remains identical to V76.0.10.
