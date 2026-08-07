// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

namespace SharpEmu.ShaderCompiler.IR;

/// <summary>
/// Control-flow graph built from decoded Gen5 shader instructions.
/// Block ranges use an inclusive start PC and an exclusive end PC.
/// </summary>
public sealed class IrControlFlowGraph
{
    public List<IrBlockRange> Blocks { get; } = new();

    public Dictionary<uint, int> BlockByStartPc { get; } = new();

    public List<List<int>> Successors { get; } = new();

    public List<List<int>> Predecessors { get; } = new();

    public HashSet<int> LoopHeaders { get; } = new();

    public bool HasControlFlow =>
        Successors.Any(static successors => successors.Count > 1) ||
        Predecessors.Any(static predecessors => predecessors.Count > 1) ||
        LoopHeaders.Count != 0 ||
        HasNonLinearEdge();

    public void AddBlock(IrBlockRange block)
    {
        ArgumentNullException.ThrowIfNull(block);

        var index = Blocks.Count;
        Blocks.Add(block);
        BlockByStartPc.Add(block.StartPc, index);
        Successors.Add(new List<int>());
        Predecessors.Add(new List<int>());
    }

    public static IrControlFlowGraph Build(
        IReadOnlyList<Gen5ShaderInstruction> instructions,
        IIrBranchResolver resolver)
    {
        ArgumentNullException.ThrowIfNull(instructions);
        ArgumentNullException.ThrowIfNull(resolver);

        var graph = new IrControlFlowGraph();
        if (instructions.Count == 0)
        {
            return graph;
        }

        var ordered = instructions
            .OrderBy(static instruction => instruction.Pc)
            .ToArray();

        var instructionByPc = ordered.ToDictionary(
            static instruction => instruction.Pc);

        var leaders = new SortedSet<uint>
        {
            ordered[0].Pc
        };

        foreach (var instruction in ordered)
        {
            if (!resolver.IsBranch(instruction))
            {
                continue;
            }

            if (resolver.TryGetBranchTarget(instruction, out var targetPc) &&
                instructionByPc.ContainsKey(targetPc))
            {
                leaders.Add(targetPc);
            }

            // The instruction after every branch starts a new block. For an
            // unconditional branch this block may be unreachable, but it must
            // still exist so CFG consumers can reason about skipped code.
            var nextPc = GetNextPc(instruction);
            if (instructionByPc.ContainsKey(nextPc))
            {
                leaders.Add(nextPc);
            }
        }

        var leaderArray = leaders.ToArray();
        var programEnd = GetNextPc(ordered[^1]);

        for (var index = 0; index < leaderArray.Length; index++)
        {
            var startPc = leaderArray[index];
            var endPc = index + 1 < leaderArray.Length
                ? leaderArray[index + 1]
                : programEnd;

            graph.AddBlock(
                new IrBlockRange(
                    startPc,
                    endPc));
        }

        var blockByInstructionPc = new Dictionary<uint, int>();

        for (var blockIndex = 0; blockIndex < graph.Blocks.Count; blockIndex++)
        {
            var block = graph.Blocks[blockIndex];

            foreach (var instruction in ordered)
            {
                if (block.Contains(instruction.Pc))
                {
                    blockByInstructionPc[instruction.Pc] = blockIndex;
                }
            }
        }

        for (var blockIndex = 0; blockIndex < graph.Blocks.Count; blockIndex++)
        {
            var block = graph.Blocks[blockIndex];
            var terminator = ordered
                .LastOrDefault(instruction => block.Contains(instruction.Pc));

            if (terminator is null)
            {
                continue;
            }

            if (resolver.IsBranch(terminator))
            {
                if (resolver.TryGetBranchTarget(terminator, out var targetPc) &&
                    blockByInstructionPc.TryGetValue(targetPc, out var targetBlock))
                {
                    graph.AddEdge(blockIndex, targetBlock);
                }

                if (resolver.IsConditional(terminator))
                {
                    var fallthroughPc = GetNextPc(terminator);
                    if (blockByInstructionPc.TryGetValue(
                            fallthroughPc,
                            out var fallthroughBlock))
                    {
                        graph.AddEdge(blockIndex, fallthroughBlock);
                    }
                }

                continue;
            }

            if (blockIndex + 1 < graph.Blocks.Count)
            {
                graph.AddEdge(blockIndex, blockIndex + 1);
            }
        }

        return graph;
    }

    private bool HasNonLinearEdge()
    {
        for (var from = 0; from < Successors.Count; from++)
        {
            foreach (var to in Successors[from])
            {
                if (to != from + 1)
                {
                    return true;
                }
            }
        }

        return false;
    }

    private void AddEdge(int from, int to)
    {
        if ((uint)from >= (uint)Blocks.Count)
        {
            throw new ArgumentOutOfRangeException(nameof(from));
        }

        if ((uint)to >= (uint)Blocks.Count)
        {
            throw new ArgumentOutOfRangeException(nameof(to));
        }

        if (!Successors[from].Contains(to))
        {
            Successors[from].Add(to);
        }

        if (!Predecessors[to].Contains(from))
        {
            Predecessors[to].Add(from);
        }

        if (to <= from)
        {
            LoopHeaders.Add(to);
        }
    }

    private static uint GetNextPc(Gen5ShaderInstruction instruction)
    {
        var byteLength = instruction.Words.Count > 0
            ? checked((uint)instruction.Words.Count * sizeof(uint))
            : sizeof(uint);

        return checked(instruction.Pc + byteLength);
    }
}

public sealed class IrBlockRange
{
    public uint StartPc { get; }

    public uint EndPc { get; }

    public int Start => checked((int)StartPc);

    public int End => checked((int)EndPc);

    public IrBlockRange(uint startPc, uint endPc)
    {
        if (endPc < startPc)
        {
            throw new ArgumentOutOfRangeException(
                nameof(endPc),
                "The block end PC cannot precede its start PC.");
        }

        StartPc = startPc;
        EndPc = endPc;
    }

    public IrBlockRange(int start, int end)
        : this(
            checked((uint)start),
            checked((uint)end))
    {
    }

    public bool Contains(uint pc) =>
        pc >= StartPc &&
        pc < EndPc;

    public bool Contains(int index) =>
        index >= 0 &&
        Contains((uint)index);
}
