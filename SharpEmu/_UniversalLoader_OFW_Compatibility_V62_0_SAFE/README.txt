SharpEmu V62.0 SAFE — OFW/Universal Loader compatibility

Fixes structural loader rejection for decrypted PS5 titles:
- accept e_phentsize >= the known ELF64 ProgramHeader prefix;
- recover a strictly validated embedded ELF64/x86-64 from alternate decrypted wrappers;
- when PT_DYNAMIC is absent, use the loader's existing section relocation/symbol machinery instead of returning immediately;
- add descriptive GNU/SCE program-header enum values.

The existing behavior that treats p_vaddr/p_offset alignment differences as warnings is preserved. Historical OFW/PRX logs show those mismatches on valid modules.

LIMIT: this does not decrypt encrypted retail eboots. OFW metadata/NIDs cannot substitute for cryptographic decryption.
