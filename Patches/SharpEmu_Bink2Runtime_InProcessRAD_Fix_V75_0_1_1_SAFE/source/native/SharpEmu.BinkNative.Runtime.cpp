// SharpEmu.BinkNative.dll
// V75.0.1.1 - runtime-loaded Bink2 x64 adapter.
//
// This file contains no RAD/Bink proprietary code, header, import library,
// decoder implementation or binary. It only resolves a user-supplied
// compatible bink2w64.dll at runtime and exposes SharpEmu's stable ABI.
//
// Expected SharpEmu ABI:
//   se_bink_abi_version
//   se_bink_build_capabilities
//   se_bink_open_utf8
//   se_bink_decode_bgra
//   se_bink_get_clock_us
//   se_bink_request_skip
//   se_bink_close
//   se_bink_last_error_utf8

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <atomic>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <new>
#include <string>
#include <vector>

namespace
{
    constexpr std::uint32_t kAbiVersion = 0x00010000u;
    constexpr std::uint32_t kCapVideo = 1u << 0;
    constexpr std::uint32_t kCapClock = 1u << 2;
    constexpr std::uint32_t kCapBgra = 1u << 3;

    // Bink copy flags used by long-standing public interoperability headers.
    // Surface 5 is the Bink2 BGRA layout used by public bink2w64 wrappers.
    constexpr std::uint32_t kCopyAll = 0x80000000u;
    constexpr std::uint32_t kDefaultSurfaceBgra = 5u;

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

    using BinkHandle = void*;

    // Windows x64 has one platform calling convention. Using __cdecl keeps
    // the source explicit while remaining compatible with normal x64 exports.
    using BinkOpenFn =
        BinkHandle (__cdecl *)(const char*, std::uint64_t);
    using BinkCloseFn =
        void (__cdecl *)(BinkHandle);
    using BinkWaitFn =
        int (__cdecl *)(BinkHandle);
    using BinkDoFrameFn =
        int (__cdecl *)(BinkHandle);
    using BinkCopyToBufferFn =
        int (__cdecl *)(
            BinkHandle,
            void*,
            int,
            std::uint32_t,
            std::uint32_t,
            std::uint32_t,
            std::uint32_t);
    using BinkNextFrameFn =
        void (__cdecl *)(BinkHandle);
    using BinkGetErrorFn =
        const char* (__cdecl *)();

    struct RuntimeApi
    {
        HMODULE module = nullptr;
        std::wstring path;
        BinkOpenFn open = nullptr;
        BinkCloseFn close = nullptr;
        BinkWaitFn wait = nullptr;
        BinkDoFrameFn do_frame = nullptr;
        BinkCopyToBufferFn copy_to_buffer = nullptr;
        BinkNextFrameFn next_frame = nullptr;
        BinkGetErrorFn get_error = nullptr;
    };

    struct Movie
    {
        RuntimeApi* runtime = nullptr;
        BinkHandle bink = nullptr;
        SeBinkInfo info{};
        std::uint32_t next_frame = 0;
        LARGE_INTEGER qpc_frequency{};
        LARGE_INTEGER clock_start{};
        bool clock_started = false;
        std::atomic<bool> skip_requested{false};
        std::mutex gate;
    };

    std::mutex g_runtime_gate;
    RuntimeApi g_runtime;
    thread_local std::string g_last_error;

    void set_error(const std::string& value)
    {
        g_last_error = value.empty() ? "unknown-error" : value;
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
            info.width > 16384 ||
            info.height > 16384 ||
            info.fps_num == 0 ||
            info.fps_den == 0 ||
            info.frame_count == 0)
        {
            set_error("invalid-kb2-header");
            return false;
        }

        return true;
    }

    std::wstring utf8_to_wide(const char* text)
    {
        if (!text || !*text)
        {
            return {};
        }

        const auto count =
            MultiByteToWideChar(
                CP_UTF8,
                MB_ERR_INVALID_CHARS,
                text,
                -1,
                nullptr,
                0);

        if (count <= 0)
        {
            return {};
        }

        std::wstring result(
            static_cast<std::size_t>(count),
            L'\0');

        if (MultiByteToWideChar(
                CP_UTF8,
                MB_ERR_INVALID_CHARS,
                text,
                -1,
                result.data(),
                count) <= 0)
        {
            return {};
        }

        if (!result.empty() && result.back() == L'\0')
        {
            result.pop_back();
        }

        return result;
    }

    std::wstring module_directory()
    {
        HMODULE self = nullptr;
        if (!GetModuleHandleExW(
                GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                reinterpret_cast<LPCWSTR>(&module_directory),
                &self))
        {
            return {};
        }

        wchar_t path[MAX_PATH]{};
        const auto length =
            GetModuleFileNameW(
                self,
                path,
                static_cast<DWORD>(std::size(path)));

        if (length == 0 ||
            length >= std::size(path))
        {
            return {};
        }

        std::wstring value(path, length);
        const auto slash =
            value.find_last_of(L"\\/");
        if (slash == std::wstring::npos)
        {
            return {};
        }

        value.resize(slash);
        return value;
    }

    bool file_exists(const std::wstring& path)
    {
        if (path.empty())
        {
            return false;
        }

        const auto attributes =
            GetFileAttributesW(path.c_str());
        return attributes != INVALID_FILE_ATTRIBUTES &&
               (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
    }

    std::vector<std::wstring> runtime_candidates()
    {
        std::vector<std::wstring> result;

        auto add_candidate =
            [&result](std::wstring value)
            {
                if (value.empty())
                {
                    return;
                }

                for (const auto& existing : result)
                {
                    if (_wcsicmp(
                            existing.c_str(),
                            value.c_str()) == 0)
                    {
                        return;
                    }
                }

                result.push_back(
                    std::move(value));
            };

        wchar_t explicit_path[32768]{};
        const auto explicit_length =
            GetEnvironmentVariableW(
                L"SHARPEMU_BINK_RUNTIME_DLL",
                explicit_path,
                static_cast<DWORD>(std::size(explicit_path)));

        if (explicit_length > 0 &&
            explicit_length < std::size(explicit_path))
        {
            add_candidate(
                std::wstring(
                    explicit_path,
                    explicit_length));
        }

        const auto directory =
            module_directory();

        if (!directory.empty())
        {
            add_candidate(
                directory +
                L"\\bink2w64.dll");
        }

        wchar_t process_path[32768]{};
        const auto process_length =
            GetModuleFileNameW(
                nullptr,
                process_path,
                static_cast<DWORD>(std::size(process_path)));

        if (process_length > 0 &&
            process_length < std::size(process_path))
        {
            std::wstring process_directory(
                process_path,
                process_length);
            const auto slash =
                process_directory.find_last_of(
                    L"\\/");

            if (slash != std::wstring::npos)
            {
                process_directory.resize(
                    slash);
                add_candidate(
                    process_directory +
                    L"\\bink2w64.dll");
            }
        }

        wchar_t current_directory[32768]{};
        const auto current_length =
            GetCurrentDirectoryW(
                static_cast<DWORD>(
                    std::size(current_directory)),
                current_directory);

        if (current_length > 0 &&
            current_length < std::size(current_directory))
        {
            add_candidate(
                std::wstring(
                    current_directory,
                    current_length) +
                L"\\bink2w64.dll");
        }

        wchar_t radvideo_path[32768]{};
        const auto radvideo_length =
            GetEnvironmentVariableW(
                L"SHARPEMU_RADVIDEO64",
                radvideo_path,
                static_cast<DWORD>(
                    std::size(radvideo_path)));

        if (radvideo_length > 0 &&
            radvideo_length < std::size(radvideo_path))
        {
            std::wstring rad_directory(
                radvideo_path,
                radvideo_length);
            const auto slash =
                rad_directory.find_last_of(
                    L"\\/");

            if (slash != std::wstring::npos)
            {
                rad_directory.resize(
                    slash);
                add_candidate(
                    rad_directory +
                    L"\\bink2w64.dll");
            }
        }

        wchar_t program_files_x86[32768]{};
        const auto pf_length =
            GetEnvironmentVariableW(
                L"ProgramFiles(x86)",
                program_files_x86,
                static_cast<DWORD>(std::size(program_files_x86)));

        if (pf_length > 0 &&
            pf_length < std::size(program_files_x86))
        {
            add_candidate(
                std::wstring(
                    program_files_x86,
                    pf_length) +
                L"\\RADVideo\\bink2w64.dll");
        }

        wchar_t program_files[32768]{};
        const auto pf64_length =
            GetEnvironmentVariableW(
                L"ProgramFiles",
                program_files,
                static_cast<DWORD>(std::size(program_files)));

        if (pf64_length > 0 &&
            pf64_length < std::size(program_files))
        {
            add_candidate(
                std::wstring(
                    program_files,
                    pf64_length) +
                L"\\RADVideo\\bink2w64.dll");
        }

        wchar_t search_result[32768]{};
        const auto search_length =
            SearchPathW(
                nullptr,
                L"bink2w64.dll",
                nullptr,
                static_cast<DWORD>(
                    std::size(search_result)),
                search_result,
                nullptr);

        if (search_length > 0 &&
            search_length < std::size(search_result))
        {
            add_candidate(
                std::wstring(
                    search_result,
                    search_length));
        }

        return result;
    }

    template <typename T>
    T load_export(
        HMODULE module,
        const char* name)
    {
        return reinterpret_cast<T>(
            GetProcAddress(
                module,
                name));
    }

    bool load_runtime_locked()
    {
        if (g_runtime.module)
        {
            return true;
        }

        for (const auto& candidate : runtime_candidates())
        {
            if (!file_exists(candidate))
            {
                continue;
            }

            const auto module =
                LoadLibraryW(
                    candidate.c_str());

            if (!module)
            {
                continue;
            }

            RuntimeApi api{};
            api.module = module;
            api.path = candidate;
            api.open =
                load_export<BinkOpenFn>(
                    module,
                    "BinkOpen");
            api.close =
                load_export<BinkCloseFn>(
                    module,
                    "BinkClose");
            api.wait =
                load_export<BinkWaitFn>(
                    module,
                    "BinkWait");
            api.do_frame =
                load_export<BinkDoFrameFn>(
                    module,
                    "BinkDoFrame");
            api.copy_to_buffer =
                load_export<BinkCopyToBufferFn>(
                    module,
                    "BinkCopyToBuffer");
            api.next_frame =
                load_export<BinkNextFrameFn>(
                    module,
                    "BinkNextFrame");
            api.get_error =
                load_export<BinkGetErrorFn>(
                    module,
                    "BinkGetError");

            if (!api.open ||
                !api.close ||
                !api.wait ||
                !api.do_frame ||
                !api.copy_to_buffer ||
                !api.next_frame)
            {
                FreeLibrary(module);
                continue;
            }

            g_runtime = api;
            return true;
        }

        set_error(
            "compatible-x64-bink2-runtime-not-found:adapter-ready-external-fallback");
        return false;
    }

    bool ensure_runtime()
    {
        std::lock_guard<std::mutex> lock(
            g_runtime_gate);
        return load_runtime_locked();
    }

    std::uint32_t selected_surface()
    {
        wchar_t value[32]{};
        const auto length =
            GetEnvironmentVariableW(
                L"SHARPEMU_BINK_RUNTIME_SURFACE",
                value,
                static_cast<DWORD>(std::size(value)));

        if (length > 0 &&
            length < std::size(value))
        {
            wchar_t* end = nullptr;
            const auto parsed =
                wcstoul(
                    value,
                    &end,
                    0);

            if (end &&
                *end == L'\0' &&
                parsed <= 15)
            {
                return
                    static_cast<std::uint32_t>(
                        parsed);
            }
        }

        return kDefaultSurfaceBgra;
    }

    std::string runtime_error()
    {
        if (g_runtime.get_error)
        {
            const auto* text =
                g_runtime.get_error();
            if (text && *text)
            {
                return text;
            }
        }

        return "bink-runtime-error";
    }
}

extern "C"
{
    __declspec(dllexport)
    std::uint32_t __cdecl
    se_bink_abi_version()
    {
        return kAbiVersion;
    }

    __declspec(dllexport)
    std::uint32_t __cdecl
    se_bink_build_capabilities()
    {
        // Embedded audio is deliberately NOT advertised. Movies with Bink
        // audio tracks therefore fall back to SharpEmu's external RAD path.
        // Demon's Souls title/menu Binks observed by SharpEmu have zero
        // embedded tracks, so they can use this in-process path safely.
        return
            kCapVideo |
            kCapClock |
            kCapBgra;
    }

    __declspec(dllexport)
    Movie* __cdecl
    se_bink_open_utf8(
        const char* utf8_path,
        std::uint32_t,
        SeBinkInfo* out_info)
    {
        g_last_error.clear();

        if (!utf8_path ||
            !out_info)
        {
            set_error(
                "invalid-open-arguments");
            return nullptr;
        }

        SeBinkInfo info{};
        if (!read_header(
                utf8_path,
                info))
        {
            return nullptr;
        }

        if (!ensure_runtime())
        {
            return nullptr;
        }

        const auto bink =
            g_runtime.open(
                utf8_path,
                0);

        if (!bink)
        {
            set_error(
                "BinkOpen-failed:" +
                runtime_error());
            return nullptr;
        }

        auto* movie =
            new (std::nothrow) Movie();

        if (!movie)
        {
            g_runtime.close(bink);
            set_error(
                "out-of-memory");
            return nullptr;
        }

        movie->runtime =
            &g_runtime;
        movie->bink =
            bink;
        movie->info =
            info;

        QueryPerformanceFrequency(
            &movie->qpc_frequency);

        *out_info =
            movie->info;
        return movie;
    }

    __declspec(dllexport)
    int __cdecl
    se_bink_decode_bgra(
        Movie* movie,
        void* destination,
        std::size_t destination_bytes,
        int pitch)
    {
        if (!movie ||
            !destination ||
            !movie->runtime ||
            !movie->bink)
        {
            set_error(
                "invalid-decode-arguments");
            return -1;
        }

        const auto required =
            static_cast<std::size_t>(
                movie->info.width) *
            static_cast<std::size_t>(
                movie->info.height) *
            4u;

        if (destination_bytes < required ||
            pitch <
                static_cast<int>(
                    movie->info.width * 4u))
        {
            set_error(
                "destination-too-small");
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

        while (movie->runtime->wait(
                   movie->bink) != 0)
        {
            if (movie->skip_requested.load(
                    std::memory_order_relaxed))
            {
                return 0;
            }

            Sleep(1);
        }

        movie->runtime->do_frame(
            movie->bink);

        const auto copy_flags =
            kCopyAll |
            selected_surface();

        const auto copied =
            movie->runtime->copy_to_buffer(
                movie->bink,
                destination,
                pitch,
                movie->info.height,
                0,
                0,
                copy_flags);

        if (copied < 0)
        {
            set_error(
                "BinkCopyToBuffer-failed:" +
                runtime_error());
            return -3;
        }

        if (!movie->clock_started)
        {
            QueryPerformanceCounter(
                &movie->clock_start);
            movie->clock_started =
                true;
        }

        ++movie->next_frame;

        if (movie->next_frame <
            movie->info.frame_count)
        {
            movie->runtime->next_frame(
                movie->bink);
        }

        return 1;
    }

    __declspec(dllexport)
    int __cdecl
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
        QueryPerformanceCounter(
            &now);

        const auto delta =
            now.QuadPart -
            movie->clock_start.QuadPart;

        *microseconds =
            static_cast<std::int64_t>(
                (delta * 1000000LL) /
                movie->qpc_frequency.QuadPart);

        return 1;
    }

    __declspec(dllexport)
    void __cdecl
    se_bink_request_skip(
        Movie* movie)
    {
        if (movie)
        {
            movie->skip_requested.store(
                true,
                std::memory_order_relaxed);
        }
    }

    __declspec(dllexport)
    void __cdecl
    se_bink_close(
        Movie* movie)
    {
        if (!movie)
        {
            return;
        }

        {
            std::lock_guard<std::mutex> lock(
                movie->gate);

            if (movie->runtime &&
                movie->bink)
            {
                movie->runtime->close(
                    movie->bink);
                movie->bink = nullptr;
            }
        }

        delete movie;
    }

    __declspec(dllexport)
    const char* __cdecl
    se_bink_last_error_utf8()
    {
        return g_last_error.c_str();
    }
}
