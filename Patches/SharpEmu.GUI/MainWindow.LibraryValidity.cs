// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

namespace SharpEmu.GUI;

public partial class MainWindow
{
    /// <summary>
    /// Central library validity rule. A HUD/library game must point to an
    /// existing executable named eboot.bin.
    /// </summary>
    private static bool IsLibraryEbootPath(string? path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return false;
        }

        string fullPath;
        try
        {
            fullPath = Path.GetFullPath(path);
        }
        catch (Exception ex) when (
            ex is ArgumentException or
            NotSupportedException or
            PathTooLongException)
        {
            return false;
        }

        return string.Equals(
                   Path.GetFileName(fullPath),
                   "eboot.bin",
                   StringComparison.OrdinalIgnoreCase) &&
               File.Exists(fullPath);
    }

    private static bool IsValidLibraryGame(GameEntry? game) =>
        game is not null && IsLibraryEbootPath(game.Path);
}
