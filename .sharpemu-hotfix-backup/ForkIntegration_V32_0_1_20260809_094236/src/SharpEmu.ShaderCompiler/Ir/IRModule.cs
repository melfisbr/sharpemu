namespace SharpEmu.ShaderCompiler.IR;


public sealed class IRModule
{

    private readonly List<IRInstruction> _instructions = new();



    public IReadOnlyList<IRInstruction> Instructions =>
        _instructions;



    public IRInstruction AddInstruction(
        IRInstruction instruction)
    {

        _instructions.Add(instruction);

        return instruction;
    }

}