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
    private static bool _timelineArmed;

    // SHARPEMU_DEMONS_STARTUP_GUEST_AUDIO_OWNERSHIP_V1_1_6
    // Host RAD owns PS Studios audio; the external deterministic WaveOut
    // sidecar owns attract audio. Guest AudioOut/AudioOut2 must remain alive
    // for scheduling semantics but must not reach a host audio device while
    // either startup host owner is active.
    private static int _v116GuestAudioMuteActive;
    private static long _v116GuestAudioMuteUntilTick;
    private static int _v116GuestAudioMuteGeneration;

    internal static bool IsStartupGuestAudioMuteActiveV116()
    {
        if (Volatile.Read(ref _v116GuestAudioMuteActive) == 0)
        {
            return false;
        }

        var untilTick = Volatile.Read(
            ref _v116GuestAudioMuteUntilTick);

        if (Environment.TickCount64 <= untilTick)
        {
            return true;
        }

        if (Interlocked.Exchange(
                ref _v116GuestAudioMuteActive,
                0) != 0)
        {
            Console.Error.WriteLine(
                "[BINK-AUDIO-OWNER][V1.1.6] guest_mute_released " +
                "reason=timeout guest_audio_restored=True");
        }

        return false;
    }

    private static void ArmStartupGuestAudioMuteV116(
        string reason,
        int timeoutMilliseconds)
    {
        var timeout = Math.Clamp(
            timeoutMilliseconds,
            10_000,
            360_000);

        var untilTick =
            Environment.TickCount64 +
            timeout;

        Volatile.Write(
            ref _v116GuestAudioMuteUntilTick,
            untilTick);
        Interlocked.Exchange(
            ref _v116GuestAudioMuteActive,
            1);

        var generation = Interlocked.Increment(
            ref _v116GuestAudioMuteGeneration);

        Console.Error.WriteLine(
            "[BINK-AUDIO-OWNER][V1.1.6] guest_mute_armed " +
            $"generation={generation} reason='{reason}' " +
            $"timeout_ms={timeout} until_tick={untilTick} " +
            "audioout=True audioout2=True");
    }

    private static void ReleaseStartupGuestAudioMuteV116(
        string reason)
    {
        Volatile.Write(
            ref _v116GuestAudioMuteUntilTick,
            0);

        if (Interlocked.Exchange(
                ref _v116GuestAudioMuteActive,
                0) != 0)
        {
            Console.Error.WriteLine(
                "[BINK-AUDIO-OWNER][V1.1.6] guest_mute_released " +
                $"reason='{reason}' guest_audio_restored=True");
        }
    }
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
            ArmStartupGuestAudioMuteV116(
                "ps-studios-rad-owner",
                300_000);
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
                _timelineArmed = false;

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
            ArmStartupGuestAudioMuteV116(
                "attract-waveout-owner",
                180_000);
            // V72.4.3.2.28 ATTRACT_AUDIO_RESYNC
            // Never continue wall-clock audio across a slow logo decoder.
            // Start the cached +12 s tail on attract_movie's own first frame.
            lock (Gate)
            {
                _activeRoot = root;
                _activeMovie = moviePath;
                _activeMode = TimelineMode.TailFrom12;
                _timelineStarted = false;
                _timelineArmed = false;
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
                $"wav='{wavePath}' source=V31.7.20-per-stem-aligned");
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
    // V31.7.21_VISIBLE_FRAME_AUDIO_LATCH
    // Prepare the deterministic WaveOut program while RAD is still hidden, but
    // do not restart the device.  The actual start is released only after the
    // renderer HWND has been shown.
    public static bool NotifyPresentationArmed(string moviePath)
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

            if (_timelineStarted || _timelineArmed)
            {
                return true;
            }

            mode = _activeMode;
            root = _activeRoot;
            task = mode switch
            {
                TimelineMode.Full => FullTasks.TryGetValue(root, out var full) ? full : null,
                TimelineMode.TailFrom12 => TailTasks.TryGetValue(root, out var tail) ? tail : null,
                _ => null,
            };
        }

        if (task is null || !task.IsCompletedSuccessfully)
        {
            return false;
        }

        return ArmIfCurrent(moviePath, mode, task.Result);
    }

    public static bool IsPresentationArmed(string moviePath)
    {
        lock (Gate)
        {
            return _timelineArmed &&
                   !_timelineStarted &&
                   string.Equals(
                       moviePath,
                       _activeMovie,
                       StringComparison.OrdinalIgnoreCase);
        }
    }

    public static bool NotifyPresentationStarted(string moviePath)
    {
        // SHARPEMU_DEMONS_ATTRACT_RAD_VISIBLE_FRAME_RELEASE_V1_1_8
        // V1.1.6 calls NotifyPresentationStarted after RAD ShowWindow.  Keep
        // V31.7.21's StartIfCurrent path so it can prepare the deterministic
        // WaveOut exactly as before, then treat this RAD ShowWindow boundary as
        // the missing visible-frame event and explicitly waveOutRestart it.
        if (string.Equals(
                Path.GetFileName(moviePath),
                "attract_movie.bk2",
                StringComparison.OrdinalIgnoreCase))
        {
            Task<string?>? v118Task;
            string? v118Root;

            lock (Gate)
            {
                if (!string.Equals(
                        moviePath,
                        _activeMovie,
                        StringComparison.OrdinalIgnoreCase) ||
                    string.IsNullOrWhiteSpace(_activeRoot) ||
                    _activeMode != TimelineMode.TailFrom12)
                {
                    return false;
                }

                v118Root = _activeRoot;
                v118Task =
                    TailTasks.TryGetValue(v118Root, out var v118Tail)
                        ? v118Tail
                        : null;
            }

            if (v118Task is null)
            {
                Console.Error.WriteLine(
                    "[BINK-ATTRACT-SYNC][V1.1.8] reveal_release_no_tail_task " +
                    "file='attract_movie.bk2'");
                return true;
            }

            void v118StartAndRelease(string? v118WavePath)
            {
                StartIfCurrent(
                    moviePath,
                    TimelineMode.TailFrom12,
                    v118WavePath);

                var v118Released =
                    BinkDeterministicWavePlayerV317152.
                        TryResumePreparedAtRendererRevealV118(
                            out var v118Detail);

                Console.Error.WriteLine(
                    "[BINK-ATTRACT-SYNC][V1.1.8] rad_visible_frame_release " +
                    "file='attract_movie.bk2' " +
                    $"released={v118Released} detail='{v118Detail}' " +
                    "source=renderer-show " +
                    "arm_path=StartIfCurrent " +
                    "guest_audio_owner=waveout-sidecar");
            }

            if (v118Task.IsCompletedSuccessfully)
            {
                v118StartAndRelease(v118Task.Result);
                return true;
            }

            _ = v118Task.ContinueWith(
                completed =>
                {
                    if (completed.Status == TaskStatus.RanToCompletion)
                    {
                        v118StartAndRelease(completed.Result);
                    }
                },
                CancellationToken.None,
                TaskContinuationOptions.ExecuteSynchronously,
                TaskScheduler.Default);

            Console.Error.WriteLine(
                "[BINK-ATTRACT-SYNC][V1.1.8] reveal_release_waiting_for_tail " +
                "file='attract_movie.bk2'");
            return true;
        }
        Task<string?>? task;
        TimelineMode mode;
        string? root;

        lock (Gate)
        {
            if (_timelineArmed &&
                !_timelineStarted &&
                string.Equals(
                    moviePath,
                    _activeMovie,
                    StringComparison.OrdinalIgnoreCase))
            {
                var releaseWatch = Stopwatch.StartNew();
                if (BinkDeterministicWavePlayerV317152.TryStartPrepared(
                        out var releaseDetail))
                {
                    _timelineArmed = false;
                    _timelineStarted = true;
                    Console.Error.WriteLine(
                        "[LOADER][INFO] bink2.ds_intro_audio_visible_frame_release " +
                        $"file='{Path.GetFileName(moviePath)}' " +
                        $"release_ms={releaseWatch.Elapsed.TotalMilliseconds:F3} " +
                        $"detail='{releaseDetail}'");
                    return true;
                }

                _timelineArmed = false;
                Console.Error.WriteLine(
                    "[LOADER][WARN] bink2.ds_intro_audio_visible_frame_release_failed " +
                    $"file='{Path.GetFileName(moviePath)}' detail='{releaseDetail}'");
            }
        }

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
    private static bool ArmIfCurrent(
        string moviePath,
        TimelineMode mode,
        string? wavePath)
    {
        if (!IsPlayableWave(wavePath))
        {
            return false;
        }

        lock (Gate)
        {
            if (!string.Equals(
                    moviePath,
                    _activeMovie,
                    StringComparison.OrdinalIgnoreCase) ||
                _activeMode != mode ||
                _timelineStarted)
            {
                return false;
            }

            if (Environment.GetEnvironmentVariable(
                    "SHARPEMU_DS_INTRO_WAVEOUT_CLOCK") == "0")
            {
                return false;
            }

            if (!BinkDeterministicWavePlayerV317152.TryPreparePaused(
                    wavePath!,
                    out var waveClockDetail))
            {
                Console.Error.WriteLine(
                    "[LOADER][WARN] bink2.ds_intro_audio_visible_frame_arm_failed " +
                    $"file='{Path.GetFileName(moviePath)}' detail='{waveClockDetail}'");
                return false;
            }

            _timelineArmed = true;
            _timelineStarted = false;
            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.ds_intro_audio_visible_frame_armed " +
                $"file='{Path.GetFileName(moviePath)}' " +
                $"mode={(mode == TimelineMode.Full ? "full12" : "tail12")} " +
                $"detail='{waveClockDetail}'");
            return true;
        }
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

            _timelineArmed = false;
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

            if (_timelineStarted || _timelineArmed)
            {
                _ = BinkDeterministicWavePlayerV317152.Stop();
                    _ = PlaySound(null, IntPtr.Zero, 0);
            }

            _activeRoot = null;
            _activeMovie = null;
            _activeMode = TimelineMode.None;
            _timelineStarted = false;
            _timelineArmed = false;

            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.rad_attract_audio_stop " +
                $"file='{Path.GetFileName(moviePath)}'");
        }
    
        if (string.Equals(
                Path.GetFileName(moviePath),
                "attract_movie.bk2",
                StringComparison.OrdinalIgnoreCase))
        {
            ReleaseStartupGuestAudioMuteV116(
                "attract-playback-ended");
        }}

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
            _timelineArmed = false;
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

        // V31.7.20.3_AT9_FACT_ENCODER_DELAY
    // V31.7.20.3.1_STRUCTURAL_NEWLINE_SAFE_APPLY
    // Sony/VGAudio AT9 RIFF fact layout: logical SampleCount followed by
    // InputOverlapDelaySamples and EncoderDelaySamples. Keep this parser
    // narrowly scoped to the Demon's Souls host-side intro stem preparation.
    private readonly record struct At9FactTimelineV317203(
        long SampleCount,
        int InputOverlapDelaySamples,
        int EncoderDelaySamples);

    private static bool TryReadAt9FactTimelineV317203(
        string path,
        out At9FactTimelineV317203 timeline)
    {
        timeline = default;
        try
        {
            using var stream = File.OpenRead(path);
            if (stream.Length < 12)
            {
                return false;
            }

            using var reader = new BinaryReader(stream);
            if (reader.ReadUInt32() != 0x46464952u) // RIFF
            {
                return false;
            }

            _ = reader.ReadUInt32();
            if (reader.ReadUInt32() != 0x45564157u) // WAVE
            {
                return false;
            }

            while (stream.Position + 8 <= stream.Length)
            {
                var chunkId = reader.ReadUInt32();
                var chunkSize = reader.ReadUInt32();
                var chunkStart = stream.Position;
                if (chunkId == 0x74636166u && // fact
                    chunkSize >= 12 &&
                    chunkStart + 12 <= stream.Length)
                {
                    var logicalSamples = reader.ReadUInt32();
                    var inputOverlapDelay = reader.ReadInt32();
                    var encoderDelay = reader.ReadInt32();
                    if (logicalSamples == 0 ||
                        inputOverlapDelay < 0 ||
                        encoderDelay < 0)
                    {
                        return false;
                    }

                    timeline = new At9FactTimelineV317203(
                        logicalSamples,
                        inputOverlapDelay,
                        encoderDelay);
                    return true;
                }

                var paddedSize = (long)chunkSize + (chunkSize & 1u);
                var next = chunkStart + paddedSize;
                if (next < chunkStart || next > stream.Length)
                {
                    return false;
                }
                stream.Position = next;
            }
        }
        catch (Exception exception) when (
            exception is IOException or UnauthorizedAccessException)
        {
            return false;
        }

        return false;
    }
private static string? BuildTail(
        string root,
        string music,
        string sfx,
        string vo,
        string fullMix)
    {
        // V31.7.20_PER_STEM_ATTRACT_ALIGNMENT
        //
        // Do not infer a single cut after the three streams have already been
        // mixed. Music/SFX/VO are separate guest stream assets and may not
        // share the same encoded timeline origin. Decode each one to 48 kHz
        // PCM, inspect its own sample length, choose its own logical attract
        // origin, normalize it to the exact BK2 duration, and only then amix.
        _ = fullMix;

        try
        {
            var ffmpeg = FindFfmpegPath();
            if (ffmpeg is null)
            {
                return null;
            }

            var cacheDirectory = GetCacheDirectory();
            Directory.CreateDirectory(cacheDirectory);

            var key = BuildAssetKey(music, sfx, vo);
            const int RequiredSampleRate = 48_000;

            string? EnsureDecodedStem(
                string source,
                string label,
                out long sampleFrames)
            {
                sampleFrames = 0;
                var pcm = Path.Combine(
                    cacheDirectory,
                    $"demons-souls-intro-{key}-v31720-{label}-pcm.wav");

                if (IsPlayableWave(pcm) &&
                    TryReadPcmWaveSampleFramesV31716(
                        pcm,
                        out var cachedRate,
                        out var cachedFrames) &&
                    cachedRate == RequiredSampleRate &&
                    cachedFrames > 0)
                {
                    sampleFrames = cachedFrames;
                    return pcm;
                }

                TryDelete(pcm);
                var temporary =
                    pcm + ".tmp-" + Guid.NewGuid().ToString("N") + ".wav";

                var args = new[]
                {
                    "-hide_banner",
                    "-loglevel", "error",
                    "-nostdin",
                    "-y",
                    "-i", source,
                    "-map", "0:a:0",
                    "-c:a", "pcm_s16le",
                    "-ar", "48000",
                    "-ac", "2",
                    temporary,
                };

                if (!RunFfmpeg(ffmpeg, args) ||
                    !IsPlayableWave(temporary) ||
                    !TryReadPcmWaveSampleFramesV31716(
                        temporary,
                        out var resultRate,
                        out var resultFrames) ||
                    resultRate != RequiredSampleRate ||
                    resultFrames <= 0)
                {
                    TryDelete(temporary);
                    return null;
                }

                File.Move(temporary, pcm, true);
                sampleFrames = resultFrames;
                return pcm;
            }

            var musicPcm = EnsureDecodedStem(
                music,
                "music",
                out var musicSamples);
            var sfxPcm = EnsureDecodedStem(
                sfx,
                "sfx",
                out var sfxSamples);
            var voPcm = EnsureDecodedStem(
                vo,
                "vo-en",
                out var voSamples);
            var musicHasFact = TryReadAt9FactTimelineV317203(music, out var musicFact);
            var sfxHasFact = TryReadAt9FactTimelineV317203(sfx, out var sfxFact);
            var voHasFact = TryReadAt9FactTimelineV317203(vo, out var voFact);

            if (musicPcm is null ||
                sfxPcm is null ||
                voPcm is null)
            {
                Console.Error.WriteLine(
                    "[LOADER][WARN] bink2.ds_intro_per_stem_failed " +
                    "reason=stem-decode");
                return null;
            }

            var logoSamples = checked(
                (long)Math.Round(
                    DemonSoulsOpeningTimelineProfileV31716
                        .LogoIntroDurationSeconds * RequiredSampleRate,
                    MidpointRounding.AwayFromZero));

            var targetSamples = checked(
                (long)Math.Round(
                    DemonSoulsOpeningTimelineProfileV31716
                        .AttractDurationSeconds * RequiredSampleRate,
                    MidpointRounding.AwayFromZero));

            var fullOpeningSamples =
                checked(logoSamples + targetSamples);

            // 500 ms tolerance covers AT9/decoder padding without ever
            // confusing an actual 12-second opening segment with codec delay.
            var classificationTolerance =
                RequiredSampleRate / 2L;

                                    // V31.7.20.4_FACT_TAIL_ATTRACT_ALIGNMENT
            long SelectStemStart(
                long decodedSamples,
                bool hasFact,
                At9FactTimelineV317203 fact,
                out string policy,
                out long logicalSamples,
                out long decodedExcess,
                out long primingSamples)
            {
                logicalSamples =
                    hasFact && fact.SampleCount > 0
                        ? fact.SampleCount
                        : decodedSamples;
                decodedExcess = Math.Max(0, decodedSamples - logicalSamples);

                var reportedEncoderDelay =
                    hasFact ? Math.Max(0, fact.EncoderDelaySamples) : 0;
                primingSamples =
                    reportedEncoderDelay > 0 &&
                    decodedExcess >= reportedEncoderDelay
                        ? reportedEncoderDelay
                        : 0;

                // FACT is authoritative for the logical stream length. The
                // Demon's Souls opening stems contain a prefix followed by the
                // attract program. Tail-align the exact attract duration against
                // SampleCount, then map logical sample zero into decoded PCM by
                // adding only the proven front encoder priming.
                if (hasFact && logicalSamples >= targetSamples)
                {
                    var logicalPrefixSamples =
                        checked(logicalSamples - targetSamples);
                    policy = primingSamples > 0
                        ? "fact-tail-attract+at9-encoder-delay"
                        : "fact-tail-attract";
                    return checked(logicalPrefixSamples + primingSamples);
                }

                // Metadata unavailable/inapplicable: retain the prior heuristic
                // rather than inventing a tail boundary.
                if (decodedSamples >=
                    fullOpeningSamples - classificationTolerance)
                {
                    policy = primingSamples > 0
                        ? "fallback-full-opening+at9-encoder-delay"
                        : "fallback-full-opening";
                    return checked(logoSamples + primingSamples);
                }

                if (decodedSamples >=
                    targetSamples - classificationTolerance)
                {
                    policy = primingSamples > 0
                        ? "fallback-attract-only+at9-encoder-delay"
                        : "fallback-attract-only";
                    return primingSamples;
                }

                policy = primingSamples > 0
                    ? "fallback-short-attract-pad-end+at9-encoder-delay"
                    : "fallback-short-attract-pad-end";
                return primingSamples;
            }

            var musicStart = SelectStemStart(
                musicSamples, musicHasFact, musicFact,
                out var musicPolicy, out var musicLogicalSamples,
                out var musicDecodedExcess, out var musicPrimingSamples);
            var sfxStart = SelectStemStart(
                sfxSamples, sfxHasFact, sfxFact,
                out var sfxPolicy, out var sfxLogicalSamples,
                out var sfxDecodedExcess, out var sfxPrimingSamples);
            var voStart = SelectStemStart(
                voSamples, voHasFact, voFact,
                out var voPolicy, out var voLogicalSamples,
                out var voDecodedExcess, out var voPrimingSamples);

            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.ds_intro_at9_fact " +
                $"stem=music present={musicHasFact} logical_samples={musicLogicalSamples} " +
                $"decoded_samples={musicSamples} decoded_excess={musicDecodedExcess} " +
                $"input_overlap_delay={(musicHasFact ? musicFact.InputOverlapDelaySamples : 0)} " +
                $"encoder_delay={(musicHasFact ? musicFact.EncoderDelaySamples : 0)} " +
                $"priming_applied={musicPrimingSamples} trim_start={musicStart}");
            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.ds_intro_at9_fact " +
                $"stem=sfx present={sfxHasFact} logical_samples={sfxLogicalSamples} " +
                $"decoded_samples={sfxSamples} decoded_excess={sfxDecodedExcess} " +
                $"input_overlap_delay={(sfxHasFact ? sfxFact.InputOverlapDelaySamples : 0)} " +
                $"encoder_delay={(sfxHasFact ? sfxFact.EncoderDelaySamples : 0)} " +
                $"priming_applied={sfxPrimingSamples} trim_start={sfxStart}");
            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.ds_intro_at9_fact " +
                $"stem=vo-en present={voHasFact} logical_samples={voLogicalSamples} " +
                $"decoded_samples={voSamples} decoded_excess={voDecodedExcess} " +
                $"input_overlap_delay={(voHasFact ? voFact.InputOverlapDelaySamples : 0)} " +
                $"encoder_delay={(voHasFact ? voFact.EncoderDelaySamples : 0)} " +
                $"priming_applied={voPrimingSamples} trim_start={voStart}");

            static double ToSeconds(long samples) =>
                samples / 48_000.0;

            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.ds_intro_stem_profile " +
                $"stem=music samples={musicSamples} " +
                $"duration_s={ToSeconds(musicSamples):F6} " +
                $"start_sample={musicStart} " +
                $"start_s={ToSeconds(musicStart):F6} " +
                $"policy={musicPolicy}");
            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.ds_intro_stem_profile " +
                $"stem=sfx samples={sfxSamples} " +
                $"duration_s={ToSeconds(sfxSamples):F6} " +
                $"start_sample={sfxStart} " +
                $"start_s={ToSeconds(sfxStart):F6} " +
                $"policy={sfxPolicy}");
            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.ds_intro_stem_profile " +
                $"stem=vo-en samples={voSamples} " +
                $"duration_s={ToSeconds(voSamples):F6} " +
                $"start_sample={voStart} " +
                $"start_s={ToSeconds(voStart):F6} " +
                $"policy={voPolicy}");

            var output = Path.Combine(
                cacheDirectory,
                $"demons-souls-intro-{key}-v31720-stemalign-" +
                $"m{musicStart}-s{sfxStart}-v{voStart}-" +
                $"n{targetSamples}.wav");

            if (IsPlayableWave(output) &&
                TryReadPcmWaveSampleFramesV31716(
                    output,
                    out var cachedOutputRate,
                    out var cachedOutputSamples) &&
                cachedOutputRate == RequiredSampleRate &&
                Math.Abs(cachedOutputSamples - targetSamples) <= 1)
            {
                Console.Error.WriteLine(
                    "[LOADER][INFO] bink2.ds_intro_per_stem_mix " +
                    $"cache=True target_samples={targetSamples} " +
                    $"music_start={musicStart} sfx_start={sfxStart} " +
                    $"vo_start={voStart} wav='{output}'");
                return output;
            }

            TryDelete(output);
            var tempOutput =
                output + ".tmp-" + Guid.NewGuid().ToString("N") + ".wav";

            string StemFilter(
                int index,
                long start,
                string outputLabel)
            {
                var requestedEnd = checked(start + targetSamples);
                return
                    $"[{index}:a]" +
                    $"atrim=start_sample={start}:end_sample={requestedEnd}," +
                    "asetpts=PTS-STARTPTS," +
                    $"apad=whole_len={targetSamples}," +
                    $"atrim=end_sample={targetSamples}," +
                    $"asetpts=PTS-STARTPTS[{outputLabel}]";
            }

            var filter =
                StemFilter(0, musicStart, "m") + ";" +
                StemFilter(1, sfxStart, "s") + ";" +
                StemFilter(2, voStart, "v") + ";" +
                "[m][s][v]amix=inputs=3:duration=longest:" +
                "dropout_transition=0:normalize=1," +
                $"atrim=end_sample={targetSamples}," +
                "asetpts=PTS-STARTPTS[out]";

            var mixArgs = new[]
            {
                "-hide_banner",
                "-loglevel", "error",
                "-nostdin",
                "-y",
                "-i", musicPcm,
                "-i", sfxPcm,
                "-i", voPcm,
                "-filter_complex", filter,
                "-map", "[out]",
                "-c:a", "pcm_s16le",
                "-ar", "48000",
                "-ac", "2",
                tempOutput,
            };

            if (!RunFfmpeg(ffmpeg, mixArgs))
            {
                TryDelete(tempOutput);
                return null;
            }

            var finalRate = 0;
            var finalSamples = 0L;
            if (!IsPlayableWave(tempOutput) ||
                !TryReadPcmWaveSampleFramesV31716(
                    tempOutput,
                    out finalRate,
                    out finalSamples) ||
                finalRate != RequiredSampleRate ||
                Math.Abs(finalSamples - targetSamples) > 1)
            {
                TryDelete(tempOutput);
                Console.Error.WriteLine(
                    "[LOADER][WARN] bink2.ds_intro_per_stem_failed " +
                    $"reason=final-sample-count expected={targetSamples} " +
                    $"actual={finalSamples} rate={finalRate}");
                return null;
            }

            File.Move(tempOutput, output, true);

            Console.Error.WriteLine(
                "[LOADER][INFO] bink2.ds_intro_per_stem_mix " +
                $"cache=False target_samples={targetSamples} " +
                $"music_start={musicStart} sfx_start={sfxStart} " +
                $"vo_start={voStart} " +
                $"policies='{musicPolicy};{sfxPolicy};{voPolicy}' " +
                $"wav='{output}'");

            return output;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(
                "[LOADER][WARN] bink2.ds_intro_audio_prepare_failed " +
                $"mode=per-stem-v31720 type={ex.GetType().Name} " +
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


