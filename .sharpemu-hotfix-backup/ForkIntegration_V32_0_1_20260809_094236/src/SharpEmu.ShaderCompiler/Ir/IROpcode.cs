namespace SharpEmu.ShaderCompiler.IR;

public enum IROpcode
{
    Nop,

    Add,
    Sub,
    Mul,
    Div,
    Min,
    Max,
    Abs,
    Neg,
    Fma,
    Mad,

    Load,
    Store,

    Compare,

    SampleTexture,

    Branch,
    BranchConditional,
    Return
}
