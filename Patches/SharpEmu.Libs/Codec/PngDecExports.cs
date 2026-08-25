// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using SharpEmu.HLE;
using System.Buffers;
using System.Buffers.Binary;

namespace SharpEmu.Libs.Codec;

/// <summary>
/// libScePngDec HLE compatibility layer.
/// The ABI/error behavior follows the public KytyPS5 implementation, while the
/// decoder itself is an independent managed implementation owned by SharpEmu.
/// </summary>
public static class PngDecExports
{
    private const int Ok = 0;
    private const int ErrorInvalidAddress = unchecked((int)0x80690001);
    private const int ErrorInvalidSize = unchecked((int)0x80690002);
    private const int ErrorInvalidParam = unchecked((int)0x80690003);
    private const int ErrorInvalidHandle = unchecked((int)0x80690004);
    private const int ErrorInvalidWorkMemory = unchecked((int)0x80690005);
    private const int ErrorInvalidData = unchecked((int)0x80690010);
    private const int ErrorDecode = unchecked((int)0x80690012);
    private const uint AttributeBitDepth16 = 1;
    private const ushort PixelFormatRgba = 0;
    private const ushort PixelFormatBgra = 1;
    private const int ContextSize = sizeof(ulong);
    private const uint MaxPngBytes = 64 * 1024 * 1024;
    private const ulong ContextMagic = 0x4B595459504E4744UL; // stable 8-byte work-memory marker

    [SysAbiExport(Nid = "-6srIGbLTIU", ExportName = "scePngDecQueryMemorySize",
        Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libScePngDec")]
    public static int PngDecQueryMemorySize(CpuContext ctx)
    {
        var paramAddress = ctx[CpuRegister.Rdi];
        var result = TryReadCreateParam(ctx, paramAddress, out var attribute, out var maxWidth);
        if (result != Ok)
        {
            return SetReturn(ctx, result);
        }
        if (attribute > AttributeBitDepth16)
        {
            return SetReturn(ctx, ErrorInvalidParam);
        }
        if (maxWidth == 0)
        {
            return SetReturn(ctx, ErrorInvalidSize);
        }
        return SetReturn(ctx, ContextSize);
    }

    [SysAbiExport(Nid = "m0uW+8pFyaw", ExportName = "scePngDecCreate",
        Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libScePngDec")]
    public static int PngDecCreate(CpuContext ctx)
    {
        var paramAddress = ctx[CpuRegister.Rdi];
        var memoryAddress = ctx[CpuRegister.Rsi];
        var memorySize = unchecked((uint)ctx[CpuRegister.Rdx]);
        var handleAddress = ctx[CpuRegister.Rcx];

        if (paramAddress == 0 || handleAddress == 0)
        {
            return SetReturn(ctx, ErrorInvalidParam);
        }
        var result = TryReadCreateParam(ctx, paramAddress, out var attribute, out var maxWidth);
        if (result != Ok)
        {
            return SetReturn(ctx, result);
        }
        if (attribute > AttributeBitDepth16)
        {
            return SetReturn(ctx, ErrorInvalidParam);
        }
        if (maxWidth == 0)
        {
            return SetReturn(ctx, ErrorInvalidSize);
        }
        if (memoryAddress == 0)
        {
            return SetReturn(ctx, ErrorInvalidAddress);
        }
        if (memorySize < ContextSize)
        {
            return SetReturn(ctx, ErrorInvalidWorkMemory);
        }
        if (!ctx.TryWriteUInt64(memoryAddress, ContextMagic) ||
            !ctx.TryWriteUInt64(handleAddress, memoryAddress))
        {
            return SetReturn(ctx, ErrorInvalidAddress);
        }
        return SetReturn(ctx, Ok);
    }

    [SysAbiExport(Nid = "WC216DD3El4", ExportName = "scePngDecDecode",
        Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libScePngDec")]
    public static int PngDecDecode(CpuContext ctx)
    {
        var handle = ctx[CpuRegister.Rdi];
        var paramAddress = ctx[CpuRegister.Rsi];
        var imageInfoAddress = ctx[CpuRegister.Rdx];
        if (!IsValidHandle(ctx, handle))
        {
            return SetReturn(ctx, ErrorInvalidHandle);
        }
        if (paramAddress == 0)
        {
            return SetReturn(ctx, ErrorInvalidParam);
        }

        Span<byte> param = stackalloc byte[32];
        if (!ctx.Memory.TryRead(paramAddress, param))
        {
            return SetReturn(ctx, ErrorInvalidParam);
        }
        var pngAddress = BinaryPrimitives.ReadUInt64LittleEndian(param[..8]);
        var imageAddress = BinaryPrimitives.ReadUInt64LittleEndian(param.Slice(8, 8));
        var pngSize = BinaryPrimitives.ReadUInt32LittleEndian(param.Slice(16, 4));
        var imageSize = BinaryPrimitives.ReadUInt32LittleEndian(param.Slice(20, 4));
        var pixelFormat = BinaryPrimitives.ReadUInt16LittleEndian(param.Slice(24, 2));
        var alphaValue = BinaryPrimitives.ReadUInt16LittleEndian(param.Slice(26, 2));
        var imagePitch = BinaryPrimitives.ReadUInt32LittleEndian(param.Slice(28, 4));

        if (pngAddress == 0 || imageAddress == 0)
        {
            return SetReturn(ctx, ErrorInvalidAddress);
        }
        if (pngSize == 0 || pngSize > MaxPngBytes)
        {
            return SetReturn(ctx, ErrorInvalidSize);
        }
        if (pixelFormat is not (PixelFormatRgba or PixelFormatBgra))
        {
            return SetReturn(ctx, ErrorInvalidParam);
        }

        var rented = ArrayPool<byte>.Shared.Rent(checked((int)pngSize));
        try
        {
            var png = rented.AsSpan(0, checked((int)pngSize));
            if (!ctx.Memory.TryRead(pngAddress, png))
            {
                return SetReturn(ctx, ErrorInvalidAddress);
            }
            if (!PngDecoder.TryReadHeader(png, out var header))
            {
                return SetReturn(ctx, ErrorInvalidData);
            }
            if (imageInfoAddress != 0 && !TryWriteImageInfo(ctx, imageInfoAddress, header))
            {
                return SetReturn(ctx, ErrorInvalidAddress);
            }

            var minPitch64 = (ulong)header.Width * 4UL;
            if (minPitch64 > uint.MaxValue)
            {
                return SetReturn(ctx, ErrorInvalidSize);
            }
            var minPitch = (uint)minPitch64;
            var pitch = imagePitch == 0 ? minPitch : imagePitch;
            var required = header.Height == 0
                ? 0UL
                : (ulong)pitch * (header.Height - 1UL) + minPitch;
            if (pitch < minPitch || required > imageSize)
            {
                return SetReturn(ctx, ErrorInvalidSize);
            }

            if (!PngDecoder.TryDecodeRgba(png, out var rgba, out var decodedHeader) ||
                decodedHeader.Width != header.Width || decodedHeader.Height != header.Height)
            {
                return SetReturn(ctx, ErrorDecode);
            }

            var applyAlpha = !header.HasSourceAlpha;
            var replacementAlpha = (byte)Math.Min(alphaValue, (ushort)255);
            var rowBytes = checked((int)minPitch);
            var row = ArrayPool<byte>.Shared.Rent(rowBytes);
            try
            {
                for (var y = 0u; y < header.Height; y++)
                {
                    var source = rgba.AsSpan(checked((int)y * rowBytes), rowBytes);
                    var destination = row.AsSpan(0, rowBytes);
                    source.CopyTo(destination);
                    for (var x = 0; x < rowBytes; x += 4)
                    {
                        if (applyAlpha)
                        {
                            destination[x + 3] = replacementAlpha;
                        }
                        if (pixelFormat == PixelFormatBgra)
                        {
                            var swap = destination[x];
                            destination[x] = destination[x + 2];
                            destination[x + 2] = swap;
                        }
                    }
                    if (!ctx.Memory.TryWrite(imageAddress + (ulong)y * pitch, destination))
                    {
                        return SetReturn(ctx, ErrorInvalidAddress);
                    }
                }
            }
            finally
            {
                ArrayPool<byte>.Shared.Return(row);
            }

            var packed = header.Width > 32767 || header.Height > 32767
                ? 0
                : unchecked((int)((header.Width << 16) | header.Height));
            return SetReturn(ctx, packed);
        }
        finally
        {
            ArrayPool<byte>.Shared.Return(rented);
        }
    }

    [SysAbiExport(Nid = "QbD+eENEwo8", ExportName = "scePngDecDelete",
        Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libScePngDec")]
    public static int PngDecDelete(CpuContext ctx)
    {
        var handle = ctx[CpuRegister.Rdi];
        if (!IsValidHandle(ctx, handle))
        {
            return SetReturn(ctx, ErrorInvalidHandle);
        }
        return SetReturn(ctx, ctx.TryWriteUInt64(handle, 0) ? Ok : ErrorInvalidHandle);
    }

    [SysAbiExport(Nid = "U6h4e5JRPaQ", ExportName = "scePngDecParseHeader",
        Target = Generation.Gen4 | Generation.Gen5, LibraryName = "libScePngDec")]
    public static int PngDecParseHeader(CpuContext ctx)
    {
        var paramAddress = ctx[CpuRegister.Rdi];
        var imageInfoAddress = ctx[CpuRegister.Rsi];
        if (paramAddress == 0 || imageInfoAddress == 0)
        {
            return SetReturn(ctx, ErrorInvalidParam);
        }

        Span<byte> param = stackalloc byte[16];
        if (!ctx.Memory.TryRead(paramAddress, param))
        {
            return SetReturn(ctx, ErrorInvalidParam);
        }
        var pngAddress = BinaryPrimitives.ReadUInt64LittleEndian(param[..8]);
        var pngSize = BinaryPrimitives.ReadUInt32LittleEndian(param.Slice(8, 4));
        var reserved = BinaryPrimitives.ReadUInt32LittleEndian(param.Slice(12, 4));
        if (pngAddress == 0)
        {
            return SetReturn(ctx, ErrorInvalidAddress);
        }
        if (reserved != 0)
        {
            return SetReturn(ctx, ErrorInvalidParam);
        }
        if (pngSize == 0 || pngSize > MaxPngBytes)
        {
            return SetReturn(ctx, ErrorInvalidData);
        }

        var rented = ArrayPool<byte>.Shared.Rent(checked((int)pngSize));
        try
        {
            var png = rented.AsSpan(0, checked((int)pngSize));
            if (!ctx.Memory.TryRead(pngAddress, png))
            {
                return SetReturn(ctx, ErrorInvalidAddress);
            }
            if (!PngDecoder.TryReadHeader(png, out var header))
            {
                return SetReturn(ctx, ErrorInvalidData);
            }
            return SetReturn(ctx, TryWriteImageInfo(ctx, imageInfoAddress, header) ? Ok : ErrorInvalidAddress);
        }
        finally
        {
            ArrayPool<byte>.Shared.Return(rented);
        }
    }

    private static int TryReadCreateParam(
        CpuContext ctx,
        ulong paramAddress,
        out uint attribute,
        out uint maxWidth)
    {
        attribute = 0;
        maxWidth = 0;
        if (paramAddress == 0)
        {
            return ErrorInvalidParam;
        }
        Span<byte> param = stackalloc byte[12];
        if (!ctx.Memory.TryRead(paramAddress, param))
        {
            return ErrorInvalidParam;
        }
        attribute = BinaryPrimitives.ReadUInt32LittleEndian(param.Slice(4, 4));
        maxWidth = BinaryPrimitives.ReadUInt32LittleEndian(param.Slice(8, 4));
        return Ok;
    }

    private static bool IsValidHandle(CpuContext ctx, ulong handle) =>
        handle != 0 && ctx.TryReadUInt64(handle, out var magic) && magic == ContextMagic;

    private static bool TryWriteImageInfo(CpuContext ctx, ulong address, PngDecoder.HeaderInfo info)
    {
        Span<byte> bytes = stackalloc byte[16];
        BinaryPrimitives.WriteUInt32LittleEndian(bytes[..4], info.Width);
        BinaryPrimitives.WriteUInt32LittleEndian(bytes.Slice(4, 4), info.Height);
        BinaryPrimitives.WriteUInt16LittleEndian(bytes.Slice(8, 2), info.ColorSpace);
        BinaryPrimitives.WriteUInt16LittleEndian(bytes.Slice(10, 2), info.BitDepth);
        BinaryPrimitives.WriteUInt32LittleEndian(bytes.Slice(12, 4), info.ImageFlags);
        return ctx.Memory.TryWrite(address, bytes);
    }

    private static int SetReturn(CpuContext ctx, int result)
    {
        ctx[CpuRegister.Rax] = unchecked((ulong)result);
        return result;
    }
}
