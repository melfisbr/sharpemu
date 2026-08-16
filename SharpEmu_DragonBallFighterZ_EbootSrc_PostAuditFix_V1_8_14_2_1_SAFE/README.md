# DBFZ Post-Audit Fix V1.8.14.2.1 SAFE

This package does NOT modify source.

V1.8.14.2 built successfully. Its post-audit produced a false negative because
it looked for sceKernelOpen NID 1G3lF1Gg1k8 only in KernelMemoryCompatExports.cs.
In the current architecture sceKernelOpen is owned by KernelExports and may be
registered through generated SysAbi registry code.

This package validates open/mkdir/APR across all src C# files by NID, export
name, or method evidence, verifies the V1.8.14.2 DBFZ markers, then runs the
360-second DBFZ diagnostic.
