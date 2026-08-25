# SharpEmu V76.0.8

- Correct GFX10 MUBUF opcode width from 7 to 8 bits and decode BUFFER_*_FORMAT_D16 0x80-0x87.
- Propagate MUBUF format component count, D16 packing and store/no-destination semantics into IR.
- Implement MTBUF and MUBUF typed format stores instead of raw-dword fallback/pending failure.
- MTBUF store uses instruction FORMAT with identity channels; MUBUF store uses resource FORMAT and resource dst_sel.
- Convert UNORM, SNORM, USCALED, SSCALED, UINT, SINT, f16/f32 and packed 10/11-bit unsigned mini-floats before guest memory writes.
- Unpack D16 store VGPR halves and preserve format-dependent integer vs floating interpretation.
- Fix D16 load narrowing comparison that accidentally compared numberFormat against SPIR-V constant IDs instead of numeric 4/5.
