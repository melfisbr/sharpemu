// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Diagnostics;
using SharpEmu.HLE.Host;

namespace SharpEmu.Libs.Media;

internal interface IMediaFrameDecoder : IDisposable
{
    uint Width { get; }

    uint Height { get; }

    uint FramesPerSecondNumerator { get; }

    uint FramesPerSecondDenominator { get; }

    bool TryDecodeNextFrame(Span<byte> destination);
}

// SHARPEMU_V74_0_105_UI_BINK_DIRECT_YUV
// Preserve NIHAV's native YUV420 representation through the playback ring.
// This removes the 1080p YUV->BGRA->YUV round-trip that cost ~65 ms/frame.
internal enum MediaFramePixelLayout
{
    Bgra32 = 0,
    Nv12 = 1,
}

internal interface IMediaFramePixelLayoutSource
{
    MediaFramePixelLayout PixelLayout { get; }
}

// SHARPEMU_BINK_NATIVE_PLAYBACK_CLOCK_V75_0_0
internal interface IMediaPlaybackClockSource
{
    bool TryGetPlaybackSeconds(out double seconds);
}

internal interface IMediaFrameBufferPolicy
{
    int PreferredBufferCount { get; }

    bool PrimeFirstFrameSynchronously { get; }
}

/// <summary>
/// Keeps blocking codec work away from the Vulkan presentation thread and
/// releases decoded frames according to the movie time base.
/// </summary>
internal sealed class MediaFramePlayback : IDisposable
{
    private const int BufferCount = 5;

    private readonly object _gate = new();
    private readonly IMediaFrameDecoder _decoder;
    private readonly IMediaPlaybackClockSource? _playbackClockSource;
    private readonly IMediaFrameBufferPolicy? _bufferPolicy;
    private readonly Queue<byte[]> _freeBuffers = new();
    private readonly Queue<DecodedFrame> _decodedFrames = new();
    // SHARPEMU_V74_0_110_UI_BINK_TIME_AWARE_RESERVOIR
    private readonly bool _dropStaleDecodedFramesOnProducerPressure;
    private long _v74110ProducerDropTraceCount;
    private readonly Thread _decoderThread;
    private byte[]? _currentFrame;
    private byte[]? _retiredFrame;
    private long _currentFrameIndex = -1;
    private long _nextDecodedFrameIndex;
    private long _playbackStartTimestamp;
    private double _audioStartSeconds;
    private long _lastSkewTraceTimestamp;
    private bool _playbackClockStarted;
    private bool _decoderCompleted;
    private bool _stopRequested;
    private bool _finished;
    private int _disposed;

    internal MediaFramePlayback(IMediaFrameDecoder decoder)
    {
        _decoder = decoder;
        _playbackClockSource =
            decoder as IMediaPlaybackClockSource;
        _bufferPolicy =
            decoder as IMediaFrameBufferPolicy;
        PixelLayout =
            (decoder as IMediaFramePixelLayoutSource)?.PixelLayout ??
            MediaFramePixelLayout.Bgra32;
        // SHARPEMU_V74_0_110_UI_BINK_TIME_AWARE_RESERVOIR
        // Once playback has started, a decoded frame older than the wall-clock
        // target can never be shown. Recycle that stale queued buffer on the
        // producer thread instead of blocking until the next 0.7-3 FPS guest
        // flip. This keeps a 30 FPS Bink timeline current without decoding
        // arbitrarily far into the future.
        var realtimeDropSettingV74110 =
            Environment.GetEnvironmentVariable(
                "SHARPEMU_DS_UI_BINK_REALTIME_DROP_STALE");
        _dropStaleDecodedFramesOnProducerPressure =
            PixelLayout == MediaFramePixelLayout.Nv12 &&
            decoder is NihavBink2Decoder &&
            !string.Equals(
                realtimeDropSettingV74110,
                "0",
                StringComparison.OrdinalIgnoreCase) &&
            !string.Equals(
                realtimeDropSettingV74110,
                "false",
                StringComparison.OrdinalIgnoreCase);
        Width = decoder.Width;
        Height = decoder.Height;
        FramesPerSecondNumerator = decoder.FramesPerSecondNumerator;
        FramesPerSecondDenominator = decoder.FramesPerSecondDenominator;

        // V61.19.0_NIHAV_WALLCLOCK_DEFAULT
        // A host-decoded NIHAV movie does not own the global guest AudioOut
        // clock. Following that unrelated clock made Demon's Souls video slow
        // down whenever guest audio advanced irregularly. Explicit
        // SHARPEMU_MOVIE_CLOCK=audio still opts back into audio-clock pacing.
        var configuredClock = Environment.GetEnvironmentVariable("SHARPEMU_MOVIE_CLOCK");
        _followGuestAudioClock =
            _playbackClockSource is null &&
            (string.Equals(
                 configuredClock,
                 "audio",
                 StringComparison.OrdinalIgnoreCase) ||
             (string.IsNullOrWhiteSpace(configuredClock) &&
              decoder is not NihavBink2Decoder));

        var frameBytes = PixelLayout == MediaFramePixelLayout.Nv12
            ? checked((int)((ulong)Width * Height * 3 / 2))
            : checked((int)((ulong)Width * Height * 4));
        // SHARPEMU_V74_0_109_UI_BINK_REALTIME_RESERVOIR
        // The old five-buffer ring can hold only ~100 ms of 30-fps video once
        // current/retired frames are accounted for. At 2-3 guest presents per
        // second it starves the decoder before the next composite, forcing the
        // title loop to play in slow motion. NV12 makes a one-second reservoir
        // inexpensive (~100 MiB at 1080p) and lets TryGetFrame drop directly to
        // the wall-clock frame on every guest composite.
        var defaultBufferCountV74109 =
            PixelLayout == MediaFramePixelLayout.Nv12 &&
            decoder is NihavBink2Decoder
                ? 32
                : BufferCount;
        var configuredBufferCountV74109 =
            Environment.GetEnvironmentVariable(
                "SHARPEMU_DS_UI_BINK_FRAME_BUFFERS");
        if (int.TryParse(configuredBufferCountV74109, out var parsedV74109))
        {
            defaultBufferCountV74109 = Math.Clamp(parsedV74109, 5, 48);
        }

        var bufferCount = Math.Clamp(
            _bufferPolicy?.PreferredBufferCount ?? defaultBufferCountV74109,
            2,
            48);

        Console.Error.WriteLine(
            "[BINK-NATIVE][V75.0.0] playback_buffers " +
            $"decoder={decoder.GetType().Name} count={bufferCount} " +
            $"layout={PixelLayout} realtime_reservoir_v109=" +
            $"{(PixelLayout == MediaFramePixelLayout.Nv12)}");

        for (var index = 0; index < bufferCount; index++)
        {
            _freeBuffers.Enqueue(GC.AllocateUninitializedArray<byte>(frameBytes));
        }

        // SHARPEMU_V73_19_1_NIHAV_FIRST_FRAME_PRIME 
        // Nihav TryOpen already waits for the streaming process to produce a 
        // complete first frame. Publish one frame synchronously before the 
        // presenter can observe an empty playback queue. 
        if ((decoder is NihavBink2Decoder ||
             _bufferPolicy?.PrimeFirstFrameSynchronously == true) &&
            _freeBuffers.Count > 0) 
        { 
            var firstBuffer = _freeBuffers.Dequeue(); 
            try 
            { 
                if (_decoder.TryDecodeNextFrame(firstBuffer)) 
                { 
                    var firstIndex = _nextDecodedFrameIndex++; 
                    _decodedFrames.Enqueue(new DecodedFrame(firstIndex, firstBuffer)); 
                    Console.Error.WriteLine( 
                        $"[LOADER][INFO] bink2.first_frame_primed " + 
                        $"size={Width}x{Height} frame={firstIndex}"); 
                } 
                else 
                { 
                    _freeBuffers.Enqueue(firstBuffer); 
                } 
            } 
            catch 
            { 
                _freeBuffers.Enqueue(firstBuffer); 
                throw; 
            } 
        } 
        _decoderThread = new Thread(DecodeLoop)
        {
            IsBackground = true,
            Name = "SharpEmu Bink video decoder",
        };
        _decoderThread.Start();
    }

    internal uint Width { get; }

    internal uint Height { get; }

    internal MediaFramePixelLayout PixelLayout { get; }

    internal uint FramesPerSecondNumerator { get; }

    internal uint FramesPerSecondDenominator { get; }

    internal bool IsFinished
    {
        get
        {
            lock (_gate)
            {
                return _finished;
            }
        }
    }

    /// <summary>
    /// Wall-clock seconds since the first frame was presented, and the index of
    /// the last frame shown. Playback is on its own time base when these agree
    /// with the movie's frame rate.
    /// </summary>
    internal (double Seconds, long FrameIndex) PlaybackProgress
    {
        get
        {
            lock (_gate)
            {
                return (
                    _playbackClockStarted
                        ? CurrentPlaybackSecondsLocked()
                        : 0,
                    _currentFrameIndex);
            }
        }
    }

    internal bool TryGetFrame(
        bool advanceClock,
        out byte[] pixels,
        out bool advanced)
    {
        lock (_gate)
        {
            pixels = [];
            advanced = false;
            if (_finished)
            {
                return false;
            }

            if (_currentFrame is null)
            {
                if (_decodedFrames.Count == 0)
                {
                    if (_decoderCompleted)
                    {
                        _finished = true;
                    }
                    return false;
                }

                var first = _decodedFrames.Dequeue();
                _currentFrame = first.Pixels;
                _currentFrameIndex = first.Index;
                advanced = true;
                Monitor.PulseAll(_gate);
            }

            if (advanceClock && !_playbackClockStarted)
            {
                _playbackStartTimestamp = Stopwatch.GetTimestamp();
                _audioStartSeconds = GuestAudioClock.PlayedSeconds;
                _playbackClockStarted = true;
            }

            var elapsedSeconds = CurrentPlaybackSecondsLocked();
            TraceClockSkewLocked();
            var targetFrameIndex = CurrentTargetFrameIndexLocked();
            DecodedFrame? replacement = null;
            while (_decodedFrames.Count > 0 &&
                   _decodedFrames.Peek().Index <= targetFrameIndex)
            {
                if (replacement is { } skipped)
                {
                    _freeBuffers.Enqueue(skipped.Pixels);
                }
                replacement = _decodedFrames.Dequeue();
            }

            if (replacement is { } next)
            {
                if (_retiredFrame is not null)
                {
                    _freeBuffers.Enqueue(_retiredFrame);
                }
                _retiredFrame = _currentFrame;
                _currentFrame = next.Pixels;
                _currentFrameIndex = next.Index;
                advanced = true;
                Monitor.PulseAll(_gate);
            }

            var frameDurationSeconds =
                (double)FramesPerSecondDenominator / FramesPerSecondNumerator;
            if (_playbackClockStarted &&
                _decoderCompleted &&
                _decodedFrames.Count == 0 &&
                elapsedSeconds >= (_currentFrameIndex + 1) * frameDurationSeconds)
            {
                _finished = true;
                return false;
            }

            pixels = _currentFrame;
            return true;
        }
    }

    /// <summary>
    /// Time base for playback. A host-decoded movie runs on whatever clock it is
    /// given, but the audio that belongs to it comes from the guest, which does
    /// not advance at wall-clock rate on a slow frame. Following the audio keeps
    /// the two together; SHARPEMU_MOVIE_CLOCK=wall restores the old behaviour.
    /// </summary>
    private readonly bool _followGuestAudioClock;

    /// <summary>
    /// Seconds of playback elapsed on the movie's time base. Falls back to wall
    /// clock whenever guest audio is not flowing: a movie whose audio never
    /// starts â€” or stops early â€” must still finish rather than hang on a clock
    /// that will never advance again.
    /// </summary>
    private double CurrentPlaybackSecondsLocked()
    {
        if (!_playbackClockStarted)
        {
            return 0;
        }
        if (_playbackClockSource is not null &&
            _playbackClockSource.TryGetPlaybackSeconds(
                out var sourceSeconds) &&
            double.IsFinite(sourceSeconds) &&
            sourceSeconds >= 0)
        {
            return sourceSeconds;
        }

        var wallSeconds = Stopwatch.GetElapsedTime(_playbackStartTimestamp).TotalSeconds;
        if (!_followGuestAudioClock || !GuestAudioClock.IsRunning)
        {
            return wallSeconds;
        }

        return Math.Clamp(GuestAudioClock.PlayedSeconds - _audioStartSeconds, 0, wallSeconds);
    }

    private static readonly bool _traceClockSkew = string.Equals(
        Environment.GetEnvironmentVariable("SHARPEMU_LOG_MOVIE_SYNC"),
        "1",
        StringComparison.Ordinal);

    /// <summary>
    /// Logs how far the movie's wall clock has drifted from the guest audio the
    /// movie is supposed to be in step with. A skew that is flat across playback
    /// is a late audio start; one that grows is a rate mismatch, and the two need
    /// different fixes. Caller holds <see cref="_gate"/>.
    /// </summary>
    private void TraceClockSkewLocked()
    {
        if (!_traceClockSkew || !_playbackClockStarted)
        {
            return;
        }

        var now = Stopwatch.GetTimestamp();
        if (_lastSkewTraceTimestamp != 0 &&
            Stopwatch.GetElapsedTime(_lastSkewTraceTimestamp) < TimeSpan.FromSeconds(1))
        {
            return;
        }

        _lastSkewTraceTimestamp = now;
        var wallSeconds = Stopwatch.GetElapsedTime(_playbackStartTimestamp).TotalSeconds;
        var audioSeconds = GuestAudioClock.PlayedSeconds - _audioStartSeconds;
        Console.Error.WriteLine(
            $"[PERF][MOVIE] wall_s={wallSeconds:F2} audio_s={audioSeconds:F2} " +
            $"playback_s={CurrentPlaybackSecondsLocked():F2} " +
            $"skew_s={wallSeconds - audioSeconds:F2} frame={_currentFrameIndex} " +
            $"audio_running={GuestAudioClock.IsRunning}");
    }

    /// <summary>
    /// The frame the movie's own time base says should be on screen right now.
    /// Returns -1 until the first frame is presented, so the queue prefills
    /// instead of instantly declaring everything late.
    /// </summary>
    private long CurrentTargetFrameIndexLocked() =>
        _playbackClockStarted
            ? (long)Math.Floor(
                CurrentPlaybackSecondsLocked() *
                FramesPerSecondNumerator / FramesPerSecondDenominator)
            : -1;

    private void DecodeLoop()
    {
        try
        {
            while (true)
            {
                byte[]? destination = null;
                lock (_gate)
                {
                    while (!_stopRequested && _freeBuffers.Count == 0)
                    {
                        // SHARPEMU_V74_0_110_UI_BINK_TIME_AWARE_RESERVOIR
                        // Do not blindly discard the oldest reservoir entry: a
                        // fast decoder could otherwise run to EOF long before
                        // presentation catches up. Reclaim only frames that
                        // are already behind the movie wall-clock target.
                        var targetFrameIndex = CurrentTargetFrameIndexLocked();
                        if (_dropStaleDecodedFramesOnProducerPressure &&
                            _playbackClockStarted &&
                            _decodedFrames.Count > 0 &&
                            _decodedFrames.Peek().Index < targetFrameIndex)
                        {
                            var stale = _decodedFrames.Dequeue();
                            destination = stale.Pixels;
                            var dropCount = ++_v74110ProducerDropTraceCount;
                            if (dropCount <= 16 ||
                                (dropCount & (dropCount - 1)) == 0)
                            {
                                Console.Error.WriteLine(
                                    "[V74.0.110][UI_BINK_RESERVOIR_DROP] " +
                                    $"count={dropCount} dropped={stale.Index} " +
                                    $"target={targetFrameIndex} queued={_decodedFrames.Count} " +
                                    "policy=stale-only producer_block_avoided=True");
                            }
                            break;
                        }

                        // Wake periodically so the producer observes wall-clock
                        // progress even if the guest cannot present another
                        // frame for hundreds of milliseconds.
                        Monitor.Wait(_gate, TimeSpan.FromMilliseconds(2));
                    }
                    if (_stopRequested)
                    {
                        return;
                    }
                    destination ??= _freeBuffers.Dequeue();
                }

                if (!_decoder.TryDecodeNextFrame(destination))
                {
                    lock (_gate)
                    {
                        _freeBuffers.Enqueue(destination);
                        _decoderCompleted = true;
                        Monitor.PulseAll(_gate);
                    }
                    return;
                }

                lock (_gate)
                {
                    var frameIndex = _nextDecodedFrameIndex++;

                    // Frames are pulled once per guest flip, so a title running
                    // well under the movie's frame rate cannot drain a queue
                    // this shallow fast enough and the movie stretches past its
                    // real duration â€” audio finishes while the last picture sits
                    // on screen and the next movie starts late. Once the clock
                    // has passed a queued frame it can never be shown, so retire
                    // it in favour of this newer one. Only superseded frames are
                    // dropped, never the newest, so a decoder that cannot keep
                    // up still advances the picture instead of freezing it.
                    var targetFrameIndex = CurrentTargetFrameIndexLocked();
                    if (frameIndex <= targetFrameIndex)
                    {
                        while (_decodedFrames.Count > 0 &&
                               _decodedFrames.Peek().Index <= targetFrameIndex)
                        {
                            _freeBuffers.Enqueue(_decodedFrames.Dequeue().Pixels);
                        }
                    }

                    _decodedFrames.Enqueue(new DecodedFrame(frameIndex, destination));
                    Monitor.PulseAll(_gate);
                }
            }
        }
        catch (Exception exception) when (exception is IOException or
                                             InvalidOperationException)
        {
            Console.Error.WriteLine(
                $"[LOADER][WARN] Bink decoder stopped: {exception.Message}");
            lock (_gate)
            {
                _decoderCompleted = true;
                Monitor.PulseAll(_gate);
            }
        }
    }

    public void Dispose()
    {
        if (Interlocked.Exchange(ref _disposed, 1) != 0)
        {
            return;
        }

        lock (_gate)
        {
            _stopRequested = true;
            Monitor.PulseAll(_gate);
        }
        if (Thread.CurrentThread != _decoderThread &&
            !_decoderThread.Join(TimeSpan.FromMilliseconds(100)))
        {
            _decoder.Dispose();
            _decoderThread.Join(TimeSpan.FromSeconds(2));
        }
        else
        {
            _decoder.Dispose();
        }
    }

    private readonly record struct DecodedFrame(long Index, byte[] Pixels);
}

