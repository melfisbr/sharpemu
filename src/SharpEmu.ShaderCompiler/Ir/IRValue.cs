// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

namespace SharpEmu.ShaderCompiler.IR;

public sealed class IRValue
{
    public int Id { get; }

    public IRType Type { get; }

    public string Name { get; }

    public IRValue(
        int id,
        IRType type,
        string? name = null)
    {
        if (id < 0)
        {
            throw new ArgumentOutOfRangeException(
                nameof(id),
                id,
                "O identificador do valor IR não pode ser negativo.");
        }

        Id = id;
        Type = type;
        Name = string.IsNullOrWhiteSpace(name)
            ? $"%{id}"
            : name;
    }

    public override string ToString() => Name;
}
