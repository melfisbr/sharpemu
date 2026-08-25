// SharpEmu Bink2 x64 native A/V adapter - V75.0.3
// Clean-room interoperability bridge: contains no RAD/Bink codec implementation or proprietary headers.
// It exposes SharpEmu ABI 0x00010000, dynamically binds a user-supplied compatible x64 Bink2 runtime,
// decodes/copies video frames to BGRA, and configures the runtime's native audio backend so embedded
// Bink audio is decoded and played in-process on the same Bink timeline.

typedef unsigned char u8;
typedef unsigned int u32;
typedef unsigned long long u64;
typedef long long i64;
typedef unsigned long long usize;
typedef int BOOL;
typedef unsigned long DWORD;
typedef void* HANDLE;
typedef void* HMODULE;
typedef void* FARPROC;
typedef const char* LPCSTR;
typedef void* LPVOID;
typedef struct { i64 QuadPart; } LARGE_INTEGER;
typedef struct __declspec(align(8)) { i64 opaque[5]; } CRITICAL_SECTION_OPAQUE;

#define WINAPI __stdcall
#define CDECL __cdecl
#define DLL_EXPORT __declspec(dllexport)
#define DLL_IMPORT __declspec(dllimport)
#define INVALID_HANDLE_VALUE ((HANDLE)(i64)-1)
#define GENERIC_READ 0x80000000UL
#define FILE_SHARE_READ 0x00000001UL
#define OPEN_EXISTING 3UL
#define FILE_ATTRIBUTE_NORMAL 0x00000080UL
#define HEAP_ZERO_MEMORY 0x00000008UL
#define GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS 0x00000004UL
#define GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT 0x00000002UL

DLL_IMPORT HMODULE WINAPI LoadLibraryA(LPCSTR);
DLL_IMPORT BOOL WINAPI FreeLibrary(HMODULE);
DLL_IMPORT FARPROC WINAPI GetProcAddress(HMODULE, LPCSTR);
DLL_IMPORT BOOL WINAPI GetModuleHandleExA(DWORD, LPCSTR, HMODULE*);
DLL_IMPORT DWORD WINAPI GetModuleFileNameA(HMODULE, char*, DWORD);
DLL_IMPORT DWORD WINAPI GetCurrentDirectoryA(DWORD, char*);
DLL_IMPORT DWORD WINAPI GetEnvironmentVariableA(LPCSTR, char*, DWORD);
DLL_IMPORT HANDLE WINAPI CreateFileA(LPCSTR, DWORD, DWORD, LPVOID, DWORD, DWORD, HANDLE);
DLL_IMPORT BOOL WINAPI ReadFile(HANDLE, LPVOID, DWORD, DWORD*, LPVOID);
DLL_IMPORT BOOL WINAPI CloseHandle(HANDLE);
DLL_IMPORT DWORD WINAPI GetLastError(void);
DLL_IMPORT void WINAPI Sleep(DWORD);
DLL_IMPORT BOOL WINAPI QueryPerformanceCounter(LARGE_INTEGER*);
DLL_IMPORT BOOL WINAPI QueryPerformanceFrequency(LARGE_INTEGER*);
DLL_IMPORT HANDLE WINAPI GetProcessHeap(void);
DLL_IMPORT LPVOID WINAPI HeapAlloc(HANDLE, DWORD, usize);
DLL_IMPORT BOOL WINAPI HeapFree(HANDLE, DWORD, LPVOID);
DLL_IMPORT void WINAPI InitializeCriticalSection(CRITICAL_SECTION_OPAQUE*);
DLL_IMPORT void WINAPI EnterCriticalSection(CRITICAL_SECTION_OPAQUE*);
DLL_IMPORT void WINAPI LeaveCriticalSection(CRITICAL_SECTION_OPAQUE*);
DLL_IMPORT void WINAPI DeleteCriticalSection(CRITICAL_SECTION_OPAQUE*);
DLL_IMPORT long WINAPI InterlockedExchange(volatile long*, long);

typedef void* BinkHandle;
typedef BinkHandle (CDECL *BinkOpenFn)(const char*, u64);
typedef void (CDECL *BinkCloseFn)(BinkHandle);
typedef int (CDECL *BinkWaitFn)(BinkHandle);
typedef int (CDECL *BinkDoFrameFn)(BinkHandle);
typedef int (CDECL *BinkCopyToBufferFn)(BinkHandle, void*, int, u32, u32, u32, u32);
typedef void (CDECL *BinkNextFrameFn)(BinkHandle);
typedef const char* (CDECL *BinkGetErrorFn)(void);
// BINKSNDSYSOPEN in public interoperability headers is a callback factory. At the ABI
// boundary only the pointer width matters on Windows x64.
typedef void* (CDECL *BinkSoundSystemOpenFn)(usize);
typedef int (CDECL *BinkSetSoundSystemFn)(BinkSoundSystemOpenFn, usize);
typedef int (CDECL *BinkSetSoundOnOffFn)(BinkHandle, int);
typedef void (CDECL *BinkSetSoundTrackFn)(u32, u32*);
typedef void (CDECL *BinkServiceFn)(BinkHandle);

typedef struct SeBinkInfo {
    u32 width;
    u32 height;
    u32 fps_num;
    u32 fps_den;
    u32 frame_count;
    u32 audio_track_count;
    u32 flags;
    u32 reserved;
} SeBinkInfo;

typedef struct RuntimeApi {
    HMODULE module;
    BinkOpenFn open;
    BinkCloseFn close;
    BinkWaitFn wait;
    BinkDoFrameFn do_frame;
    BinkCopyToBufferFn copy_to_buffer;
    BinkNextFrameFn next_frame;
    BinkGetErrorFn get_error;
    BinkSetSoundSystemFn set_sound_system;
    BinkSetSoundOnOffFn set_sound_on_off;
    BinkSetSoundTrackFn set_sound_track;
    BinkServiceFn service;
    BinkSoundSystemOpenFn sound_open_xaudio29;
    BinkSoundSystemOpenFn sound_open_xaudio28;
    BinkSoundSystemOpenFn sound_open_xaudio27;
    BinkSoundSystemOpenFn sound_open_xaudio2;
    BinkSoundSystemOpenFn sound_open_waveout;
    BinkSoundSystemOpenFn sound_open_directsound;
    int audio_system_configured;
    char audio_backend[32];
    char path[1024];
} RuntimeApi;

typedef struct Movie {
    RuntimeApi* runtime;
    BinkHandle bink;
    SeBinkInfo info;
    u32 next_frame;
    LARGE_INTEGER qpc_frequency;
    LARGE_INTEGER clock_start;
    int clock_started;
    volatile long skip_requested;
    CRITICAL_SECTION_OPAQUE gate;
} Movie;


void* memcpy(void* dst, const void* src, usize n) {
    u8* d=(u8*)dst; const u8* x=(const u8*)src; usize i;
    for(i=0;i<n;++i) d[i]=x[i];
    return dst;
}

void* memset(void* dst, int value, usize n) {
    u8* d=(u8*)dst; usize i;
    for(i=0;i<n;++i) d[i]=(u8)value;
    return dst;
}

static RuntimeApi g_runtime;
static char g_last_error[1024];
static DWORD g_best_load_error;

DLL_EXPORT u32 CDECL se_bink_abi_version(void);

static void mem_zero(void* p, usize n) {
    u8* b = (u8*)p;
    usize i;
    for (i = 0; i < n; ++i) b[i] = 0;
}

static usize str_len(const char* s) {
    usize n = 0;
    if (!s) return 0;
    while (s[n]) ++n;
    return n;
}

static void str_copy(char* dst, usize cap, const char* src) {
    usize i = 0;
    if (!dst || cap == 0) return;
    if (!src) { dst[0] = 0; return; }
    while (i + 1 < cap && src[i]) { dst[i] = src[i]; ++i; }
    dst[i] = 0;
}

static int str_append(char* dst, usize cap, const char* src) {
    usize d = str_len(dst), i = 0;
    if (d >= cap) return 0;
    while (src && src[i] && d + i + 1 < cap) { dst[d + i] = src[i]; ++i; }
    if (src && src[i]) return 0;
    dst[d + i] = 0;
    return 1;
}

static void append_u32_dec(char* dst, usize cap, u32 v) {
    char tmp[16];
    int n = 0, i;
    if (v == 0) { str_append(dst, cap, "0"); return; }
    while (v && n < 15) { tmp[n++] = (char)('0' + (v % 10)); v /= 10; }
    for (i = n - 1; i >= 0; --i) {
        char c[2]; c[0] = tmp[i]; c[1] = 0; str_append(dst, cap, c);
    }
}

static void set_error(const char* s) { str_copy(g_last_error, sizeof(g_last_error), s ? s : "unknown-error"); }

static u32 read_u32_le(const u8* p) {
    return ((u32)p[0]) | ((u32)p[1] << 8) | ((u32)p[2] << 16) | ((u32)p[3] << 24);
}

__declspec(noinline) static int read_header(const char* path, SeBinkInfo* info) {
    HANDLE h;
    DWORD got = 0;
    u8 header[44];
    if (!path || !info) { set_error("invalid-header-arguments"); return 0; }
    h = CreateFileA(path, GENERIC_READ, FILE_SHARE_READ, (LPVOID)0, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, (HANDLE)0);
    if (h == INVALID_HANDLE_VALUE) { set_error("file-open-failed"); return 0; }
    mem_zero(header, sizeof(header));
    if (!ReadFile(h, header, (DWORD)sizeof(header), &got, (LPVOID)0) || got < sizeof(header)) {
        CloseHandle(h); set_error("short-bink-header"); return 0;
    }
    CloseHandle(h);
    if (header[0] != 'K' || header[1] != 'B' || header[2] != '2') { set_error("not-kb2"); return 0; }
    mem_zero(info, sizeof(*info));
    info->frame_count = read_u32_le(header + 8);
    info->width = read_u32_le(header + 0x14);
    info->height = read_u32_le(header + 0x18);
    info->fps_num = read_u32_le(header + 0x1C);
    info->fps_den = read_u32_le(header + 0x20);
    info->audio_track_count = read_u32_le(header + 40);
    if (!info->width || !info->height || info->width > 16384 || info->height > 16384 || !info->fps_num || !info->fps_den || !info->frame_count) {
        set_error("invalid-kb2-header"); return 0;
    }
    return 1;
}

static int get_self_dir(char* out, usize cap) {
    HMODULE self = (HMODULE)0;
    DWORD n;
    usize i;
    if (!out || cap < 4) return 0;
    out[0] = 0;
    if (!GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                            (LPCSTR)(void*)&se_bink_abi_version, &self)) return 0;
    n = GetModuleFileNameA(self, out, (DWORD)cap);
    if (!n || n >= cap) { out[0] = 0; return 0; }
    i = n;
    while (i > 0) {
        --i;
        if (out[i] == '\\' || out[i] == '/') { out[i] = 0; return 1; }
    }
    out[0] = 0;
    return 0;
}

static FARPROC proc(HMODULE m, const char* n) { return GetProcAddress(m, n); }

__declspec(noinline) static int bind_module(HMODULE module, const char* path) {
    RuntimeApi api;
    if (!module) return 0;
    mem_zero(&api, sizeof(api));
    api.module = module;
    api.open = (BinkOpenFn)(void*)proc(module, "BinkOpen");
    api.close = (BinkCloseFn)(void*)proc(module, "BinkClose");
    api.wait = (BinkWaitFn)(void*)proc(module, "BinkWait");
    api.do_frame = (BinkDoFrameFn)(void*)proc(module, "BinkDoFrame");
    api.copy_to_buffer = (BinkCopyToBufferFn)(void*)proc(module, "BinkCopyToBuffer");
    api.next_frame = (BinkNextFrameFn)(void*)proc(module, "BinkNextFrame");
    api.get_error = (BinkGetErrorFn)(void*)proc(module, "BinkGetError");
    api.set_sound_system = (BinkSetSoundSystemFn)(void*)proc(module, "BinkSetSoundSystem");
    api.set_sound_on_off = (BinkSetSoundOnOffFn)(void*)proc(module, "BinkSetSoundOnOff");
    api.set_sound_track = (BinkSetSoundTrackFn)(void*)proc(module, "BinkSetSoundTrack");
    api.service = (BinkServiceFn)(void*)proc(module, "BinkService");
    api.sound_open_xaudio29 = (BinkSoundSystemOpenFn)(void*)proc(module, "BinkOpenXAudio29");
    api.sound_open_xaudio28 = (BinkSoundSystemOpenFn)(void*)proc(module, "BinkOpenXAudio28");
    api.sound_open_xaudio27 = (BinkSoundSystemOpenFn)(void*)proc(module, "BinkOpenXAudio27");
    api.sound_open_xaudio2 = (BinkSoundSystemOpenFn)(void*)proc(module, "BinkOpenXAudio2");
    api.sound_open_waveout = (BinkSoundSystemOpenFn)(void*)proc(module, "BinkOpenWaveOut");
    api.sound_open_directsound = (BinkSoundSystemOpenFn)(void*)proc(module, "BinkOpenDirectSound");
    if (!api.open || !api.close || !api.wait || !api.do_frame || !api.copy_to_buffer || !api.next_frame) {
        FreeLibrary(module);
        return 0;
    }
    str_copy(api.path, sizeof(api.path), path ? path : "loaded-runtime");
    g_runtime = api;
    return 1;
}

__declspec(noinline) static int try_load(const char* path) {
    HMODULE m;
    DWORD e;
    if (!path || !*path) return 0;
    m = LoadLibraryA(path);
    if (!m) {
        e = GetLastError();
        if (e == 193 || g_best_load_error == 0) g_best_load_error = e;
        return 0;
    }
    return bind_module(m, path);
}

__declspec(noinline) static int try_sibling(const char* dir, const char* leaf) {
    char path[1024];
    if (!dir || !*dir || !leaf || !*leaf) return 0;
    path[0] = 0;
    str_copy(path, sizeof(path), dir);
    if (!str_append(path, sizeof(path), "\\")) return 0;
    if (!str_append(path, sizeof(path), leaf)) return 0;
    return try_load(path);
}

__declspec(noinline) static int ensure_runtime(void) {
    char explicit_path[1024];
    char dir[1024];
    DWORD n;
    if (g_runtime.module) return 1;
    g_best_load_error = 0;
    explicit_path[0] = 0;
    n = GetEnvironmentVariableA("SHARPEMU_BINK_RUNTIME_DLL", explicit_path, (DWORD)sizeof(explicit_path));
    if (n > 0 && n < sizeof(explicit_path) && try_load(explicit_path)) return 1;

    dir[0] = 0;
    if (get_self_dir(dir, sizeof(dir))) {
        if (try_sibling(dir, "bink2w64.dll")) return 1;
        if (try_sibling(dir, "New Engines.dll")) return 1;
        if (try_sibling(dir, "New Engines\\bink2w64.dll")) return 1;
        if (try_sibling(dir, "Old Engines.dll")) return 1;
        if (try_sibling(dir, "Original.dll")) return 1;
    }

    // Standard Windows DLL search, useful when a legitimate runtime is beside SharpEmu.exe.
    if (try_load("bink2w64.dll")) return 1;

    set_error("compatible-x64-bink2-runtime-not-found:last-win32=");
    append_u32_dec(g_last_error, sizeof(g_last_error), (u32)g_best_load_error);
    if (g_best_load_error == 193) str_append(g_last_error, sizeof(g_last_error), ":bad-exe-format-probable-32bit-dll");
    return 0;
}

static int ascii_eq_ci(const char* a, const char* b) {
    usize i = 0;
    if (!a || !b) return 0;
    while (a[i] && b[i]) {
        char ca = a[i], cb = b[i];
        if (ca >= 'A' && ca <= 'Z') ca = (char)(ca + ('a' - 'A'));
        if (cb >= 'A' && cb <= 'Z') cb = (char)(cb + ('a' - 'A'));
        if (ca != cb) return 0;
        ++i;
    }
    return a[i] == 0 && b[i] == 0;
}

static int try_sound_backend(BinkSoundSystemOpenFn open_fn, const char* name) {
    if (!g_runtime.set_sound_system || !open_fn) return 0;
    if (g_runtime.set_sound_system(open_fn, (usize)0) == 0) return 0;
    g_runtime.audio_system_configured = 1;
    str_copy(g_runtime.audio_backend, sizeof(g_runtime.audio_backend), name);
    return 1;
}

__declspec(noinline) static int ensure_audio_system(void) {
    char requested[64];
    DWORD n;
    if (g_runtime.audio_system_configured) return 1;
    if (!g_runtime.set_sound_system) {
        set_error("bink-runtime-has-no-BinkSetSoundSystem");
        return 0;
    }

    requested[0] = 0;
    n = GetEnvironmentVariableA("SHARPEMU_BINK_AUDIO_BACKEND", requested, (DWORD)sizeof(requested));
    if (n > 0 && n < sizeof(requested)) {
        if (ascii_eq_ci(requested, "off") || ascii_eq_ci(requested, "none")) {
            set_error("native-bink-audio-disabled-by-environment");
            return 0;
        }
        if (ascii_eq_ci(requested, "xaudio29") && try_sound_backend(g_runtime.sound_open_xaudio29, "xaudio29")) return 1;
        if (ascii_eq_ci(requested, "xaudio28") && try_sound_backend(g_runtime.sound_open_xaudio28, "xaudio28")) return 1;
        if (ascii_eq_ci(requested, "xaudio27") && try_sound_backend(g_runtime.sound_open_xaudio27, "xaudio27")) return 1;
        if (ascii_eq_ci(requested, "xaudio2") && try_sound_backend(g_runtime.sound_open_xaudio2, "xaudio2")) return 1;
        if (ascii_eq_ci(requested, "waveout") && try_sound_backend(g_runtime.sound_open_waveout, "waveout")) return 1;
        if (ascii_eq_ci(requested, "directsound") && try_sound_backend(g_runtime.sound_open_directsound, "directsound")) return 1;
        set_error("requested-native-bink-audio-backend-unavailable");
        return 0;
    }

    // Prefer the newest XAudio export when available, then fall back through older
    // XAudio entry points and finally the very broadly compatible WaveOut backend.
    if (try_sound_backend(g_runtime.sound_open_xaudio29, "xaudio29")) return 1;
    if (try_sound_backend(g_runtime.sound_open_xaudio28, "xaudio28")) return 1;
    if (try_sound_backend(g_runtime.sound_open_xaudio2, "xaudio2")) return 1;
    if (try_sound_backend(g_runtime.sound_open_xaudio27, "xaudio27")) return 1;
    if (try_sound_backend(g_runtime.sound_open_waveout, "waveout")) return 1;
    if (try_sound_backend(g_runtime.sound_open_directsound, "directsound")) return 1;

    set_error("compatible-native-bink-audio-backend-not-found");
    return 0;
}

static u32 selected_audio_track(u32 track_count) {
    char value[32];
    DWORD n;
    u32 result = 0;
    usize i;
    if (track_count == 0) return 0;
    value[0] = 0;
    n = GetEnvironmentVariableA("SHARPEMU_BINK_AUDIO_TRACK", value, (DWORD)sizeof(value));
    if (n == 0 || n >= sizeof(value)) return 0;
    result = 0;
    for (i = 0; value[i]; ++i) {
        if (value[i] < '0' || value[i] > '9') return 0;
        result = result * 10u + (u32)(value[i] - '0');
        if (result >= track_count) return 0;
    }
    return result;
}

static const char* runtime_error(void) {
    const char* p;
    if (g_runtime.get_error) {
        p = g_runtime.get_error();
        if (p && *p) return p;
    }
    return "bink-runtime-error";
}

DLL_EXPORT u32 CDECL se_bink_abi_version(void) { return 0x00010000u; }

DLL_EXPORT u32 CDECL se_bink_build_capabilities(void) {
    // video | embedded audio | clock | BGRA. Audio becomes active per movie only
    // after a native Bink sound backend has been configured successfully.
    return (1u << 0) | (1u << 1) | (1u << 2) | (1u << 3);
}

DLL_EXPORT Movie* CDECL se_bink_open_utf8(const char* utf8_path, u32 flags, SeBinkInfo* out_info) {
    SeBinkInfo info;
    BinkHandle bink;
    Movie* movie;
    HANDLE heap;
    (void)flags;
    g_last_error[0] = 0;
    if (!utf8_path || !out_info) { set_error("invalid-open-arguments"); return (Movie*)0; }
    if (!read_header(utf8_path, &info)) return (Movie*)0;
    if (!ensure_runtime()) return (Movie*)0;

    // Bink sound system selection is global and must happen before BinkOpen.
    // For movies with embedded audio, fail the native path rather than silently
    // claiming audio ownership. SharpEmu can then take an explicit fallback.
    if (info.audio_track_count > 0) {
        u32 track = selected_audio_track(info.audio_track_count);
        if (!ensure_audio_system()) return (Movie*)0;
        if (g_runtime.set_sound_track) g_runtime.set_sound_track(1u, &track);
    }

    bink = g_runtime.open(utf8_path, 0);
    if (!bink) {
        set_error("BinkOpen-failed:");
        str_append(g_last_error, sizeof(g_last_error), runtime_error());
        return (Movie*)0;
    }
    if (info.audio_track_count > 0 && g_runtime.audio_system_configured) {
        if (g_runtime.set_sound_on_off) g_runtime.set_sound_on_off(bink, 1);
        info.flags |= 1u; // InfoFlagEmbeddedAudioActive
    }

    heap = GetProcessHeap();
    movie = (Movie*)HeapAlloc(heap, HEAP_ZERO_MEMORY, sizeof(Movie));
    if (!movie) { g_runtime.close(bink); set_error("out-of-memory"); return (Movie*)0; }
    movie->runtime = &g_runtime;
    movie->bink = bink;
    movie->info = info;
    QueryPerformanceFrequency(&movie->qpc_frequency);
    InitializeCriticalSection(&movie->gate);
    *out_info = info;
    return movie;
}

DLL_EXPORT int CDECL se_bink_decode_bgra(Movie* movie, void* destination, usize destination_bytes, int pitch) {
    usize required;
    int copied;
    u32 copy_flags;
    if (!movie || !destination || !movie->runtime || !movie->bink) { set_error("invalid-decode-arguments"); return -1; }
    required = (usize)movie->info.width * (usize)movie->info.height * 4u;
    if (destination_bytes < required || pitch < (int)(movie->info.width * 4u)) { set_error("destination-too-small"); return -2; }
    EnterCriticalSection(&movie->gate);
    if (movie->skip_requested || movie->next_frame >= movie->info.frame_count) { LeaveCriticalSection(&movie->gate); return 0; }
    while (movie->runtime->wait(movie->bink) != 0) {
        if (movie->skip_requested) { LeaveCriticalSection(&movie->gate); return 0; }
        if (movie->runtime->service) movie->runtime->service(movie->bink);
        Sleep(1);
    }
    movie->runtime->do_frame(movie->bink);
    if (movie->runtime->service) movie->runtime->service(movie->bink);
    copy_flags = 0x80000000u | 5u; // COPYALL | BGRA surface used by established Bink2 interop wrappers.
    copied = movie->runtime->copy_to_buffer(movie->bink, destination, pitch, movie->info.height, 0, 0, copy_flags);
    if (copied < 0) {
        set_error("BinkCopyToBuffer-failed:");
        str_append(g_last_error, sizeof(g_last_error), runtime_error());
        LeaveCriticalSection(&movie->gate);
        return -3;
    }
    if (!movie->clock_started) { QueryPerformanceCounter(&movie->clock_start); movie->clock_started = 1; }
    ++movie->next_frame;
    if (movie->next_frame < movie->info.frame_count) movie->runtime->next_frame(movie->bink);
    LeaveCriticalSection(&movie->gate);
    return 1;
}

DLL_EXPORT int CDECL se_bink_get_clock_us(Movie* movie, i64* microseconds) {
    LARGE_INTEGER now;
    i64 delta;
    if (!movie || !microseconds || !movie->clock_started || movie->qpc_frequency.QuadPart <= 0) return 0;
    QueryPerformanceCounter(&now);
    delta = now.QuadPart - movie->clock_start.QuadPart;
    *microseconds = (delta * 1000000LL) / movie->qpc_frequency.QuadPart;
    return 1;
}

DLL_EXPORT void CDECL se_bink_request_skip(Movie* movie) {
    if (movie) InterlockedExchange(&movie->skip_requested, 1);
}

DLL_EXPORT void CDECL se_bink_close(Movie* movie) {
    HANDLE heap;
    if (!movie) return;
    EnterCriticalSection(&movie->gate);
    if (movie->runtime && movie->bink) {
        if (movie->info.audio_track_count > 0 && movie->runtime->set_sound_on_off)
            movie->runtime->set_sound_on_off(movie->bink, 0);
        movie->runtime->close(movie->bink);
        movie->bink = (BinkHandle)0;
    }
    LeaveCriticalSection(&movie->gate);
    DeleteCriticalSection(&movie->gate);
    heap = GetProcessHeap();
    HeapFree(heap, 0, movie);
}

DLL_EXPORT const char* CDECL se_bink_last_error_utf8(void) {
    return g_last_error[0] ? g_last_error : "";
}
