// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;

namespace SharpEmu.Libs.Media;

/// <summary>
/// V72.4.3.2.31.7.7: RAD playback through the SharpEmu embedded-host API with a shared host media-clock anchor for zero-track attract audio.
///
/// V72.4.3.2.31.7.7 preserves the V31.7.6 real decoder
/// lifecycle. V31.7.5 only called compatibility shims
/// (OnMovieFrame/EndMovieSession), which are no-ops in the accumulated checkout;
/// therefore HighGraphics/Core.Res.TaskManager kept running behind the 4K attract
/// movie. The V72.4.3.2.14 lifecycle hooks already pair
/// NotifyHostMovieDecoderStarted/Stopped with HostMovieExecutionGateV7243214
/// Begin/End, so this bridge calls the lifecycle exactly once and does not
/// double-increment the HLE gate. The heartbeat is diagnostic only.
/// </summary>
internal sealed class RadBinkExternalPlaybackV7243231 : IDisposable
{
    private readonly Process _process;
    private readonly IRadBinkHostApi _hostApi;
    private readonly Stopwatch _elapsed = Stopwatch.StartNew();
    private readonly bool _usesSharpEmuAttractAudio;
    private readonly Timer? _guestThrottleHeartbeatTimer;
    private readonly bool _guestThrottleStarted;
    private int _guestThrottleHeartbeatCount;
    private int _guestThrottleReleased;
    private bool _disposed;

    private readonly record struct BinkHeaderMetadata(
        uint FrameCount,
        uint Width,
        uint Height,
        uint FpsNumerator,
        uint FpsDenominator,
        uint[] AudioTrackIds)
    {
        internal double DurationMilliseconds =>
            FrameCount > 0 && FpsNumerator > 0 && FpsDenominator > 0
                ? FrameCount * 1000.0 * FpsDenominator / FpsNumerator
                : 0.0;
    }

    private RadBinkExternalPlaybackV7243231(
        Process process,
        IRadBinkHostApi hostApi,
        string toolPath,
        string moviePath,
        int audioTrackCount,
        uint[] audioTrackIds,
        bool usesSharpEmuAttractAudio,
        bool guestThrottleStarted)
    {
        _process = process;
        _hostApi = hostApi;
        ToolPath = toolPath;
        MoviePath = moviePath;
        AudioTrackCount = audioTrackCount;
        AudioTrackIds = audioTrackIds;
        _usesSharpEmuAttractAudio = usesSharpEmuAttractAudio;
        _guestThrottleStarted = guestThrottleStarted;

        if (guestThrottleStarted)
        {
            var heartbeatMs = ResolveIntEnvironment(
                "SHARPEMU_RAD_GUEST_THROTTLE_HEARTBEAT_MS",
                defaultValue: 200,
                minimum: 50,
                maximum: 1_000);

            _guestThrottleHeartbeatTimer = new Timer(
                static state =>
                {
                    if (state is RadBinkExternalPlaybackV7243231 playback)
                    {
                        playback.PulseGuestMovieThrottle();
                    }
                },
                this,
                dueTime: heartbeatMs,
                period: heartbeatMs);
        }
    }

    internal string ToolPath { get; }
    internal string MoviePath { get; }
    internal int AudioTrackCount { get; }
    internal IReadOnlyList<uint> AudioTrackIds { get; }
    internal bool UsesSharpEmuAttractAudio => _usesSharpEmuAttractAudio;
    internal bool IsEmbedded => _hostApi.IsEmbedded;
    internal double ElapsedSeconds => _elapsed.Elapsed.TotalSeconds;

    internal bool IsFinished =>
        _disposed || _hostApi.IsPlaybackFinished;

    internal int? ExitCode =>
        _disposed ? null : _hostApi.PlaybackExitCode;

    internal static bool TryStart(
        string moviePath,
        out RadBinkExternalPlaybackV7243231? playback)
    {
        playback = null;

        if (!OperatingSystem.IsWindows() ||
            string.IsNullOrWhiteSpace(moviePath) ||
            !File.Exists(moviePath))
        {
            return false;
        }

        var toolPath = ResolveToolPath();
        if (string.IsNullOrWhiteSpace(toolPath) ||
            !File.Exists(toolPath))
        {
            Console.Error.WriteLine(
                "[LOADER][ERROR] bink2.rad_required_missing " +
                "SHARPEMU_RADVIDEO64/radvideo64.path does not resolve.");
            return false;
        }

        var fileName = Path.GetFileName(moviePath);
        var interactiveRadUiV111 =
            HostMovieBridge.IsDemonSoulsUiBinkCompositePathV740841(moviePath) &&
            !string.Equals(
                Environment.GetEnvironmentVariable(
                    "SHARPEMU_DS_UI_BINK_RAD_INTERACTIVE"),
                "0",
                StringComparison.Ordinal);

        // V31.7.18_BINK_EMBEDDED_ATTRACT_AUDIO
        // When possible, play a cache-only BK2 produced by RAD binkmix with the
        // audited sample-exact attract WAV.  Keep moviePath as the logical game
        // path so lifecycle/queue ownership remains unchanged.
        var playbackMoviePath = moviePath;
        var usesBinkEmbeddedAttractAudio = false;

        if (string.Equals(
                fileName,
                "attract_movie.bk2",
                StringComparison.OrdinalIgnoreCase) &&
            Environment.GetEnvironmentVariable(
                "SHARPEMU_DS_ATTRACT_EMBED_AUDIO") != "0")
        {
            if (BinkDemonSoulsIntroAudioV7243227
                    .TryGetPreparedAttractWaveForBinkMix(
                        moviePath,
                        timeoutMilliseconds: 180_000,
                        out var exactWave) &&
                exactWave is not null &&
                DemonSoulsAttractBinkMuxV31718.TryGetOrCreate(
                    toolPath,
                    moviePath,
                    exactWave,
                    out var cachedMovie,
                    out var muxInfo))
            {
                playbackMoviePath = cachedMovie;
                usesBinkEmbeddedAttractAudio = true;

                Console.Error.WriteLine(
                    "[LOADER][INFO] bink2.ds_attract_embedded_audio_ready " +
                    "file='attract_movie.bk2' " +
                    $"cached='{cachedMovie}' tracks={muxInfo.AudioTrackIds.Length} " +
                    $"ids='{string.Join(";", muxInfo.AudioTrackIds)}' " +
                    "sidecar=False clock=bink-frame-audio-stream");
            }
            else
            {
                Console.Error.WriteLine(
                    "[LOADER][WARN] bink2.ds_attract_embedded_audio_fallback " +
                    "file='attract_movie.bk2' fallback=external-sidecar");
            }
        }

        var headerKnown = TryReadBinkHeaderMetadata(
            playbackMoviePath,
            out var metadata);
        var audioTrackIds = headerKnown
            ? metadata.AudioTrackIds
            : Array.Empty<uint>();
        var audioTrackCount = headerKnown ? audioTrackIds.Length : -1;
        var nominalDurationMilliseconds = headerKnown
            ? metadata.DurationMilliseconds
            : 0.0;

        Console.Error.WriteLine(
            "[LOADER][INFO] bink2.rad_audio_header " +
            $"file='{fileName}' known={headerKnown} " +
            $"tracks={audioTrackCount} " +
            $"ids='{(headerKnown ? string.Join(";", audioTrackIds) : "unknown")}' " +
            $"frames={(headerKnown ? metadata.FrameCount : 0)} " +
            $"fps={(headerKnown ? metadata.FpsNumerator : 0)}/{(headerKnown ? metadata.FpsDenominator : 0)} " +
            $"duration_ms={nominalDurationMilliseconds:F1}");

        if (string.Equals(
                fileName,
                "ps_studios_logo.bk2",
                StringComparison.OrdinalIgnoreCase))
        {
            Environment.SetEnvironmentVariable(
                "SHARPEMU_DS_ATTRACT_AUDIO_TEMPO",
                "1.0000");
            _ = BinkDemonSoulsIntroAudioV7243227.PrepareAttach(moviePath);
            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.rad_attract_audio_prewarm " +
                "tempo=1.0000 source=external-at9-stems");
        }

        Process? process = null;
        IRadBinkHostApi? hostApi = null;
        IReadOnlySet<int>? radProcessesBeforeLaunch = null;
        var guestThrottleStarted = false;
        var usesSharpEmuAttractAudio = false;
        Action<double>? beforeReveal = null;

        try
        {
            var windowsBeforeLaunch =
                RadBinkEmbeddedHostApiV724323171
                    .CaptureTopLevelWindowSnapshot();
            radProcessesBeforeLaunch =
                RadBinkEmbeddedHostApiV724323171
                    .CaptureRadProcessSnapshot();

            var start = new ProcessStartInfo
            {
                FileName = toolPath,
                WorkingDirectory =
                    Path.GetDirectoryName(toolPath) ??
                    AppContext.BaseDirectory,
                UseShellExecute = false,
                // V31.7.20_STARTUP_HIDDEN_PLAYER
                // STARTF_USESHOWWINDOW/SW_HIDE is applied before the first HWND
                // becomes visible. The host API has a hidden-HWND discovery path
                // so embedding no longer depends on desktop visibility.
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden,
            };

            start.ArgumentList.Add("binkplay");
            start.ArgumentList.Add(playbackMoviePath);
            // /I2 = no player caption/non-client chrome.  /Z0 forces Windows
            // Audio.  When Bink audio tracks exist, select them explicitly in
            // track-index order so embedding cannot inherit a silent default.
            start.ArgumentList.Add("/I2");
            // SHARPEMU_V74_0_111_RAD_INTERACTIVE_LOOP
            if (interactiveRadUiV111)
            {
                start.ArgumentList.Add("/L");
                Console.Error.WriteLine(
                    "[V74.0.111][RAD_INTERACTIVE_LOOP] " +
                    $"file='{fileName}' loop=rad-infinite transition_owner=guest");
            }
            // V31.7.18: Win Audio/WASAPI is RAD's default output. Do not force
            // /Z0; this also restores the single embedded audio track path used
            // by ps_studios_logo.

            string? trackSwitch = null;

            if (headerKnown && audioTrackIds.Length == 1)
            {
                // One embedded track needs no selection override. Let the RAD
                // player use its default Windows Audio path.
                Console.Error.WriteLine(
                    "[LOADER][INFO] bink2.rad_audio_policy " +
                    $"file='{fileName}' tracks=1 " +
                    $"id={audioTrackIds[0]} policy=rad-default-single-track " +
                    "explicit_switch=False output=rad-default-windows-audio");
            }
            else if (headerKnown && audioTrackIds.Length > 1)
            {
                var builder = new StringBuilder("/T");
                for (var index = 0; index < audioTrackIds.Length; index++)
                {
                    if (index > 0)
                    {
                        builder.Append(';');
                    }

                    // /T takes Bink track IDs.  The old bridge used array
                    // indices, which is wrong whenever ids are non-contiguous.
                    builder.Append(audioTrackIds[index]);
                }

                trackSwitch = builder.ToString();
                start.ArgumentList.Add(trackSwitch);

                Console.Error.WriteLine(
                    "[LOADER][INFO] bink2.rad_audio_track_select " +
                    $"file='{fileName}' switch='{trackSwitch}' " +
                    "policy=explicit-actual-track-ids output=rad-default-windows-audio");
            }
            else
            {
                Console.Error.WriteLine(
                    "[LOADER][INFO] bink2.rad_audio_policy " +
                    $"file='{fileName}' tracks={audioTrackCount} " +
                    "policy=no-embedded-audio explicit_switch=False");
            }
            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.rad_command " +
                "syntax='radvideo64.exe binkplay <movie> /I2 [/T<actual-id>...]' " +
                $"file='{fileName}'");

            process = new Process
            {
                StartInfo = start,
                EnableRaisingEvents = true,
            };

            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.rad_startup_hidden " +
                $"file='{fileName}' window_style=Hidden " +
                "create_no_window=True preparent_visibility=forbidden");

            if (string.Equals(
                    fileName,
                    "attract_movie.bk2",
                    StringComparison.OrdinalIgnoreCase))
            {
                Console.Error.WriteLine(
                    "[V31.7.20][ATTRACT_RAD_LAUNCH] " +
                    $"utc='{DateTime.UtcNow:O}' " +
                    $"mono_ticks={System.Diagnostics.Stopwatch.GetTimestamp()} " +
                    "startup_hidden=True");
            }
            if (!process.Start())
            {
                process.Dispose();
                return false;
            }

            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.rad_required_started " +
                $"pid={process.Id} file='{fileName}' " +
                $"tool='{toolPath}'");
            if (usesBinkEmbeddedAttractAudio)
            {
                Console.Error.WriteLine(
                    "[LOADER][INFO] bink2.rad_attract_embedded_audio_playback " +
                    "file='attract_movie.bk2' sidecar=False " +
                    $"playback_source='{playbackMoviePath}' " +
                    $"tracks={audioTrackIds.Length} " +
                    $"ids='{string.Join(";", audioTrackIds)}' " +
                    "audio_clock=bink-internal");
            }

            // V31.7.7: attract_movie has no embedded Bink audio track.  Prepare
            // the audited external AT9 mix now, but do not start it yet.  The
            // embedded-host API invokes beforeReveal at the RAD playback anchor
            // while the HWND is still hidden, then reveals the video immediately.
            if (headerKnown &&
                audioTrackIds.Length == 0 &&
                string.Equals(
                    fileName,
                    "attract_movie.bk2",
                    StringComparison.OrdinalIgnoreCase))
            {
                Environment.SetEnvironmentVariable(
                    "SHARPEMU_DS_ATTRACT_AUDIO_TEMPO",
                    "1.0000");

                var disposition =
                    BinkDemonSoulsIntroAudioV7243227.PrepareAttach(moviePath);

                usesSharpEmuAttractAudio =
                    disposition !=
                    BinkDemonSoulsIntroAudioV7243227
                        .AttachDisposition.NotHandled;

                if (usesSharpEmuAttractAudio)
                {
                    beforeReveal = anchorMs =>
                    {
                        var armed = BinkDemonSoulsIntroAudioV7243227
                            .NotifyPresentationArmed(moviePath);

                        Console.Error.WriteLine(
                            "[LOADER][INFO] bink2.rad_attract_audio_visible_frame_arm " +
                            "file='attract_movie.bk2' tracks=0 " +
                            "source=external-at9-stems offset_s=12.000 tempo=1.0000 " +
                            $"anchor_ms={anchorMs:F1} armed={armed} " +
                            "sync_source=visible-frame-audio-latch");
                    };
                }
                else
                {
                    Console.Error.WriteLine(
                        "[LOADER][WARN] bink2.rad_attract_audio_unavailable " +
                        "file='attract_movie.bk2' tracks=0");
                }
            }

            // Strict integrated-host policy: if we cannot turn the RAD window
            // into a SharpEmu child HWND, kill the player rather than leaving a
            // separate external window on the desktop.
            if (!RadBinkEmbeddedHostApiV724323171.TryAttach(
                    process,
                    windowsBeforeLaunch,
                    radProcessesBeforeLaunch!,
                    moviePath,
                    nominalDurationMilliseconds,
                    beforeReveal,
                    out var embeddedHost) ||
                embeddedHost is null)
            {
                TryKill(process);
                RadBinkEmbeddedHostApiV724323171
                    .KillSpawnedRadProcesses(radProcessesBeforeLaunch!);
                process.Dispose();
                Console.Error.WriteLine(
                    "[LOADER][ERROR] bink2.rad_embedded_host_required_failed " +
                    $"file='{fileName}' external_window_forbidden=True");
                return false;
            }

            hostApi = embeddedHost;

            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.rad_renderer_bound " +
                $"file='{fileName}' launcher_pid={process.Id} " +
                $"renderer_pid={embeddedHost.RendererProcessId} " +
                "window_discovery=pid-mainwindow-no-windowtext");

            // SHARPEMU_V74_0_111_RAD_INTERACTIVE_GUEST_LIVE
            if (interactiveRadUiV111)
            {
                Console.Error.WriteLine(
                    "[V74.0.111][RAD_INTERACTIVE_GUEST_LIVE] " +
                    $"file='{fileName}' hard_gate=False cpu_park=False " +
                    "gpu_payload_backpressure=False guest_input=True guest_scripts=True");
            }
            else
            {
                BeginGuestMovieThrottle(moviePath);
                guestThrottleStarted = true;
                Console.Error.WriteLine(
                    "[LOADER][INFO] bink2.rad_guest_work_throttle_begin " +
                    $"file='{fileName}' cpu_event_park=True gpu_payload_backpressure=True " +
                    "lifecycle=decoder-active hle_gate=True");
                Console.Error.WriteLine(
                    "[LOADER][INFO] bink2.rad_guest_hard_gate_started " +
                    $"file='{fileName}' active_decoder_lifecycle=True hle_execution_gate=True");
            }

            playback =
                new RadBinkExternalPlaybackV7243231(
                    process,
                    embeddedHost,
                    toolPath,
                    moviePath,
                    audioTrackCount,
                    audioTrackIds,
                    usesSharpEmuAttractAudio,
                    guestThrottleStarted);

            return true;
        }
        catch (Exception ex) when (
            ex is InvalidOperationException or
            System.ComponentModel.Win32Exception or
            IOException)
        {
            if (usesSharpEmuAttractAudio)
            {
                try
                {
                    BinkDemonSoulsIntroAudioV7243227.StopForMovie(moviePath);
                }
                catch
                {
                }
            }

            if (guestThrottleStarted)
            {
                try
                {
                    EndGuestMovieThrottle(moviePath);
                }
                catch
                {
                }
            }

            hostApi?.Dispose();
            if (process is not null)
            {
                TryKill(process);
                process.Dispose();
            }

            if (radProcessesBeforeLaunch is not null)
            {
                RadBinkEmbeddedHostApiV724323171
                    .KillSpawnedRadProcesses(radProcessesBeforeLaunch);
            }

            Console.Error.WriteLine(
                "[LOADER][ERROR] bink2.rad_required_start_failed " +
                $"file='{fileName}' " +
                $"type={ex.GetType().Name} message='{Sanitize(ex.Message)}'");
            return false;
        }
    }

    private void PulseGuestMovieThrottle()
    {
        if (_disposed || Volatile.Read(ref _guestThrottleReleased) != 0)
        {
            return;
        }

        if (_hostApi.IsPlaybackFinished)
        {
            ReleaseGuestMovieThrottle("renderer-finished");
            return;
        }

        // Lifecycle state is persistent; heartbeat is telemetry only.
        var count = Interlocked.Increment(ref _guestThrottleHeartbeatCount);
        if (count <= 3 || (count & (count - 1)) == 0)
        {
            Console.Error.WriteLine(
                "[LOADER][TRACE] bink2.rad_guest_work_throttle_heartbeat " +
                $"file='{Path.GetFileName(MoviePath)}' count={count} " +
                $"elapsed_ms={_elapsed.Elapsed.TotalMilliseconds:F1}");
        }
    }

    private void ReleaseGuestMovieThrottle(string reason)
    {
        if (!_guestThrottleStarted)
        {
            return;
        }

        if (Interlocked.Exchange(ref _guestThrottleReleased, 1) != 0)
        {
            return;
        }

        try
        {
            EndGuestMovieThrottle(MoviePath);
            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.rad_guest_hard_gate_stopped " +
                $"file='{Path.GetFileName(MoviePath)}' active_decoder_lifecycle=False hle_execution_gate=False");
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(
                "[LOADER][WARN] bink2.rad_guest_work_throttle_release_failed " +
                $"file='{Path.GetFileName(MoviePath)}' type={ex.GetType().Name}");
        }

        Console.Error.WriteLine(
            "[LOADER][INFO] bink2.rad_guest_work_throttle_end " +
            $"file='{Path.GetFileName(MoviePath)}' reason={reason} " +
            $"heartbeats={Volatile.Read(ref _guestThrottleHeartbeatCount)} " +
            $"elapsed_ms={_elapsed.Elapsed.TotalMilliseconds:F1}");
    }

    private static void BeginGuestMovieThrottle(string moviePath)
    {
        // V72.4.3.2.14 patches this lifecycle method to enter
        // HostMovieExecutionGateV7243214 exactly once.
        BinkHostPlaybackAssist.NotifyHostMovieDecoderStarted(moviePath);
    }

    private static void EndGuestMovieThrottle(string moviePath)
    {
        // V72.4.3.2.14 patches this lifecycle method to leave
        // HostMovieExecutionGateV7243214 exactly once.
        BinkHostPlaybackAssist.NotifyHostMovieDecoderStopped(moviePath);
    }

    private static int ResolveIntEnvironment(
        string name,
        int defaultValue,
        int minimum,
        int maximum)
    {
        var configured = Environment.GetEnvironmentVariable(name);
        return int.TryParse(configured, out var parsed)
            ? Math.Clamp(parsed, minimum, maximum)
            : defaultValue;
    }

    private static bool TryReadBinkHeaderMetadata(
        string moviePath,
        out BinkHeaderMetadata metadata)
    {
        metadata = default;

        try
        {
            using var stream = new FileStream(
                moviePath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.ReadWrite);
            using var reader = new BinaryReader(
                stream,
                Encoding.ASCII,
                leaveOpen: false);

            if (stream.Length < 48)
            {
                return false;
            }

            var tagBytes = reader.ReadBytes(4);
            if (tagBytes.Length != 4)
            {
                return false;
            }

            var tag = Encoding.ASCII.GetString(tagBytes);
            var isBink1 = tag.StartsWith("BIK", StringComparison.Ordinal);
            var isBink2 = tag.StartsWith("KB2", StringComparison.Ordinal);
            if (!isBink1 && !isBink2)
            {
                return false;
            }

            stream.Position = 8;
            var frameCount = reader.ReadUInt32();
            stream.Position = 20;
            var width = reader.ReadUInt32();
            var height = reader.ReadUInt32();
            var fpsNumerator = reader.ReadUInt32();
            var fpsDenominator = reader.ReadUInt32();
            if (frameCount == 0 || width == 0 || height == 0 ||
                fpsNumerator == 0 || fpsDenominator == 0)
            {
                return false;
            }

            stream.Position = 40;
            var count = reader.ReadUInt32();
            if (count > 256)
            {
                return false;
            }

            var revision = tag[3];
            var hasNewField =
                (isBink1 && revision == 'k') ||
                (isBink2 &&
                 (revision == 'i' ||
                  revision == 'j' ||
                  revision == 'k'));

            if (hasNewField)
            {
                if (stream.Position + 4 > stream.Length)
                {
                    return false;
                }
                _ = reader.ReadUInt32();
            }

            var tableBytes = checked((long)count * 12L);
            if (stream.Position + tableBytes > stream.Length)
            {
                return false;
            }

            stream.Position += checked((long)count * 4L);
            stream.Position += checked((long)count * 4L);

            var trackIds = new uint[(int)count];
            for (var index = 0; index < trackIds.Length; index++)
            {
                trackIds[index] = reader.ReadUInt32();
            }

            metadata = new BinkHeaderMetadata(
                frameCount,
                width,
                height,
                fpsNumerator,
                fpsDenominator,
                trackIds);
            return true;
        }
        catch (Exception ex) when (
            ex is IOException or
            UnauthorizedAccessException or
            OverflowException)
        {
            Console.Error.WriteLine(
                "[LOADER][WARN] bink2.rad_audio_header_failed " +
                $"file='{Path.GetFileName(moviePath)}' " +
                $"type={ex.GetType().Name} message='{Sanitize(ex.Message)}'");
            metadata = default;
            return false;
        }
    }

    private static string? ResolveToolPath()
    {
        var configured =
            Environment.GetEnvironmentVariable(
                "SHARPEMU_RADVIDEO64");

        if (IsExecutable(configured))
        {
            return Path.GetFullPath(configured!);
        }

        var configFile =
            Path.Combine(
                AppContext.BaseDirectory,
                "plugins",
                "bink2",
                "radvideo64.path");

        try
        {
            if (File.Exists(configFile))
            {
                var configuredFile =
                    File.ReadAllText(configFile).Trim().Trim('"');

                if (IsExecutable(configuredFile))
                {
                    return Path.GetFullPath(configuredFile);
                }
            }
        }
        catch (IOException)
        {
        }

        var path = Environment.GetEnvironmentVariable("PATH");
        if (!string.IsNullOrWhiteSpace(path))
        {
            foreach (var entry in path.Split(
                         Path.PathSeparator,
                         StringSplitOptions.RemoveEmptyEntries |
                         StringSplitOptions.TrimEntries))
            {
                try
                {
                    var candidate =
                        Path.Combine(entry, "radvideo64.exe");
                    if (File.Exists(candidate))
                    {
                        return Path.GetFullPath(candidate);
                    }
                }
                catch
                {
                }
            }
        }

        return null;
    }

    private static bool IsExecutable(string? path) =>
        !string.IsNullOrWhiteSpace(path) &&
        File.Exists(path) &&
        string.Equals(
            Path.GetFileName(path),
            "radvideo64.exe",
            StringComparison.OrdinalIgnoreCase);

    private static void TryKill(Process process)
    {
        try
        {
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
                process.WaitForExit(2_000);
            }
        }
        catch
        {
        }
    }

    private static string Sanitize(string? text) =>
        string.IsNullOrWhiteSpace(text)
            ? string.Empty
            : text.Replace('\r', ' ').Replace('\n', ' ').Trim();

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;

        if (_usesSharpEmuAttractAudio)
        {
            BinkDemonSoulsIntroAudioV7243227.StopForMovie(MoviePath);
        }

        // Kill first while it is still parented to SharpEmu; this prevents the
        // renderer HWND from becoming a desktop top-level window during teardown.
        TryKill(_process);
        ReleaseGuestMovieThrottle("dispose");
        _guestThrottleHeartbeatTimer?.Dispose();
        _hostApi.Dispose();
        _process.Dispose();
        _elapsed.Stop();
    }
}
