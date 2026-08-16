# V74.0.6.3 StringBuilder physical-line repair

V74.0.6.2 still emitted the replacement as a collapsed physical line even
though it correctly identified source line 8662. SAFE rollback restored the
presenter.

V74.0.6.3 eliminates PowerShell replacement arrays entirely. It constructs the
C# block with `StringBuilder.AppendLine()`, replaces the exact physical
character range with `WriteAllText()`, and validates the local physical lines
afterward.

# SharpEmu Demon's Souls — Compute Texture Resolve Restore V74.0.6.2 SAFE

V74.0.6.1 again stopped before build because its verifier still confused
different `for (var index...)` loops in `CreateComputeDispatchResources()`.

The baseline source is known exactly:

    VulkanVideoPresenter.cs
    SHA256 A9E4F7D3BB6ADF5B2956FD332A9C4EA3E28ADE5F2EBFF42DCD73EBDAFB0BA3F5

In that source, the corrupted V73.20 compute block occupies exactly one physical
line (1549 characters) beginning with `//`. That line contains the
host-movie binding, the texture loop, all `resources.Textures[index]`
assignments and `ResolveTextureResource()` calls, so C# comments all of them.

V74.0.6.2 no longer uses method-wide loop inference.

It:
1. loads `VulkanVideoPresenter.cs` with `ReadAllLines`;
2. finds the single physical line containing the V73.20 marker;
3. verifies that same line contains hostMovieTextures, assignment and resolver;
4. removes exactly that one line;
5. inserts the multiline executable C# block as distinct `string[]` lines;
6. writes the source with `WriteAllLines`;
7. verifies only an 80-line window after the restored marker.

The runtime correction is unchanged: populate every compute texture resource
before descriptor creation.
