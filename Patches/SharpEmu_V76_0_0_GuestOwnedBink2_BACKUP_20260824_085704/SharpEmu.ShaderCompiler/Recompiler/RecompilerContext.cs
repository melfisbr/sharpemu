using SharpEmu.ShaderCompiler.IR;

namespace SharpEmu.ShaderCompiler.Recompiler;

public sealed class RecompilerContext
{
    public IRBuilder Builder { get; }

    public Dictionary<int, IRValue> Registers { get; }

    public RecompilerContext(IRBuilder builder)
    {
        Builder = builder;
        Registers = new();
    }
}