// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using SharpEmu.HLE.Host;
using System.Globalization;
using System.Text;

namespace SharpEmu.Libs.Pad;

/// <summary>One primary and one optional secondary host key for a pad action.</summary>
public sealed class KeyboardPadBinding
{
    public int Primary { get; set; }

    public int Secondary { get; set; }

    public KeyboardPadBinding()
    {
    }

    public KeyboardPadBinding(int primary, int secondary = 0)
    {
        Primary = primary;
        Secondary = secondary;
    }

    public KeyboardPadBinding Clone() => new(Primary, Secondary);
}

/// <summary>Metadata used by the launcher to render keyboard mapping rows.</summary>
public sealed record KeyboardPadActionDefinition(
    string Id,
    string LabelKey,
    string GroupKey,
    int DefaultPrimary,
    int DefaultSecondary);

/// <summary>
/// Shared keyboard-to-pad profile used by the launcher and scePad runtime.
/// Virtual-key values deliberately match the SDL window's host-key seam.
/// </summary>
public static class KeyboardPadMapping
{
    public const string EnvironmentVariableName = "SHARPEMU_KEYBOARD_MAP";

    public const string DpadLeft = "DpadLeft";
    public const string DpadRight = "DpadRight";
    public const string DpadUp = "DpadUp";
    public const string DpadDown = "DpadDown";
    public const string Cross = "Cross";
    public const string Circle = "Circle";
    public const string Square = "Square";
    public const string Triangle = "Triangle";
    public const string L1 = "L1";
    public const string R1 = "R1";
    public const string L2 = "L2";
    public const string R2 = "R2";
    public const string Share = "Share";
    public const string Options = "Options";
    public const string L3 = "L3";
    public const string R3 = "R3";
    public const string TouchPad = "TouchPad";
    public const string LeftStickLeft = "LeftStickLeft";
    public const string LeftStickRight = "LeftStickRight";
    public const string LeftStickUp = "LeftStickUp";
    public const string LeftStickDown = "LeftStickDown";
    public const string RightStickLeft = "RightStickLeft";
    public const string RightStickRight = "RightStickRight";
    public const string RightStickUp = "RightStickUp";
    public const string RightStickDown = "RightStickDown";

    private static readonly KeyboardPadActionDefinition[] ActionList =
    [
        new(DpadLeft, "Options.KeyboardMapping.Action.DpadLeft", "Options.KeyboardMapping.Group.Dpad", 0x25, 0),
        new(DpadRight, "Options.KeyboardMapping.Action.DpadRight", "Options.KeyboardMapping.Group.Dpad", 0x27, 0),
        new(DpadUp, "Options.KeyboardMapping.Action.DpadUp", "Options.KeyboardMapping.Group.Dpad", 0x26, 0),
        new(DpadDown, "Options.KeyboardMapping.Action.DpadDown", "Options.KeyboardMapping.Group.Dpad", 0x28, 0),

        new(Cross, "Options.KeyboardMapping.Action.Cross", "Options.KeyboardMapping.Group.Face", 0x5A, 0x0D),
        new(Circle, "Options.KeyboardMapping.Action.Circle", "Options.KeyboardMapping.Group.Face", 0x58, 0x1B),
        new(Square, "Options.KeyboardMapping.Action.Square", "Options.KeyboardMapping.Group.Face", 0x43, 0),
        new(Triangle, "Options.KeyboardMapping.Action.Triangle", "Options.KeyboardMapping.Group.Face", 0x56, 0),

        new(L1, "Options.KeyboardMapping.Action.L1", "Options.KeyboardMapping.Group.Shoulder", 0x51, 0),
        new(R1, "Options.KeyboardMapping.Action.R1", "Options.KeyboardMapping.Group.Shoulder", 0x45, 0),
        new(L2, "Options.KeyboardMapping.Action.L2", "Options.KeyboardMapping.Group.Shoulder", 0x52, 0),
        new(R2, "Options.KeyboardMapping.Action.R2", "Options.KeyboardMapping.Group.Shoulder", 0x46, 0),

        new(Share, "Options.KeyboardMapping.Action.Share", "Options.KeyboardMapping.Group.System", 0x08, 0),
        new(Options, "Options.KeyboardMapping.Action.Options", "Options.KeyboardMapping.Group.System", 0x09, 0),
        new(L3, "Options.KeyboardMapping.Action.L3", "Options.KeyboardMapping.Group.System", 0x47, 0),
        new(R3, "Options.KeyboardMapping.Action.R3", "Options.KeyboardMapping.Group.System", 0x48, 0),
        new(TouchPad, "Options.KeyboardMapping.Action.TouchPad", "Options.KeyboardMapping.Group.System", 0x54, 0),

        new(LeftStickLeft, "Options.KeyboardMapping.Action.LeftStickLeft", "Options.KeyboardMapping.Group.LeftStick", 0x41, 0),
        new(LeftStickRight, "Options.KeyboardMapping.Action.LeftStickRight", "Options.KeyboardMapping.Group.LeftStick", 0x44, 0),
        new(LeftStickUp, "Options.KeyboardMapping.Action.LeftStickUp", "Options.KeyboardMapping.Group.LeftStick", 0x57, 0),
        new(LeftStickDown, "Options.KeyboardMapping.Action.LeftStickDown", "Options.KeyboardMapping.Group.LeftStick", 0x53, 0),

        new(RightStickLeft, "Options.KeyboardMapping.Action.RightStickLeft", "Options.KeyboardMapping.Group.RightStick", 0x4A, 0),
        new(RightStickRight, "Options.KeyboardMapping.Action.RightStickRight", "Options.KeyboardMapping.Group.RightStick", 0x4C, 0),
        new(RightStickUp, "Options.KeyboardMapping.Action.RightStickUp", "Options.KeyboardMapping.Group.RightStick", 0x49, 0),
        new(RightStickDown, "Options.KeyboardMapping.Action.RightStickDown", "Options.KeyboardMapping.Group.RightStick", 0x4B, 0),
    ];

    public static IReadOnlyList<KeyboardPadActionDefinition> Actions => ActionList;

    public static Dictionary<string, KeyboardPadBinding> CreateDefaultBindings()
    {
        var result = new Dictionary<string, KeyboardPadBinding>(
            StringComparer.OrdinalIgnoreCase);
        foreach (var action in ActionList)
        {
            result[action.Id] = new KeyboardPadBinding(
                action.DefaultPrimary,
                action.DefaultSecondary);
        }

        return result;
    }

    public static Dictionary<string, KeyboardPadBinding> NormalizeBindings(
        IDictionary<string, KeyboardPadBinding>? source)
    {
        var result = CreateDefaultBindings();
        if (source is null)
        {
            return result;
        }

        foreach (var action in ActionList)
        {
            if (!source.TryGetValue(action.Id, out var candidate) ||
                candidate is null)
            {
                continue;
            }

            var primary = IsSupportedVirtualKey(candidate.Primary)
                ? candidate.Primary
                : 0;
            var secondary = IsSupportedVirtualKey(candidate.Secondary)
                ? candidate.Secondary
                : 0;
            if (secondary == primary)
            {
                secondary = 0;
            }

            result[action.Id] = new KeyboardPadBinding(primary, secondary);
        }

        return result;
    }

    public static string Serialize(
        IDictionary<string, KeyboardPadBinding>? bindings)
    {
        var normalized = NormalizeBindings(bindings);
        var builder = new StringBuilder(512);
        foreach (var action in ActionList)
        {
            if (builder.Length != 0)
            {
                builder.Append(';');
            }

            var binding = normalized[action.Id];
            builder.Append(action.Id);
            builder.Append('=');
            builder.Append(
                binding.Primary.ToString(
                    CultureInfo.InvariantCulture));
            builder.Append(',');
            builder.Append(
                binding.Secondary.ToString(
                    CultureInfo.InvariantCulture));
        }

        return builder.ToString();
    }

    public static string GetKeyDisplayName(int virtualKey) =>
        virtualKey switch
        {
            0 => "—",
            0x08 => "Backspace",
            0x09 => "Tab",
            0x0D => "Enter",
            0x1B => "Esc",
            0x25 => "←",
            0x26 => "↑",
            0x27 => "→",
            0x28 => "↓",
            >= 0x41 and <= 0x5A => ((char)virtualKey).ToString(),
            _ => $"0x{virtualKey:X2}",
        };

    public static bool IsSupportedVirtualKey(int virtualKey) =>
        virtualKey is 0 or 0x08 or 0x09 or 0x0D or 0x1B or
            0x25 or 0x26 or 0x27 or 0x28 ||
        virtualKey is >= 0x41 and <= 0x5A;
    private static readonly object RuntimeProfileGate = new();
    private static string? _runtimeProfileRaw;
    private static KeyboardPadProfile? _runtimeProfile;

    internal static KeyboardPadProfile GetRuntimeProfile()
    {
        var raw = Environment.GetEnvironmentVariable(EnvironmentVariableName);
        lock (RuntimeProfileGate)
        {
            if (_runtimeProfile is not null &&
                string.Equals(raw, _runtimeProfileRaw, StringComparison.Ordinal))
            {
                return _runtimeProfile;
            }

            _runtimeProfileRaw = raw;
            _runtimeProfile = ParseEnvironmentProfile();
            return _runtimeProfile;
        }
    } // SHARPEMU_RUNTIME_CORRECTIONS_V33_0_4_INPUT


    internal static KeyboardPadProfile ParseEnvironmentProfile()
    {
        var result = CreateDefaultBindings();
        var raw = Environment.GetEnvironmentVariable(
            EnvironmentVariableName);
        if (string.IsNullOrWhiteSpace(raw))
        {
            return new KeyboardPadProfile(result);
        }

        foreach (var assignment in raw.Split(
                     ';',
                     StringSplitOptions.RemoveEmptyEntries |
                     StringSplitOptions.TrimEntries))
        {
            var separator = assignment.IndexOf('=');
            if (separator <= 0 ||
                separator == assignment.Length - 1)
            {
                continue;
            }

            var actionId = assignment[..separator].Trim();
            if (!result.ContainsKey(actionId))
            {
                continue;
            }

            var values = assignment[(separator + 1)..].Split(
                ',',
                2,
                StringSplitOptions.TrimEntries);
            if (!int.TryParse(
                    values[0],
                    NumberStyles.Integer,
                    CultureInfo.InvariantCulture,
                    out var primary))
            {
                continue;
            }

            var secondary = 0;
            if (values.Length == 2)
            {
                _ = int.TryParse(
                    values[1],
                    NumberStyles.Integer,
                    CultureInfo.InvariantCulture,
                    out secondary);
            }

            primary = IsSupportedVirtualKey(primary) ? primary : 0;
            secondary = IsSupportedVirtualKey(secondary) ? secondary : 0;
            if (secondary == primary)
            {
                secondary = 0;
            }

            result[actionId] = new KeyboardPadBinding(
                primary,
                secondary);
        }

        return new KeyboardPadProfile(result);
    }
}

internal sealed class KeyboardPadProfile
{
    private readonly IReadOnlyDictionary<string, KeyboardPadBinding> _bindings;

    internal KeyboardPadProfile(
        IReadOnlyDictionary<string, KeyboardPadBinding> bindings)
    {
        _bindings = bindings;
    }

    internal bool IsPressed(IHostInput input, string actionId)
    {
        if (!_bindings.TryGetValue(actionId, out var binding))
        {
            return false;
        }

        return binding.Primary != 0 &&
                   input.IsKeyDown(binding.Primary) ||
               binding.Secondary != 0 &&
                   input.IsKeyDown(binding.Secondary);
    }
}
