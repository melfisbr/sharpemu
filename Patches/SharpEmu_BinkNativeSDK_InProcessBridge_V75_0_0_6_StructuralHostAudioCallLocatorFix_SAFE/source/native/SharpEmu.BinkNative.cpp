// SharpEmu.BinkNative.dll
// SharpEmu-owned stable ABI -> licensed RAD Bink SDK.
// This source intentionally contains no RAD proprietary header/library.
// Build it against a legitimately obtained Bink SDK.

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <atomic>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <string>

#include "bink.h"

#if !defined(BINKSURFACE32RA) && !defined(BINKSURFACE32R) && !defined(BINKSURFACE32)
#error The supplied Bink SDK does not expose a supported 32-bit software surface.
#endif

namespace
{
    constexpr std::uint32_t kAbiVersion = 0x00010000u;
    constexpr std::uint32_t kCapVideo = 1u << 0;
    constexpr std::uint32_t kCapEmbeddedAudio = 1u << 1;
    constexpr std::uint32_t kCapClock = 1u << 2;
    constexpr std::uint32_t kCapBgra = 1u << 3;

    constexpr std::uint32_t kInfoEmbeddedAudioActive = 1u << 0;

    struct SeBinkInfo
    {
        std::uint32_t width;
        std::uint32_t height;
        std::uint32_t fps_num;
        std::uint32_t fps_den;
        std::uint32_t frame_count;
        std::uint32_t audio_track_count;
        std::uint32_t flags;
        std::uint32_t reserved;
    };

    struct Movie
    {
        HBINK bink = nullptr;
        SeBinkInfo info{};
        std::uint32_t next_frame = 0;
        LARGE_INTEGER qpc_frequency{};
        LARGE_INTEGER clock_start{};
        bool clock_started = false;
        std::atomic<bool> skip_requested{false};
        std::mutex gate;
    };

    thread_local std::string g_last_error;
    std::once_flag g_audio_once;
    bool g_audio_ready = false;

    void set_error(const char* message)
    {
        g_last_error = message ? message : "unknown-error";
    }

    std::uint32_t read_u32_le(const unsigned char* p)
    {
        return
            static_cast<std::uint32_t>(p[0]) |
            (static_cast<std::uint32_t>(p[1]) << 8) |
            (static_cast<std::uint32_t>(p[2]) << 16) |
            (static_cast<std::uint32_t>(p[3]) << 24);
    }

    bool read_header(const char* path, SeBinkInfo& info)
    {
        FILE* file = nullptr;
        if (fopen_s(&file, path, "rb") != 0 || !file)
        {
            set_error("file-open-failed");
            return false;
        }

        unsigned char header[44]{};
        const auto read = std::fread(header, 1, sizeof(header), file);
        std::fclose(file);

        if (read < sizeof(header))
        {
            set_error("short-bink-header");
            return false;
        }

        if (header[0] != 'K' ||
            header[1] != 'B' ||
            header[2] != '2')
        {
            set_error("not-kb2");
            return false;
        }

        info.frame_count = read_u32_le(header + 8);
        info.width = read_u32_le(header + 0x14);
        info.height = read_u32_le(header + 0x18);
        info.fps_num = read_u32_le(header + 0x1C);
        info.fps_den = read_u32_le(header + 0x20);
        info.audio_track_count = read_u32_le(header + 40);

        if (info.width == 0 ||
            info.height == 0 ||
            info.fps_num == 0 ||
            info.fps_den == 0 ||
            info.frame_count == 0)
        {
            set_error("invalid-kb2-header");
            return false;
        }

        return true;
    }

    void initialize_audio()
    {
        std::call_once(
            g_audio_once,
            []()
            {
#if defined(SHARPEMU_BINK_HAVE_XAUDIO2)
                // Bink SDK history documents that passing zero requests Bink's
                // own XAudio2 device/mastering voice.
                g_audio_ready =
                    BinkSoundUseXAudio2(0) != 0;
#else
                g_audio_ready = false;
#endif
            });
    }

    std::uint32_t choose_surface()
    {
        char requested[32]{};
        const auto length = GetEnvironmentVariableA(
            "SHARPEMU_BINK_NATIVE_SURFACE",
            requested,
            static_cast<DWORD>(sizeof(requested)));

        if (length > 0 && length < sizeof(requested))
        {
#if defined(BINKSURFACE32RA)
            if (_stricmp(requested, "32RA") == 0)
                return BINKSURFACE32RA;
#endif
#if defined(BINKSURFACE32R)
            if (_stricmp(requested, "32R") == 0)
                return BINKSURFACE32R;
#endif
#if defined(BINKSURFACE32)
            if (_stricmp(requested, "32") == 0)
                return BINKSURFACE32;
#endif
        }

#if defined(BINKSURFACE32RA)
        return BINKSURFACE32RA;
#elif defined(BINKSURFACE32R)
        return BINKSURFACE32R;
#else
        return BINKSURFACE32;
#endif
    }
}

extern "C"
{
    __declspec(dllexport) std::uint32_t __cdecl
    se_bink_abi_version()
    {
        return kAbiVersion;
    }

    __declspec(dllexport) std::uint32_t __cdecl
    se_bink_build_capabilities()
    {
        std::uint32_t caps =
            kCapVideo |
            kCapClock |
            kCapBgra;
#if defined(SHARPEMU_BINK_HAVE_XAUDIO2)
        caps |= kCapEmbeddedAudio;
#endif
        return caps;
    }

    __declspec(dllexport) Movie* __cdecl
    se_bink_open_utf8(
        const char* utf8_path,
        std::uint32_t,
        SeBinkInfo* out_info)
    {
        g_last_error.clear();

        if (!utf8_path ||
            !out_info)
        {
            set_error("invalid-open-arguments");
            return nullptr;
        }

        SeBinkInfo info{};
        if (!read_header(
                utf8_path,
                info))
        {
            return nullptr;
        }

        initialize_audio();

        HBINK bink = BinkOpen(
            const_cast<char*>(utf8_path),
            0);

        if (!bink)
        {
            set_error("BinkOpen-failed");
            return nullptr;
        }

        auto* movie = new (std::nothrow) Movie();
        if (!movie)
        {
            BinkClose(bink);
            set_error("out-of-memory");
            return nullptr;
        }

        movie->bink = bink;
        movie->info = info;

        if (info.audio_track_count > 0 &&
            g_audio_ready)
        {
            movie->info.flags |=
                kInfoEmbeddedAudioActive;
        }

        QueryPerformanceFrequency(
            &movie->qpc_frequency);

        *out_info = movie->info;
        return movie;
    }

    __declspec(dllexport) int __cdecl
    se_bink_decode_bgra(
        Movie* movie,
        void* destination,
        std::size_t destination_bytes,
        int pitch)
    {
        if (!movie ||
            !destination)
        {
            set_error("invalid-decode-arguments");
            return -1;
        }

        const auto required =
            static_cast<std::size_t>(movie->info.width) *
            static_cast<std::size_t>(movie->info.height) *
            4u;

        if (destination_bytes < required ||
            pitch < static_cast<int>(movie->info.width * 4u))
        {
            set_error("destination-too-small");
            return -2;
        }

        std::lock_guard<std::mutex> lock(
            movie->gate);

        if (movie->skip_requested.load(
                std::memory_order_relaxed))
        {
            return 0;
        }

        if (movie->next_frame >=
            movie->info.frame_count)
        {
            return 0;
        }

        // Keep all codec timing/wait work on SharpEmu's dedicated decoder
        // thread. Never block the Vulkan presenter or guest CPU.
        while (BinkWait(movie->bink))
        {
            if (movie->skip_requested.load(
                    std::memory_order_relaxed))
            {
                return 0;
            }
            Sleep(1);
        }

        BinkDoFrame(movie->bink);

        BinkCopyToBuffer(
            movie->bink,
            destination,
            pitch,
            movie->info.height,
            0,
            0,
            choose_surface());

        if (!movie->clock_started)
        {
            QueryPerformanceCounter(
                &movie->clock_start);
            movie->clock_started = true;
        }

        ++movie->next_frame;

        if (movie->next_frame <
            movie->info.frame_count)
        {
            BinkNextFrame(movie->bink);
        }

        return 1;
    }

    __declspec(dllexport) int __cdecl
    se_bink_get_clock_us(
        Movie* movie,
        std::int64_t* microseconds)
    {
        if (!movie ||
            !microseconds ||
            !movie->clock_started ||
            movie->qpc_frequency.QuadPart <= 0)
        {
            return 0;
        }

        LARGE_INTEGER now{};
        QueryPerformanceCounter(&now);

        const auto delta =
            now.QuadPart -
            movie->clock_start.QuadPart;

        *microseconds =
            static_cast<std::int64_t>(
                (delta * 1000000LL) /
                movie->qpc_frequency.QuadPart);
        return 1;
    }

    __declspec(dllexport) void __cdecl
    se_bink_request_skip(Movie* movie)
    {
        if (movie)
        {
            movie->skip_requested.store(
                true,
                std::memory_order_relaxed);
        }
    }

    __declspec(dllexport) void __cdecl
    se_bink_close(Movie* movie)
    {
        if (!movie)
        {
            return;
        }

        {
            std::lock_guard<std::mutex> lock(
                movie->gate);

            movie->skip_requested.store(
                true,
                std::memory_order_relaxed);

            if (movie->bink)
            {
                BinkClose(movie->bink);
                movie->bink = nullptr;
            }
        }

        delete movie;
    }

    __declspec(dllexport) const char* __cdecl
    se_bink_last_error_utf8()
    {
        return g_last_error.c_str();
    }
}
