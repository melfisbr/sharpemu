// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;
using System.Collections.Concurrent;
using System.IO;
using System.Text;

namespace SharpEmu.Libs.Kernel;

/// <summary>
/// Extension/signature-aware content routing diagnostics.
///
/// This class deliberately does not parse title-owned assets. It proves that the
/// guest filesystem receives the file and identifies the downstream subsystem
/// which is expected to consume it. This avoids incorrectly treating formats
/// such as BNK/DDS as "missing host decoders".
/// </summary>
internal static class ContentAssetRoutingDiagnostics
{
    private static readonly ConcurrentDictionary<string, byte> Seen =
        new(StringComparer.OrdinalIgnoreCase);

    private static readonly bool Enabled =
        string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_CONTENT_ROUTE_TRACE"),
            "1",
            StringComparison.Ordinal);

    public static void TracePath(string operation, string? guestPath, string? hostPath, bool found)
    {
        if (!Enabled || string.IsNullOrWhiteSpace(guestPath))
        {
            return;
        }

        var extension = Path.GetExtension(guestPath).ToLowerInvariant();
        if (!IsInteresting(extension))
        {
            return;
        }

        var key = operation + "|" + guestPath;
        if (!Seen.TryAdd(key, 0))
        {
            return;
        }

        var route = GetRoute(extension);
        var signature = found ? ProbeSignature(hostPath, extension) : "missing";

        Console.Error.WriteLine(
            $"[CONTENT-ROUTE] op={operation} ext={extension} found={found} " +
            $"route={route} signature={signature} guest='{guestPath}' host='{hostPath}'");
    }

    private static bool IsInteresting(string extension) =>
        extension is ".at9" or ".bnk" or ".xvag" or ".dds" or ".bk2" or
        ".ctxc" or ".ctxr" or ".cmsh" or ".cmdl" or ".csdr";

    private static string GetRoute(string extension) => extension switch
    {
        ".at9" => "guest-fileio->AJM/ATRAC9->AudioOut",
        ".bnk" => "guest-fileio->title-audio-bank->AJM/AudioOut",
        ".xvag" => "guest-fileio->title-audio-stream->audio-decoder/AJM",
        ".dds" => "guest-fileio->title-texture-loader->AGC->Vulkan",
        ".bk2" => "guest-fileio->Bink2/NIHAV->VideoOut",
        ".ctxc" or ".ctxr" => "guest-fileio->title-texture-stream->AGC->Vulkan",
        ".cmsh" or ".cmdl" => "guest-fileio->title-model-loader->AGC->Vulkan",
        ".csdr" => "guest-fileio->title-shader-resource->AGC/Gen5->SPIR-V",
        _ => "guest-fileio",
    };

    private static string ProbeSignature(string? hostPath, string extension)
    {
        if (string.IsNullOrWhiteSpace(hostPath) || !File.Exists(hostPath))
        {
            return "unavailable";
        }

        try
        {
            Span<byte> header = stackalloc byte[16];
            using var stream = new FileStream(
                hostPath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.ReadWrite | FileShare.Delete);

            var read = stream.Read(header);
            if (read <= 0)
            {
                return "empty";
            }

            var four = read >= 4
                ? Encoding.ASCII.GetString(header[..4])
                : Convert.ToHexString(header[..read]);

            if (extension == ".at9")
            {
                // ATRAC9 files used by PlayStation titles are commonly RIFF/WAVE
                // containers. The actual codec is still decoded through AJM/ATRAC9.
                return four == "RIFF" ? "RIFF(ATRAC9-candidate)" : "hex:" + Convert.ToHexString(header[..Math.Min(read, 8)]);
            }

            if (extension == ".bnk")
            {
                return four == "BKHD" ? "BKHD(audio-bank)" : "hex:" + Convert.ToHexString(header[..Math.Min(read, 8)]);
            }

            if (extension == ".xvag")
            {
                return four == "XVAG" ? "XVAG" : "hex:" + Convert.ToHexString(header[..Math.Min(read, 8)]);
            }

            if (extension == ".dds")
            {
                return four == "DDS " ? "DDS" : "hex:" + Convert.ToHexString(header[..Math.Min(read, 8)]);
            }

            if (extension == ".bk2")
            {
                return four.StartsWith("KB2", StringComparison.Ordinal) ? four : "hex:" + Convert.ToHexString(header[..Math.Min(read, 8)]);
            }

            return "hex:" + Convert.ToHexString(header[..Math.Min(read, 8)]);
        }
        catch (Exception exception)
        {
            return "probe-error:" + exception.GetType().Name;
        }
    }
}
