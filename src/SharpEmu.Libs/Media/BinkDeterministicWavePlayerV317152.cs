// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Buffers.Binary;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace SharpEmu.Libs.Media;

/// <summary>
/// V31.7.15.2: deterministic WinMM waveOut clock for the Demon's Souls
/// attract-movie sidecar.
///
/// PlaySound(SND_ASYNC) reports that queuing succeeded, not that samples have
/// reached the output device.  This backend exposes waveOutGetPosition so the
/// RAD child can stay hidden until a configured amount of real audio progress
/// has occurred.
/// </summary>
internal static class BinkDeterministicWavePlayerV317152
{
    private const uint WaveMapper = 0xFFFF_FFFFu;
    private const uint MmNoError = 0;
    private const uint TimeMs = 0x0001;
    private const uint TimeSamples = 0x0002;
    private const uint TimeBytes = 0x0004;

    private static readonly object Gate = new();

    private static nint _waveOut;
    private static nint _data;
    private static nint _header;
    private static int _headerSize;
    private static bool _prepared;
    private static uint _sampleRate;
    private static uint _avgBytesPerSecond;
    private static string? _activeWave;

    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    private struct WaveFormatEx
    {
        public ushort FormatTag;
        public ushort Channels;
        public uint SamplesPerSec;
        public uint AvgBytesPerSec;
        public ushort BlockAlign;
        public ushort BitsPerSample;
        public ushort ExtraSize;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct WaveHeader
    {
        public nint Data;
        public uint BufferLength;
        public uint BytesRecorded;
        public nuint User;
        public uint Flags;
        public uint Loops;
        public nint Next;
        public nuint Reserved;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MmTime
    {
        public uint Type;
        public uint Value;
        public uint Value2;
    }

    // SHARPEMU_DEMONS_ATTRACT_RAD_VISIBLE_FRAME_PLAYER_RELEASE_V1_1_8
    // V31.7.21 intentionally prepares the deterministic WaveOut sidecar
    // paused until a visible-frame event.  A RAD child window does not produce
    // the Vulkan-present notification used by that latch, so V1.1.8 lets the
    // RAD ShowWindow boundary serve as the visible-frame release.
    internal static bool TryResumePreparedAtRendererRevealV118(
        out string detail)
    {
        detail = string.Empty;

        if (!OperatingSystem.IsWindows())
        {
            detail = "non-windows";
            return false;
        }

        lock (Gate)
        {
            if (_waveOut == 0)
            {
                detail = "no-waveout";
                return false;
            }

            if (!_prepared)
            {
                detail = "not-prepared";
                return false;
            }

            var restart = waveOutRestart(_waveOut);
            if (restart != MmNoError)
            {
                detail = $"waveOutRestart:{restart}";
                return false;
            }

            detail =
                $"waveOutRestart:{restart} " +
                $"active='{_activeWave ?? string.Empty}'";
            return true;
        }
    }
    // SHARPEMU_DEMONS_ATTRACT_DIRECT_RAD_WAVEOUT_RELEASE_PLAYER_V1_1_9
    // The V31.7.21 attract path has already opened, prepared and queued the
    // sidecar when it reports state=paused-prepared.  The RAD callback itself
    // is therefore the correct owner of the final waveOutRestart transition.
    internal static bool TryReleasePreparedAfterRadCallbackV119(
        out string detail)
    {
        detail = string.Empty;

        if (!OperatingSystem.IsWindows())
        {
            detail = "non-windows";
            return false;
        }

        lock (Gate)
        {
            if (_waveOut == 0)
            {
                detail = "no-waveout";
                return false;
            }

            if (!_prepared)
            {
                detail = "not-prepared";
                return false;
            }

            var restart = waveOutRestart(_waveOut);
            if (restart != MmNoError)
            {
                detail = $"waveOutRestart:{restart}";
                return false;
            }

            _ = TryGetProgressMillisecondsLocked(
                out var initialCursorMs);

            detail =
                $"waveOutRestart:{restart} " +
                $"cursor_ms={initialCursorMs:F3} " +
                $"active='{_activeWave ?? string.Empty}'";
            return true;
        }
    }
    internal static bool TryStart(string wavePath, out string detail)
    {
        if (!TryPreparePaused(wavePath, out detail))
        {
            return false;
        }

        return TryStartPrepared(out detail);
    }

    // V31.7.21_VISIBLE_FRAME_AUDIO_LATCH
    // Fully open/prepare/write the WaveOut buffer while the RAD child is hidden,
    // but keep the device paused.  This removes file I/O, allocation and header
    // setup from the first-visible-frame critical path without allowing a single
    // sample to advance before the video is actually revealed.
    internal static bool TryPreparePaused(string wavePath, out string detail)
    {
        detail = string.Empty;

        if (!OperatingSystem.IsWindows() ||
            string.IsNullOrWhiteSpace(wavePath) ||
            !File.Exists(wavePath))
        {
            detail = "wave-missing-or-platform";
            return false;
        }

        byte[] wave;
        try
        {
            wave = File.ReadAllBytes(wavePath);
        }
        catch (Exception ex)
        {
            detail = "read:" + ex.GetType().Name;
            return false;
        }

        if (!TryParsePcmWave(
                wave,
                out var format,
                out var dataOffset,
                out var dataLength,
                out detail))
        {
            return false;
        }

        lock (Gate)
        {
            StopLocked();

            try
            {
                var open = waveOutOpen(
                    out _waveOut,
                    WaveMapper,
                    ref format,
                    0,
                    0,
                    0);

                if (open != MmNoError || _waveOut == 0)
                {
                    detail = $"waveOutOpen:{open}";
                    StopLocked();
                    return false;
                }

                var pause = waveOutPause(_waveOut);
                if (pause != MmNoError)
                {
                    detail = $"waveOutPause:{pause}";
                    StopLocked();
                    return false;
                }

                _data = Marshal.AllocHGlobal(dataLength);
                Marshal.Copy(wave, dataOffset, _data, dataLength);

                var header = new WaveHeader
                {
                    Data = _data,
                    BufferLength = checked((uint)dataLength),
                    BytesRecorded = 0,
                    User = 0,
                    Flags = 0,
                    Loops = 0,
                    Next = 0,
                    Reserved = 0,
                };

                _headerSize = Marshal.SizeOf<WaveHeader>();
                _header = Marshal.AllocHGlobal(_headerSize);
                Marshal.StructureToPtr(header, _header, false);

                var prepare = waveOutPrepareHeader(
                    _waveOut,
                    _header,
                    checked((uint)_headerSize));
                if (prepare != MmNoError)
                {
                    detail = $"waveOutPrepareHeader:{prepare}";
                    StopLocked();
                    return false;
                }

                _prepared = true;

                var write = waveOutWrite(
                    _waveOut,
                    _header,
                    checked((uint)_headerSize));
                if (write != MmNoError)
                {
                    detail = $"waveOutWrite:{write}";
                    StopLocked();
                    return false;
                }

                _sampleRate = format.SamplesPerSec;
                _avgBytesPerSecond = format.AvgBytesPerSec;
                _activeWave = wavePath;

                detail =
                    $"pcm={format.SamplesPerSec}Hz/{format.Channels}ch/" +
                    $"{format.BitsPerSample}bit bytes={dataLength} state=paused-prepared";
                return true;
            }
            catch (Exception ex)
            {
                detail = "prepare:" + ex.GetType().Name;
                StopLocked();
                return false;
            }
        }
    }

    internal static bool TryStartPrepared(out string detail)
    {
        lock (Gate)
        {
            if (_waveOut == 0 || !_prepared || string.IsNullOrWhiteSpace(_activeWave))
            {
                detail = "not-prepared";
                return false;
            }

            var restart = waveOutRestart(_waveOut);
            if (restart != MmNoError)
            {
                detail = $"waveOutRestart:{restart}";
                return false;
            }

            detail = "waveOutRestart:0 state=running";
            return true;
        }
    }

    internal static bool WaitForProgress(
        int targetMilliseconds,
        int timeoutMilliseconds,
        out double observedMilliseconds,
        out double wallWaitMilliseconds)
    {
        observedMilliseconds = 0.0;
        wallWaitMilliseconds = 0.0;

        if (targetMilliseconds <= 0)
        {
            return true;
        }

        var watch = Stopwatch.StartNew();
        var timeout = Math.Max(targetMilliseconds + 100, timeoutMilliseconds);

        while (watch.ElapsedMilliseconds < timeout)
        {
            if (TryGetProgressMilliseconds(out observedMilliseconds) &&
                observedMilliseconds >= targetMilliseconds)
            {
                wallWaitMilliseconds = watch.Elapsed.TotalMilliseconds;
                return true;
            }

            Thread.Sleep(2);
        }

        _ = TryGetProgressMilliseconds(out observedMilliseconds);
        wallWaitMilliseconds = watch.Elapsed.TotalMilliseconds;
        return false;
    }

    internal static bool TryGetProgressMilliseconds(
        out double milliseconds)
    {
        lock (Gate)
        {
            return TryGetProgressMillisecondsLocked(out milliseconds);
        }
    }

    internal static bool Stop()
    {
        lock (Gate)
        {
            return StopLocked();
        }
    }

    internal static string? ActiveWave
    {
        get
        {
            lock (Gate)
            {
                return _activeWave;
            }
        }
    }

    private static bool TryGetProgressMillisecondsLocked(
        out double milliseconds)
    {
        milliseconds = 0.0;

        if (_waveOut == 0)
        {
            return false;
        }

        var time = new MmTime
        {
            Type = TimeSamples,
            Value = 0,
            Value2 = 0,
        };

        var result = waveOutGetPosition(
            _waveOut,
            ref time,
            checked((uint)Marshal.SizeOf<MmTime>()));

        if (result != MmNoError)
        {
            return false;
        }

        switch (time.Type)
        {
            case TimeSamples when _sampleRate != 0:
                milliseconds =
                    time.Value * 1000.0 / _sampleRate;
                return true;

            case TimeMs:
                milliseconds = time.Value;
                return true;

            case TimeBytes when _avgBytesPerSecond != 0:
                milliseconds =
                    time.Value * 1000.0 / _avgBytesPerSecond;
                return true;

            default:
                return false;
        }
    }

    private static bool StopLocked()
    {
        var hadDevice = _waveOut != 0;

        if (_waveOut != 0)
        {
            try
            {
                _ = waveOutReset(_waveOut);
            }
            catch
            {
            }

            if (_prepared && _header != 0)
            {
                try
                {
                    _ = waveOutUnprepareHeader(
                        _waveOut,
                        _header,
                        checked((uint)_headerSize));
                }
                catch
                {
                }
            }

            try
            {
                _ = waveOutClose(_waveOut);
            }
            catch
            {
            }
        }

        if (_header != 0)
        {
            try
            {
                Marshal.FreeHGlobal(_header);
            }
            catch
            {
            }
        }

        if (_data != 0)
        {
            try
            {
                Marshal.FreeHGlobal(_data);
            }
            catch
            {
            }
        }

        _waveOut = 0;
        _data = 0;
        _header = 0;
        _headerSize = 0;
        _prepared = false;
        _sampleRate = 0;
        _avgBytesPerSecond = 0;
        _activeWave = null;
        return hadDevice;
    }

    private static bool TryParsePcmWave(
        byte[] wave,
        out WaveFormatEx format,
        out int dataOffset,
        out int dataLength,
        out string detail)
    {
        format = default;
        dataOffset = 0;
        dataLength = 0;
        detail = string.Empty;

        if (wave.Length < 44 ||
            wave[0] != (byte)'R' ||
            wave[1] != (byte)'I' ||
            wave[2] != (byte)'F' ||
            wave[3] != (byte)'F' ||
            wave[8] != (byte)'W' ||
            wave[9] != (byte)'A' ||
            wave[10] != (byte)'V' ||
            wave[11] != (byte)'E')
        {
            detail = "invalid-riff-wave";
            return false;
        }

        var foundFormat = false;
        var foundData = false;
        var offset = 12;

        while (offset + 8 <= wave.Length)
        {
            var chunkSize =
                BinaryPrimitives.ReadUInt32LittleEndian(
                    wave.AsSpan(offset + 4, 4));

            var payload = offset + 8;
            var available = wave.Length - payload;
            if (chunkSize > int.MaxValue ||
                chunkSize > (uint)Math.Max(available, 0))
            {
                detail = "invalid-chunk-size";
                return false;
            }

            var size = checked((int)chunkSize);
            var isFmt =
                wave[offset] == (byte)'f' &&
                wave[offset + 1] == (byte)'m' &&
                wave[offset + 2] == (byte)'t' &&
                wave[offset + 3] == (byte)' ';

            var isData =
                wave[offset] == (byte)'d' &&
                wave[offset + 1] == (byte)'a' &&
                wave[offset + 2] == (byte)'t' &&
                wave[offset + 3] == (byte)'a';

            if (isFmt)
            {
                if (size < 16)
                {
                    detail = "fmt-too-small";
                    return false;
                }

                var span = wave.AsSpan(payload, size);
                format = new WaveFormatEx
                {
                    FormatTag =
                        BinaryPrimitives.ReadUInt16LittleEndian(span.Slice(0, 2)),
                    Channels =
                        BinaryPrimitives.ReadUInt16LittleEndian(span.Slice(2, 2)),
                    SamplesPerSec =
                        BinaryPrimitives.ReadUInt32LittleEndian(span.Slice(4, 4)),
                    AvgBytesPerSec =
                        BinaryPrimitives.ReadUInt32LittleEndian(span.Slice(8, 4)),
                    BlockAlign =
                        BinaryPrimitives.ReadUInt16LittleEndian(span.Slice(12, 2)),
                    BitsPerSample =
                        BinaryPrimitives.ReadUInt16LittleEndian(span.Slice(14, 2)),
                    ExtraSize = 0,
                };
                foundFormat = true;
            }
            else if (isData)
            {
                dataOffset = payload;
                dataLength = size;
                foundData = true;
            }

            var padded = size + (size & 1);
            if (payload > int.MaxValue - padded)
            {
                detail = "chunk-offset-overflow";
                return false;
            }

            offset = payload + padded;

            if (foundFormat && foundData)
            {
                break;
            }
        }

        if (!foundFormat || !foundData)
        {
            detail = "fmt-or-data-missing";
            return false;
        }

        if (format.FormatTag != 1 ||
            format.Channels == 0 ||
            format.SamplesPerSec == 0 ||
            format.AvgBytesPerSec == 0 ||
            format.BlockAlign == 0 ||
            format.BitsPerSample == 0 ||
            dataLength <= 0)
        {
            detail =
                $"unsupported-wave tag={format.FormatTag} " +
                $"channels={format.Channels} rate={format.SamplesPerSec} " +
                $"bits={format.BitsPerSample}";
            return false;
        }

        return true;
    }

    [DllImport("winmm.dll")]
    private static extern uint waveOutOpen(
        out nint waveOut,
        uint deviceId,
        ref WaveFormatEx format,
        nint callback,
        nint instance,
        uint flags);

    [DllImport("winmm.dll")]
    private static extern uint waveOutPrepareHeader(
        nint waveOut,
        nint header,
        uint headerSize);

    [DllImport("winmm.dll")]
    private static extern uint waveOutUnprepareHeader(
        nint waveOut,
        nint header,
        uint headerSize);

    [DllImport("winmm.dll")]
    private static extern uint waveOutWrite(
        nint waveOut,
        nint header,
        uint headerSize);

    [DllImport("winmm.dll")]
    private static extern uint waveOutPause(nint waveOut);

    [DllImport("winmm.dll")]
    private static extern uint waveOutRestart(nint waveOut);

    [DllImport("winmm.dll")]
    private static extern uint waveOutReset(nint waveOut);

    [DllImport("winmm.dll")]
    private static extern uint waveOutClose(nint waveOut);

    [DllImport("winmm.dll")]
    private static extern uint waveOutGetPosition(
        nint waveOut,
        ref MmTime time,
        uint timeSize);
}


