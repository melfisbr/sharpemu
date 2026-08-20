# EBOOT Audit

Found: **True**
Format: **SCE_SELF_PS5**
Path: `F:\JOGOSPS5\PPSA01341\eboot.bin`
SHA256: `22DD832BAE21ABEB57FC66074D2BFA5F4C53F6EFED4544A9BE6B9E0D0316130E`
Size: 46575201 bytes

SELF segments: **12**
Encrypted segments: **0**
Compressed segments: **0**
Embedded ELF offset: **0x1A0**
Embedded ELF format: **ELF64_LE**
Dynamic undefined/import symbols extracted from embedded ELF: **0**

Static eboot evidence does not replace dynamic HLE/import/file-I/O tracing. It is used to compare what the executable declares/references with what SharpEmu actually reaches at runtime.
