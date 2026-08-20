// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;
using System.Collections.Concurrent;
using System.IO;
using System.Text;

namespace SharpEmu.Libs.Kernel;

/// <summary>
/// Evidence-driven content routing diagnostics for title-owned assets.
///
/// SharpEmu must not parse every proprietary Demon's Souls format on the host.
/// The guest engine owns formats such as CTXR/CTXC/CMSH/CMDL/CSDR/BNK. This
/// helper records successful guest opens and identifies the downstream
/// emulation subsystem that must consume the resulting bytes.
/// </summary>
internal static class ContentAssetRoutingDiagnostics
{
    private static readonly ConcurrentDictionary<string, byte> Seen =
        new(StringComparer.OrdinalIgnoreCase);

    // SHARPEMU_V74_0_56_27_BOUNDED_CONTENT_ROUTE
    private static readonly ConcurrentDictionary<string, long> RouteCounts =
        new(StringComparer.OrdinalIgnoreCase);

    private static readonly bool Enabled =
        string.Equals(
            Environment.GetEnvironmentVariable("SHARPEMU_CONTENT_ROUTE_TRACE"),
            "1",
            StringComparison.Ordinal);

    public static void TracePath(
        string operation,
        string? guestPath,
        string? hostPath,
        bool found)
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

        var key = operation + "|" + guestPath + "|" + found;
        if (!Seen.TryAdd(key, 0))
        {
            return;
        }

        var counterKey =
            operation + "|" + extension + "|" + found;

        var count = RouteCounts.AddOrUpdate(
            counterKey,
            1,
            static (_, current) => current + 1);

        // First sixteen unique paths make the route human-inspectable. After
        // that, powers of two retain a useful count without producing tens of
        // thousands of asset-path lines.
        if (count > 16 &&
            (count & (count - 1)) != 0)
        {
            return;
        }

        var route = GetRoute(extension);
        var signature = found
            ? ProbeSignature(hostPath, extension)
            : "missing";

        Console.Error.WriteLine(
            $"[CONTENT-ROUTE] op={operation} ext={extension} found={found} " +
            $"count={count} route={route} signature={signature} " +
            $"guest='{guestPath}' host='{hostPath}'");
    }

    private static bool IsInteresting(string extension) =>
        extension is ".at9" or ".bnk" or ".xvag" or ".dds" or ".bk2" or
        ".ctxc" or ".ctxr" or ".cmsh" or ".cmdl" or ".csdr" or ".cmat" or
        ".cani" or ".flver" or ".objbnd" or ".anibnd";

    private static string GetRoute(string extension) => extension switch
    {
        ".at9" => "guest-fileio->AJM/ATRAC9->AudioOut",
        ".xvag" => "guest-fileio->title-audio-stream->AJM/AudioOut",
        ".bnk" => "guest-fileio->title-audio-bank->AJM/AudioOut",
        ".dds" => "guest-fileio->title-texture-loader->AGC->Vulkan",
        ".bk2" => "guest-fileio->Bink2/NIHAV->VideoOut",
        ".ctxc" or ".ctxr" => "guest-fileio->title-texture-stream->AGC->Vulkan",
        ".cmsh" or ".cmdl" or ".flver" => "guest-fileio->title-geometry-loader->AGC->Vulkan",
        ".csdr" => "guest-fileio->title-shader-resource->AGC/Gen5->SPIR-V",
        ".cmat" => "guest-fileio->title-material-loader->AGC",
        ".cani" or ".anibnd" => "guest-fileio->title-animation-loader",
        ".objbnd" => "guest-fileio->title-object-bundle-loader",
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
                return four == "RIFF"
                    ? "RIFF(ATRAC9-candidate)"
                    : HexPrefix(header, read);
            }

            if (extension == ".xvag")
            {
                return four == "XVAG"
                    ? "XVAG"
                    : HexPrefix(header, read);
            }

            if (extension == ".bnk")
            {
                return four == "BKHD"
                    ? "BKHD(audio-bank)"
                    : HexPrefix(header, read);
            }

            if (extension == ".dds")
            {
                return four == "DDS "
                    ? "DDS"
                    : HexPrefix(header, read);
            }

            if (extension == ".bk2")
            {
                return four.StartsWith("KB2", StringComparison.Ordinal)
                    ? four
                    : HexPrefix(header, read);
            }

            return HexPrefix(header, read);
        }
        catch (Exception exception)
        {
            return "probe-error:" + exception.GetType().Name;
        }
    }

    private static string HexPrefix(Span<byte> header, int read) =>
        "hex:" + Convert.ToHexString(header[..Math.Min(read, 8)]);
}
