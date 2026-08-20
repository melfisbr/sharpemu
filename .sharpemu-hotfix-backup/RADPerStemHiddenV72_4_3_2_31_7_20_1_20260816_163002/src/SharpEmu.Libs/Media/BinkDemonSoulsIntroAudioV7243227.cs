// Copyright (C) 2026 SharpEmu Emulator Project
// SPDX-License-Identifier: GPL-2.0-or-later

using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;

namespace SharpEmu.Libs.Media;

/// <summary>
/// V72.4.3.2.29: Demon's Souls opening external-audio decoder-rate timeline.
///
/// Eboot/bank cross-reference established that PlayOpeningMovie and
/// MusicStartIntro are separate paths. The cutscene banks resolve the opening
/// stems to pr_demons_souls_intro_{music,sfx,vo}.at9.
///
/// The stems are prepared ahead of logo_intro while ps_studios_logo is still
/// playing, then started on the first presented logo frame. If attract_movie
/// follows immediately, the same 129.433 s timeline continues without restart.
/// If attract_movie starts independently, a cached 12-second-offset tail is
/// used.
/// </summary>
internal static class BinkDemonSoulsIntroAudioV7243227
{
    internal enum AttachDisposition
    {
        NotHandled = 0,
        NewTimeline = 1,
        ContinueTimeline = 2,
    }

    private enum TimelineMode
    {
        None = 0,
        Full = 1,
        TailFrom12 = 2,
        Continue = 3,
    }

    private const uint SndAsync = 0x0001;
    private const uint SndNodefault = 0x0002;
    private const uint SndFilename = 0x00020000;
    private static double AttractOffsetSeconds => DemonSoulsOpeningTimelineProfileV31716.LogoIntroDurationSeconds;

    private static readonly object Gate = new();

    private static readonly Dictionary<string, Task<string?>> FullTasks =
        new(StringComparer.OrdinalIgnoreCase);
    private static readonly Dictionary<string, Task<string?>> TailTasks =
        new(StringComparer.OrdinalIgnoreCase);

    private static string? _activeRoot;
    private static string? _activeMovie;
    private static TimelineMode _activeMode;
    private static bool _timelineStarted;

    public static AttachDisposition PrepareAttach(string moviePath)
    {
        if (!OperatingSystem.IsWindows() ||
            string.Equals(
                Environment.GetEnvironmentVariable(
                    "SHARPEMU_DS_INTRO_EXTERNAL_AUDIO"),
                "0",
                StringComparison.Ordinal) ||
            !TryResolveAssets(
                moviePath,
                out var root,
                out var music,
                out var sfx,
                out var vo))
        {
            ResetStateForNonIntro(moviePath);
            return AttachDisposition.NotHandled;
        }

        var fileName = Path.GetFileName(moviePath);

        // Warm both cached variants during the PlayStation Studios clip. The
        // existing embedded audio bridge still handles that movie itself.
        if (string.Equals(
                fileName,
                "ps_studios_logo.bk2",
                StringComparison.OrdinalIgnoreCase))
        {
            lock (Gate)
            {
                _ = EnsureFullTaskLocked(root, music, sfx, vo);
                _ = EnsureTailTaskLocked(root, music, sfx, vo);
            }

            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.ds_intro_audio_prewarm " +
                $"root='{root}'");
            return AttachDisposition.NotHandled;
        }

        if (string.Equals(
                fileName,
                "logo_intro.bk2",
                StringComparison.OrdinalIgnoreCase))
        {
            lock (Gate)
            {
                _activeRoot = root;
                _activeMovie = moviePath;
                _activeMode = TimelineMode.Full;
                _timelineStarted = false;

                _ = EnsureFullTaskLocked(root, music, sfx, vo);
                _ = EnsureTailTaskLocked(root, music, sfx, vo);
            }

            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.ds_intro_audio_prepare " +
                "mode=full file='logo_intro.bk2'");
            return AttachDisposition.NewTimeline;
        }

        if (string.Equals(
                fileName,
                "attract_movie.bk2",
                StringComparison.OrdinalIgnoreCase))
        {
            // V72.4.3.2.28 ATTRACT_AUDIO_RESYNC
            // Never continue wall-clock audio across a slow logo decoder.
            // Start the cached +12 s tail on attract_movie's own first frame.
            lock (Gate)
            {
                _activeRoot = root;
                _activeMovie = moviePath;
                _activeMode = TimelineMode.TailFrom12;
                _timelineStarted = false;
                _ = EnsureTailTaskLocked(root, music, sfx, vo);
            }

            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.ds_intro_audio_resync " +
                "mode=tail12 file='attract_movie.bk2'");
            return AttachDisposition.NewTimeline;
        }

        ResetStateForNonIntro(moviePath);
        return AttachDisposition.NotHandled;
    }

    // V31.7.18_PREPARED_ATTRACT_WAVE_FOR_BINKMIX
    // Returns the same sample-exact V31.7.16 tail that the old waveOut
    // sidecar used, but does not start a host audio device.  RAD binkmix will
    // encode this WAV as an audio track in a cached derivative of the BK2.
    public static bool TryGetPreparedAttractWaveForBinkMix(
        string moviePath,
        int timeoutMilliseconds,
        out string? wavePath)
    {
        wavePath = null;

        if (!OperatingSystem.IsWindows() ||
            !string.Equals(
                Path.GetFileName(moviePath),
                "attract_movie.bk2",
                StringComparison.OrdinalIgnoreCase) ||
            !TryResolveAssets(
                moviePath,
                out var root,
                out var music,
                out var sfx,
                out var vo))
        {
            return false;
        }

        Task<string?> task;
        lock (Gate)
        {
            task = EnsureTailTaskLocked(root, music, sfx, vo);
        }

        try
        {
            var timeout = Math.Clamp(
                timeoutMilliseconds,
                1_000,
                180_000);

            if (!task.Wait(timeout))
            {
                Console.Error.WriteLine(
                    "[LOADER][WARN] bink2.ds_attract_exact_wave_wait_failed " +
                    $"reason=timeout timeout_ms={timeout}");
                return false;
            }

            wavePath = task.GetAwaiter().GetResult();
            if (!IsPlayableWave(wavePath))
            {
                Console.Error.WriteLine(
                    "[LOADER][WARN] bink2.ds_attract_exact_wave_wait_failed " +
                    "reason=wave-unavailable");
                wavePath = null;
                return false;
            }

            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.ds_attract_exact_wave_for_binkmix " +
                $"wav='{wavePath}' source=V31.7.16-sample-exact");
            return true;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(
                "[LOADER][WARN] bink2.ds_attract_exact_wave_wait_failed " +
                $"reason=exception type={ex.GetType().Name} " +
                $"message='{Sanitize(ex.Message)}'");
            wavePath = null;
            return false;
        }
    }
    public static bool NotifyPresentationStarted(string moviePath)
    {
        Task<string?>? task;
        TimelineMode mode;
        string? root;

        lock (Gate)
        {
            if (!string.Equals(
                    moviePath,
                    _activeMovie,
                    StringComparison.OrdinalIgnoreCase) ||
                string.IsNullOrWhiteSpace(_activeRoot))
            {
                return false;
            }

            mode = _activeMode;
            root = _activeRoot;

            if (mode == TimelineMode.Full)
            {
                task = FullTasks.TryGetValue(root, out var full)
                    ? full
                    : null;
            }
            else if (mode == TimelineMode.TailFrom12)
            {
                task = TailTasks.TryGetValue(root, out var tail)
                    ? tail
                    : null;
            }
            else
            {
                return false;
            }
        }

        if (task is null)
        {
            return true;
        }

        if (task.IsCompletedSuccessfully)
        {
            StartIfCurrent(moviePath, mode, task.Result);
            return true;
        }

        // Preparation normally starts during ps_studios_logo, so this path is
        // only a first-run fallback. Do not block the presentation thread.
        _ = task.ContinueWith(
            completed =>
            {
                if (completed.Status == TaskStatus.RanToCompletion)
                {
                    StartIfCurrent(moviePath, mode, completed.Result);
                }
            },
            CancellationToken.None,
            TaskContinuationOptions.ExecuteSynchronously,
            TaskScheduler.Default);

        Console.Error.WriteLine(
            "[LOADER][INFO] bink2.ds_intro_audio_waiting_for_cache " +
            $"file='{Path.GetFileName(moviePath)}'");
        return true;
    }

    // V31.7.15.2_WAVEOUT_AUDIO_PROGRESS
    public static bool WaitForPresentationAudioProgress(
        string moviePath,
        int targetMilliseconds,
        int timeoutMilliseconds,
        out double observedMilliseconds,
        out double wallWaitMilliseconds)
    {
        observedMilliseconds = 0.0;
        wallWaitMilliseconds = 0.0;

        lock (Gate)
        {
            if (!_timelineStarted ||
                !string.Equals(
                    moviePath,
                    _activeMovie,
                    StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }
        }

        return BinkDeterministicWavePlayerV317152.WaitForProgress(
            targetMilliseconds,
            timeoutMilliseconds,
            out observedMilliseconds,
            out wallWaitMilliseconds);
    }
    private static void StartIfCurrent(
        string moviePath,
        TimelineMode mode,
        string? wavePath)
    {
        if (!IsPlayableWave(wavePath))
        {
            Console.Error.WriteLine(
                "[LOADER][WARN] bink2.ds_intro_audio_unavailable " +
                $"file='{Path.GetFileName(moviePath)}'");
            return;
        }

        lock (Gate)
        {
            if (!string.Equals(
                    moviePath,
                    _activeMovie,
                    StringComparison.OrdinalIgnoreCase) ||
                _activeMode != mode)
            {
                return;
            }

                        // V31.7.15.2_WAVEOUT_AUDIO_CLOCK
            // PlaySound(SND_ASYNC) only confirms queueing.  Use waveOut by
            // default so the embedded RAD host can query actual PCM playback
            // progress before revealing attract_movie.
            var useDeterministicWaveClock =
                Environment.GetEnvironmentVariable(
                    "SHARPEMU_DS_INTRO_WAVEOUT_CLOCK") != "0";

            string waveClockDetail = "playsound-fallback";
            var audioStarted = useDeterministicWaveClock
                ? BinkDeterministicWavePlayerV317152.TryStart(
                    wavePath!,
                    out waveClockDetail)
                : PlaySound(
                    wavePath,
                    IntPtr.Zero,
                    SndFilename | SndAsync | SndNodefault);

            if (!audioStarted)
            {
                Console.Error.WriteLine(
                    "[LOADER][WARN] bink2.ds_intro_audio_start_failed " +
                    $"file='{Path.GetFileName(moviePath)}'");
                return;
            }

            _timelineStarted = true;
            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.ds_intro_audio_clock " +
                $"file='{Path.GetFileName(moviePath)}' " +
                $"backend={(useDeterministicWaveClock ? "waveout-cursor" : "playsound-async")} " +
                $"detail='{waveClockDetail}'");

            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.ds_intro_audio_start " +
                $"file='{Path.GetFileName(moviePath)}' " +
                $"mode={(mode == TimelineMode.Full ? "full12" : "tail12")} " +
                $"wav='{wavePath}'");

            if (mode == TimelineMode.Full)
            {
                // V72.4.3.2.28 LOGO_AUDIO_SEGMENT_LIMIT
                ScheduleLogoSegmentStop(moviePath);
            }
        }
    }

    private static void ScheduleLogoSegmentStop(string moviePath)
    {
        _ = Task.Run(
            async () =>
            {
                await Task.Delay(
                    TimeSpan.FromSeconds(AttractOffsetSeconds))
                    .ConfigureAwait(false);

                lock (Gate)
                {
                    if (!_timelineStarted ||
                        _activeMode != TimelineMode.Full ||
                        !string.Equals(
                            moviePath,
                            _activeMovie,
                            StringComparison.OrdinalIgnoreCase))
                    {
                        return;
                    }

                    _ = BinkDeterministicWavePlayerV317152.Stop();
                    _ = PlaySound(null, IntPtr.Zero, 0);
                    _timelineStarted = false;

                    Console.Error.WriteLine(
                        "[LOADER][INFO] bink2.ds_intro_audio_logo_segment_stop " +
                        "elapsed_s=12.000");
                }
            });
    }

    // V72.4.3.2.31.6 RAD_ATTRACT_AUDIO_STOP
    public static void StopForMovie(string moviePath)
    {
        if (string.IsNullOrWhiteSpace(moviePath))
        {
            return;
        }

        lock (Gate)
        {
            if (!string.Equals(
                    moviePath,
                    _activeMovie,
                    StringComparison.OrdinalIgnoreCase))
            {
                return;
            }

            if (_timelineStarted)
            {
                _ = BinkDeterministicWavePlayerV317152.Stop();
                    _ = PlaySound(null, IntPtr.Zero, 0);
            }

            _activeRoot = null;
            _activeMovie = null;
            _activeMode = TimelineMode.None;
            _timelineStarted = false;

            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.rad_attract_audio_stop " +
                $"file='{Path.GetFileName(moviePath)}'");
        }
    }

    private static void ResetStateForNonIntro(string moviePath)
    {
        if (string.IsNullOrWhiteSpace(moviePath))
        {
            return;
        }

        var fileName = Path.GetFileName(moviePath);
        if (string.Equals(
                fileName,
                "ps_studios_logo.bk2",
                StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        lock (Gate)
        {
            _activeRoot = null;
            _activeMovie = null;
            _activeMode = TimelineMode.None;
            _timelineStarted = false;
        }
    }

    private static Task<string?> EnsureFullTaskLocked(
        string root,
        string music,
        string sfx,
        string vo)
    {
        if (FullTasks.TryGetValue(root, out var existing))
        {
            return existing;
        }

        var task = Task.Run(
            () => BuildFullMix(root, music, sfx, vo));
        FullTasks[root] = task;
        return task;
    }

    private static Task<string?> EnsureTailTaskLocked(
        string root,
        string music,
        string sfx,
        string vo)
    {
        if (TailTasks.TryGetValue(root, out var existing))
        {
            return existing;
        }

        var fullTask = EnsureFullTaskLocked(root, music, sfx, vo);
        var task = Task.Run(
            () =>
            {
                string? full;
                try
                {
                    full = fullTask.GetAwaiter().GetResult();
                }
                catch
                {
                    return null;
                }

                return IsPlayableWave(full)
                    ? BuildTail(root, music, sfx, vo, full!)
                    : null;
            });

        TailTasks[root] = task;
        return task;
    }

    private static string? BuildFullMix(
        string root,
        string music,
        string sfx,
        string vo)
    {
        try
        {
            var ffmpeg = FindFfmpegPath();
            if (ffmpeg is null)
            {
                Console.Error.WriteLine(
                    "[LOADER][WARN] bink2.ds_intro_audio_ffmpeg_missing");
                return null;
            }

            var cacheDirectory = GetCacheDirectory();
            Directory.CreateDirectory(cacheDirectory);

            var key = BuildAssetKey(music, sfx, vo);
            var output =
                Path.Combine(
                    cacheDirectory,
                    $"demons-souls-intro-{key}.wav");

            if (IsPlayableWave(output))
            {
                return output;
            }

            var temporary =
                output + ".tmp-" + Guid.NewGuid().ToString("N") + ".wav";

            var args = new[]
            {
                "-hide_banner",
                "-loglevel", "error",
                "-nostdin",
                "-y",
                "-i", music,
                "-i", sfx,
                "-i", vo,
                "-filter_complex",
                "[0:a]aformat=sample_rates=48000:channel_layouts=stereo[m];" +
                "[1:a]aformat=sample_rates=48000:channel_layouts=stereo[s];" +
                "[2:a]aformat=sample_rates=48000:channel_layouts=stereo[v];" +
                "[m][s][v]amix=inputs=3:duration=longest:" +
                "dropout_transition=0:normalize=1[out]",
                "-map", "[out]",
                "-c:a", "pcm_s16le",
                "-ar", "48000",
                "-ac", "2",
                temporary,
            };

            if (!RunFfmpeg(ffmpeg, args))
            {
                TryDelete(temporary);
                return null;
            }

            if (!IsPlayableWave(temporary))
            {
                TryDelete(temporary);
                return null;
            }

            File.Move(temporary, output, true);

            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.ds_intro_audio_cache_ready " +
                $"mode=full root='{root}' wav='{output}'");
            return output;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(
                "[LOADER][WARN] bink2.ds_intro_audio_prepare_failed " +
                $"mode=full type={ex.GetType().Name} " +
                $"message='{Sanitize(ex.Message)}'");
            return null;
        }
    }

    private static string? BuildTail(
        string root,
        string music,
        string sfx,
        string vo,
        string fullMix)
    {
        // V31.7.19_EBOOT_FRONT_BOUNDARY_ATTRACT_TAIL
        //
        // EBOOT separates MusicStartIntro/MusicSkipIntro/SkipIntro from the
        // frontend AttractMovie state. The numerical boundary comes from the
        // immediately preceding canonical media: logo_intro is 360/30 = 12 s.
        //
        // Do NOT infer start from the end of the decoded PCM. Decoder/codec
        // residual samples belong after the requested attract window.
        try
        {
            var ffmpeg = FindFfmpegPath();
            if (ffmpeg is null)
            {
                return null;
            }

            if (!TryReadPcmWaveSampleFramesV31716(
                    fullMix,
                    out var sampleRate,
                    out var fullSampleFrames) ||
                sampleRate <= 0 ||
                fullSampleFrames <= 0)
            {
                Console.Error.WriteLine(
                    "[LOADER][WARN] bink2.ds_intro_front_boundary_failed " +
                    "reason=full-mix-wave-metadata");
                return null;
            }

            var logoDuration =
                DemonSoulsOpeningTimelineProfileV31716.LogoIntroDurationSeconds;
            var attractDuration =
                DemonSoulsOpeningTimelineProfileV31716.AttractDurationSeconds;

            var startSample = checked(
                (long)Math.Round(
                    logoDuration * sampleRate,
                    MidpointRounding.AwayFromZero));

            var targetSamples = checked(
                (long)Math.Round(
                    attractDuration * sampleRate,
                    MidpointRounding.AwayFromZero));

            var endSample = checked(startSample + targetSamples);

            if (startSample < 0 ||
                targetSamples <= 0 ||
                fullSampleFrames < endSample)
            {
                Console.Error.WriteLine(
                    "[LOADER][WARN] bink2.ds_intro_front_boundary_failed " +
                    $"reason=invalid-sample-range full={fullSampleFrames} " +
                    $"start={startSample} target={targetSamples} end={endSample}");
                return null;
            }

            var trailingPaddingSamples =
                fullSampleFrames - endSample;
            var trailingPaddingMilliseconds =
                trailingPaddingSamples * 1000.0 / sampleRate;

            var cacheDirectory = GetCacheDirectory();
            Directory.CreateDirectory(cacheDirectory);

            var key = BuildAssetKey(music, sfx, vo);
            var output = Path.Combine(
                cacheDirectory,
                $"demons-souls-intro-{key}-eboot-v31719-front-" +
                $"s{startSample}-n{targetSamples}.wav");

            if (IsPlayableWave(output) &&
                TryReadPcmWaveSampleFramesV31716(
                    output,
                    out var cachedRate,
                    out var cachedSamples) &&
                cachedRate == sampleRate &&
                Math.Abs(cachedSamples - targetSamples) <= 1)
            {
                Console.Error.WriteLine(
                    "[LOADER][INFO] bink2.ds_intro_eboot_front_boundary_profile " +
                    $"cache=True sample_rate={sampleRate} " +
                    $"full_samples={fullSampleFrames} " +
                    $"start_sample={startSample} target_samples={targetSamples} " +
                    $"end_sample={endSample} logical_offset_s={logoDuration:F6} " +
                    $"attract_duration_s={attractDuration:F6} " +
                    $"trailing_padding_samples={trailingPaddingSamples} " +
                    $"trailing_padding_ms={trailingPaddingMilliseconds:F3} " +
                    $"eboot_sha='{DemonSoulsOpeningTimelineProfileV31716.EbootSha256}'");
                return output;
            }

            var temporary =
                output + ".tmp-" + Guid.NewGuid().ToString("N") + ".wav";

            var filter =
                $"atrim=start_sample={startSample}:end_sample={endSample}," +
                "asetpts=PTS-STARTPTS";

            var args = new[]
            {
                "-hide_banner",
                "-loglevel", "error",
                "-nostdin",
                "-y",
                "-i", fullMix,
                "-filter:a", filter,
                "-c:a", "pcm_s16le",
                "-ar", sampleRate.ToString(
                    System.Globalization.CultureInfo.InvariantCulture),
                "-ac", "2",
                temporary,
            };

            if (!RunFfmpeg(ffmpeg, args))
            {
                TryDelete(temporary);
                return null;
            }

            var resultRate = 0;
            var resultSamples = 0L;
            var resultMetadataOk =
                TryReadPcmWaveSampleFramesV31716(
                    temporary,
                    out resultRate,
                    out resultSamples);

            if (!IsPlayableWave(temporary) ||
                !resultMetadataOk ||
                resultRate != sampleRate ||
                Math.Abs(resultSamples - targetSamples) > 1)
            {
                TryDelete(temporary);
                Console.Error.WriteLine(
                    "[LOADER][WARN] bink2.ds_intro_front_boundary_failed " +
                    $"reason=result-sample-count expected={targetSamples} " +
                    $"actual={resultSamples} rate={resultRate} " +
                    $"metadata_ok={resultMetadataOk}");
                return null;
            }

            File.Move(temporary, output, true);

            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.ds_intro_eboot_front_boundary_profile " +
                $"cache=False sample_rate={sampleRate} " +
                $"full_samples={fullSampleFrames} " +
                $"start_sample={startSample} target_samples={targetSamples} " +
                $"end_sample={endSample} logical_offset_s={logoDuration:F6} " +
                $"attract_duration_s={attractDuration:F6} " +
                $"trailing_padding_samples={trailingPaddingSamples} " +
                $"trailing_padding_ms={trailingPaddingMilliseconds:F3} " +
                $"eboot_sha='{DemonSoulsOpeningTimelineProfileV31716.EbootSha256}'");

            return output;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(
                "[LOADER][WARN] bink2.ds_intro_audio_prepare_failed " +
                $"mode=eboot-front-boundary type={ex.GetType().Name} " +
                $"message='{Sanitize(ex.Message)}'");
            return null;
        }
    }

    // V31.7.16_PCM_WAVE_SAMPLE_READER
    private static bool TryReadPcmWaveSampleFramesV31716(
        string path,
        out int sampleRate,
        out long sampleFrames)
    {
        sampleRate = 0;
        sampleFrames = 0;

        try
        {
            using var stream = File.OpenRead(path);
            using var reader = new BinaryReader(
                stream,
                Encoding.ASCII,
                leaveOpen: false);

            if (stream.Length < 44 ||
                Encoding.ASCII.GetString(reader.ReadBytes(4)) != "RIFF")
            {
                return false;
            }

            _ = reader.ReadUInt32();
            if (Encoding.ASCII.GetString(reader.ReadBytes(4)) != "WAVE")
            {
                return false;
            }

            ushort blockAlign = 0;
            long dataBytes = -1;

            while (stream.Position + 8 <= stream.Length)
            {
                var id = Encoding.ASCII.GetString(reader.ReadBytes(4));
                var size = reader.ReadUInt32();
                var payload = stream.Position;

                if (id == "fmt " && size >= 16)
                {
                    var formatTag = reader.ReadUInt16();
                    _ = reader.ReadUInt16(); // channels
                    var rate = reader.ReadUInt32();
                    _ = reader.ReadUInt32(); // avg bytes/sec
                    var align = reader.ReadUInt16();
                    _ = reader.ReadUInt16(); // bits/sample

                    if (formatTag != 1 || rate == 0 || align == 0)
                    {
                        return false;
                    }

                    sampleRate = checked((int)rate);
                    blockAlign = align;
                }
                else if (id == "data")
                {
                    dataBytes = size;
                }

                var padded = size + (size & 1u);
                stream.Position = checked(payload + padded);

                if (sampleRate != 0 &&
                    blockAlign != 0 &&
                    dataBytes >= 0)
                {
                    break;
                }
            }

            if (sampleRate == 0 ||
                blockAlign == 0 ||
                dataBytes < 0 ||
                dataBytes % blockAlign != 0)
            {
                return false;
            }

            sampleFrames = dataBytes / blockAlign;
            return sampleFrames > 0;
        }
        catch
        {
            sampleRate = 0;
            sampleFrames = 0;
            return false;
        }
    }
    private static double ResolveV724329AttractTempo()
    {
        var configured =
            Environment.GetEnvironmentVariable(
                "SHARPEMU_DS_ATTRACT_AUDIO_TEMPO");

        if (double.TryParse(
                configured,
                System.Globalization.NumberStyles.Float,
                System.Globalization.CultureInfo.InvariantCulture,
                out var parsed))
        {
            return Math.Clamp(parsed, 0.75, 1.00);
        }

        // 27.162 / 30.0 from the user's native/LTO pure decoder benchmark.
        return 0.9054;
    }

    private static bool RunFfmpeg(
        string ffmpeg,
        IReadOnlyList<string> arguments)
    {
        using var process = new Process();
        process.StartInfo = new ProcessStartInfo
        {
            FileName = ffmpeg,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };

        foreach (var argument in arguments)
        {
            process.StartInfo.ArgumentList.Add(argument);
        }

        if (!process.Start())
        {
            return false;
        }

        var stdout = process.StandardOutput.ReadToEndAsync();
        var stderr = process.StandardError.ReadToEndAsync();

        if (!process.WaitForExit(180_000))
        {
            try
            {
                process.Kill(entireProcessTree: true);
            }
            catch
            {
            }

            Console.Error.WriteLine(
                "[LOADER][WARN] bink2.ds_intro_audio_ffmpeg_timeout");
            return false;
        }

        Task.WaitAll(stdout, stderr);

        if (process.ExitCode == 0)
        {
            return true;
        }

        Console.Error.WriteLine(
            "[LOADER][WARN] bink2.ds_intro_audio_ffmpeg_failed " +
            $"exit={process.ExitCode} detail='{Sanitize(stderr.Result)}'");
        return false;
    }

    private static bool TryResolveAssets(
        string moviePath,
        out string root,
        out string music,
        out string sfx,
        out string vo)
    {
        root = "";
        music = "";
        sfx = "";
        vo = "";

        if (string.IsNullOrWhiteSpace(moviePath) ||
            !File.Exists(moviePath))
        {
            return false;
        }

        var movieDirectory = Path.GetDirectoryName(moviePath);
        if (string.IsNullOrWhiteSpace(movieDirectory) ||
            !string.Equals(
                Path.GetFileName(movieDirectory),
                "movies",
                StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        var parent = Directory.GetParent(movieDirectory);
        if (parent is null)
        {
            return false;
        }

        root = parent.FullName;

        // Scope to the audited Demon's Souls installs.
        if (!root.Contains(
                "PPSA01341",
                StringComparison.OrdinalIgnoreCase) &&
            !root.Contains(
                "PPSA25646",
                StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        music = Path.Combine(
            root,
            "sound",
            "streams",
            "07_cutscene_music",
            "pr_demons_souls_intro_music.at9");
        sfx = Path.Combine(
            root,
            "sound",
            "streams",
            "05_cutscene_sfx",
            "pr_demons_souls_intro_sfx.at9");
        vo = Path.Combine(
            root,
            "sound",
            "streams",
            "06_cutscene_vo",
            "en",
            "pr_demons_souls_intro_vo.at9");

        return File.Exists(music) &&
               File.Exists(sfx) &&
               File.Exists(vo);
    }

    private static string BuildAssetKey(
        string music,
        string sfx,
        string vo)
    {
        var builder = new StringBuilder();

        foreach (var path in new[] { music, sfx, vo })
        {
            var info = new FileInfo(path);
            builder.Append(path);
            builder.Append('|');
            builder.Append(info.Length);
            builder.Append('|');
            builder.Append(info.LastWriteTimeUtc.Ticks);
            builder.Append(';');
        }

        var bytes = SHA256.HashData(
            Encoding.UTF8.GetBytes(builder.ToString()));
        return Convert.ToHexString(bytes.AsSpan(0, 8)).ToLowerInvariant();
    }

    private static string GetCacheDirectory()
    {
        var local =
            Environment.GetFolderPath(
                Environment.SpecialFolder.LocalApplicationData);

        if (string.IsNullOrWhiteSpace(local))
        {
            local = Path.GetTempPath();
        }

        return Path.Combine(
            local,
            "SharpEmu",
            "MediaCache",
            "DemonSouls");
    }

    private static string? FindFfmpegPath()
    {
        var configured =
            Environment.GetEnvironmentVariable("SHARPEMU_FFMPEG");

        if (!string.IsNullOrWhiteSpace(configured) &&
            File.Exists(configured))
        {
            return configured;
        }

        var appLocal =
            Path.Combine(AppContext.BaseDirectory, "ffmpeg.exe");

        if (File.Exists(appLocal))
        {
            return appLocal;
        }

        var path =
            Environment.GetEnvironmentVariable("PATH");

        if (!string.IsNullOrWhiteSpace(path))
        {
            foreach (var entry in path.Split(
                         Path.PathSeparator,
                         StringSplitOptions.RemoveEmptyEntries |
                         StringSplitOptions.TrimEntries))
            {
                try
                {
                    var candidate = Path.Combine(entry, "ffmpeg.exe");
                    if (File.Exists(candidate))
                    {
                        return candidate;
                    }
                }
                catch
                {
                }
            }
        }

        return null;
    }

    private static bool IsPlayableWave(string? path)
    {
        if (string.IsNullOrWhiteSpace(path) ||
            !File.Exists(path))
        {
            return false;
        }

        try
        {
            var info = new FileInfo(path);
            if (info.Length <= 44)
            {
                return false;
            }

            Span<byte> header = stackalloc byte[12];
            using var stream = new FileStream(
                path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read);

            if (stream.Read(header) != header.Length)
            {
                return false;
            }

            return header[0] == (byte)'R' &&
                   header[1] == (byte)'I' &&
                   header[2] == (byte)'F' &&
                   header[3] == (byte)'F' &&
                   header[8] == (byte)'W' &&
                   header[9] == (byte)'A' &&
                   header[10] == (byte)'V' &&
                   header[11] == (byte)'E';
        }
        catch
        {
            return false;
        }
    }

    private static void TryDelete(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
        catch
        {
        }
    }

    private static string Sanitize(string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return "";
        }

        return text
            .Replace('\r', ' ')
            .Replace('\n', ' ')
            .Trim();
    }

    [DllImport(
        "winmm.dll",
        CharSet = CharSet.Unicode,
        SetLastError = false)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool PlaySound(
        string? pszSound,
        IntPtr hmod,
        uint fdwSound);
}
