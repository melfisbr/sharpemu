// SharpEmu Bink2 native headless A/V adapter - V75.0.4
// SPDX-License-Identifier: GPL-2.0-or-later
// Clean-room SharpEmu ABI adapter. Uses the SharpEmu ffmpeg-core executable as
// a headless decoder; no RAD SDK, RAD player, proprietary Bink code or headers.

#define NULL ((void*)0)
typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;
typedef unsigned long DWORD;
typedef unsigned long ULONG;
typedef unsigned long long u64;
typedef unsigned long long usize;
typedef long long i64;
typedef int BOOL;
typedef unsigned int UINT;
typedef unsigned long long DWORD_PTR;
typedef void* HANDLE;
typedef void* HMODULE;
typedef void* LPVOID;
typedef char* LPSTR;
typedef const char* LPCSTR;
typedef struct { i64 QuadPart; } LARGE_INTEGER;
typedef struct __declspec(align(8)) { i64 opaque[5]; } CRITICAL_SECTION_OPAQUE;

#define WINAPI __stdcall
#define CDECL __cdecl
#define DLL_EXPORT __declspec(dllexport)
#define DLL_IMPORT __declspec(dllimport)
#define TRUE 1
#define FALSE 0
#define INVALID_HANDLE_VALUE ((HANDLE)(i64)-1)
#define FILE_ATTRIBUTE_DIRECTORY 0x10UL
#define INVALID_FILE_ATTRIBUTES 0xFFFFFFFFUL
#define HANDLE_FLAG_INHERIT 0x1UL
#define STARTF_USESTDHANDLES 0x00000100UL
#define CREATE_NO_WINDOW 0x08000000UL
#define STD_INPUT_HANDLE ((DWORD)-10)
#define STD_ERROR_HANDLE ((DWORD)-12)
#define WAIT_OBJECT_0 0x00000000UL
#define WAIT_TIMEOUT 0x00000102UL
#define STILL_ACTIVE 259UL
#define HEAP_ZERO_MEMORY 0x00000008UL
#define GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS 0x00000004UL
#define GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT 0x00000002UL

#define WAVE_FORMAT_PCM 1
#define WAVE_MAPPER ((UINT)-1)
#define CALLBACK_NULL 0
#define MMSYSERR_NOERROR 0
#define WHDR_DONE 0x00000001UL
#define WHDR_PREPARED 0x00000002UL
#define TIME_SAMPLES 2
#define AUDIO_SLOT_COUNT 12
#define AUDIO_RATE 48000u
#define AUDIO_CHANNELS 2u
#define AUDIO_BITS 16u

typedef DWORD (WINAPI *ThreadProc)(LPVOID);

DLL_IMPORT BOOL WINAPI GetModuleHandleExA(DWORD,LPCSTR,HMODULE*);
DLL_IMPORT DWORD WINAPI GetModuleFileNameA(HMODULE,char*,DWORD);
DLL_IMPORT DWORD WINAPI GetEnvironmentVariableA(LPCSTR,char*,DWORD);
DLL_IMPORT DWORD WINAPI GetFileAttributesA(LPCSTR);
DLL_IMPORT BOOL WINAPI CreatePipe(HANDLE*,HANDLE*,LPVOID,DWORD);
DLL_IMPORT BOOL WINAPI SetHandleInformation(HANDLE,DWORD,DWORD);
DLL_IMPORT BOOL WINAPI CreateProcessA(LPCSTR,LPSTR,LPVOID,LPVOID,BOOL,DWORD,LPVOID,LPCSTR,LPVOID,LPVOID);
DLL_IMPORT HANDLE WINAPI CreateThread(LPVOID,usize,ThreadProc,LPVOID,DWORD,DWORD*);
DLL_IMPORT HANDLE WINAPI GetStdHandle(DWORD);
DLL_IMPORT BOOL WINAPI ReadFile(HANDLE,LPVOID,DWORD,DWORD*,LPVOID);
DLL_IMPORT BOOL WINAPI CloseHandle(HANDLE);
DLL_IMPORT BOOL WINAPI TerminateProcess(HANDLE,UINT);
DLL_IMPORT DWORD WINAPI WaitForSingleObject(HANDLE,DWORD);
DLL_IMPORT BOOL WINAPI GetExitCodeProcess(HANDLE,DWORD*);
DLL_IMPORT void WINAPI Sleep(DWORD);
DLL_IMPORT BOOL WINAPI QueryPerformanceCounter(LARGE_INTEGER*);
DLL_IMPORT BOOL WINAPI QueryPerformanceFrequency(LARGE_INTEGER*);
DLL_IMPORT HANDLE WINAPI GetProcessHeap(void);
DLL_IMPORT LPVOID WINAPI HeapAlloc(HANDLE,DWORD,usize);
DLL_IMPORT BOOL WINAPI HeapFree(HANDLE,DWORD,LPVOID);
DLL_IMPORT void WINAPI InitializeCriticalSection(CRITICAL_SECTION_OPAQUE*);
DLL_IMPORT void WINAPI EnterCriticalSection(CRITICAL_SECTION_OPAQUE*);
DLL_IMPORT void WINAPI LeaveCriticalSection(CRITICAL_SECTION_OPAQUE*);
DLL_IMPORT void WINAPI DeleteCriticalSection(CRITICAL_SECTION_OPAQUE*);
DLL_IMPORT long WINAPI InterlockedExchange(volatile long*,long);
DLL_IMPORT DWORD WINAPI GetLastError(void);

// winmm.dll

typedef void* HWAVEOUT;
typedef struct {
    u16 wFormatTag;
    u16 nChannels;
    u32 nSamplesPerSec;
    u32 nAvgBytesPerSec;
    u16 nBlockAlign;
    u16 wBitsPerSample;
    u16 cbSize;
} WAVEFORMATEX;

typedef struct wavehdr_tag {
    LPSTR lpData;
    u32 dwBufferLength;
    u32 dwBytesRecorded;
    DWORD_PTR dwUser;
    u32 dwFlags;
    u32 dwLoops;
    struct wavehdr_tag* lpNext;
    DWORD_PTR reserved;
} WAVEHDR;

typedef struct {
    u32 wType;
    union { u32 ms; u32 sample; u32 cb; u32 ticks; u8 smpte[8]; u32 midi; } u;
} MMTIME;

DLL_IMPORT UINT WINAPI waveOutOpen(HWAVEOUT*,UINT,const WAVEFORMATEX*,DWORD_PTR,DWORD_PTR,DWORD);
DLL_IMPORT UINT WINAPI waveOutPrepareHeader(HWAVEOUT,WAVEHDR*,UINT);
DLL_IMPORT UINT WINAPI waveOutUnprepareHeader(HWAVEOUT,WAVEHDR*,UINT);
DLL_IMPORT UINT WINAPI waveOutWrite(HWAVEOUT,WAVEHDR*,UINT);
DLL_IMPORT UINT WINAPI waveOutPause(HWAVEOUT);
DLL_IMPORT UINT WINAPI waveOutRestart(HWAVEOUT);
DLL_IMPORT UINT WINAPI waveOutReset(HWAVEOUT);
DLL_IMPORT UINT WINAPI waveOutClose(HWAVEOUT);
DLL_IMPORT UINT WINAPI waveOutGetPosition(HWAVEOUT,MMTIME*,UINT);

typedef struct {
    DWORD nLength;
    LPVOID lpSecurityDescriptor;
    BOOL bInheritHandle;
} SECURITY_ATTRIBUTES;

typedef struct {
    DWORD cb;
    LPSTR lpReserved;
    LPSTR lpDesktop;
    LPSTR lpTitle;
    DWORD dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars;
    DWORD dwFillAttribute, dwFlags;
    u16 wShowWindow, cbReserved2;
    u8* lpReserved2;
    HANDLE hStdInput, hStdOutput, hStdError;
} STARTUPINFOA;

typedef struct {
    HANDLE hProcess;
    HANDLE hThread;
    DWORD dwProcessId;
    DWORD dwThreadId;
} PROCESS_INFORMATION;

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

typedef struct AudioSlot {
    WAVEHDR header;
    u8* bytes;
} AudioSlot;

typedef struct Movie {
    SeBinkInfo info;
    HANDLE video_process;
    HANDLE video_thread;
    HANDLE video_pipe;
    HANDLE audio_process;
    HANDLE audio_thread;
    HANDLE audio_pipe;
    HANDLE audio_worker_thread;
    HWAVEOUT wave;
    AudioSlot audio_slots[AUDIO_SLOT_COUNT];
    u32 audio_slot_cursor;
    u32 audio_capacity;
    u64 audio_sample_accum;
    u64 audio_samples_submitted;
    int audio_active;
    int presentation_started;
    int audio_eof;
    u32 next_frame;
    LARGE_INTEGER qpc_frequency;
    LARGE_INTEGER clock_start;
    volatile long skip_requested;
    CRITICAL_SECTION_OPAQUE gate;
} Movie;

static char g_last_error[1024];
static char g_ffmpeg_path[1024];

void* memcpy(void* dst,const void* src,usize n){u8*d=(u8*)dst;const u8*s=(const u8*)src;usize i;for(i=0;i<n;i++)d[i]=s[i];return dst;}
void* memset(void* dst,int v,usize n){u8*d=(u8*)dst;usize i;for(i=0;i<n;i++)d[i]=(u8)v;return dst;}
static void zero(void*p,usize n){memset(p,0,n);}
static usize slen(const char*s){usize n=0;if(!s)return 0;while(s[n])n++;return n;}
static void scopy(char*d,usize cap,const char*s){usize i=0;if(!d||!cap)return;if(!s){d[0]=0;return;}while(i+1<cap&&s[i]){d[i]=s[i];i++;}d[i]=0;}
static int sapp(char*d,usize cap,const char*s){usize a=slen(d),i=0;if(a>=cap)return 0;while(s&&s[i]&&a+i+1<cap){d[a+i]=s[i];i++;}if(s&&s[i])return 0;d[a+i]=0;return 1;}
static void seterr(const char*s){scopy(g_last_error,sizeof(g_last_error),s?s:"unknown-error");}
static void app_u32(char*d,usize cap,u32 v){char t[16];int n=0,i;if(!v){sapp(d,cap,"0");return;}while(v&&n<15){t[n++]=(char)('0'+v%10);v/=10;}for(i=n-1;i>=0;i--){char c[2]={t[i],0};sapp(d,cap,c);}}
static u32 rd32(const u8*p){return (u32)p[0]|((u32)p[1]<<8)|((u32)p[2]<<16)|((u32)p[3]<<24);}

DLL_EXPORT u32 CDECL se_bink_abi_version(void);

static int self_dir(char*out,usize cap){HMODULE self=0;DWORD n;usize i;if(!GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,(LPCSTR)(void*)&se_bink_abi_version,&self))return 0;n=GetModuleFileNameA(self,out,(DWORD)cap);if(!n||n>=cap)return 0;i=n;while(i){--i;if(out[i]=='\\'||out[i]=='/'){out[i]=0;return 1;}}return 0;}
static int exists_file(const char*p){DWORD a;if(!p||!*p)return 0;a=GetFileAttributesA(p);return a!=INVALID_FILE_ATTRIBUTES&&!(a&FILE_ATTRIBUTE_DIRECTORY);}
static int sibling(char*out,usize cap,const char*dir,const char*leaf){out[0]=0;scopy(out,cap,dir);return sapp(out,cap,"\\")&&sapp(out,cap,leaf);}

static int locate_ffmpeg(void){char e[1024],d[1024],p[1024];DWORD n;if(g_ffmpeg_path[0]&&exists_file(g_ffmpeg_path))return 1;e[0]=0;n=GetEnvironmentVariableA("SHARPEMU_BINK_FFMPEG_EXE",e,(DWORD)sizeof(e));if(n>0&&n<sizeof(e)&&exists_file(e)){scopy(g_ffmpeg_path,sizeof(g_ffmpeg_path),e);return 1;}if(self_dir(d,sizeof(d))){
    if(sibling(p,sizeof(p),d,"ffmpeg-runtime\\ffmpeg.exe")&&exists_file(p)){scopy(g_ffmpeg_path,sizeof(g_ffmpeg_path),p);return 1;}
    if(sibling(p,sizeof(p),d,"ffmpeg.exe")&&exists_file(p)){scopy(g_ffmpeg_path,sizeof(g_ffmpeg_path),p);return 1;}
    if(sibling(p,sizeof(p),d,"..\\ffmpeg\\ffmpeg.exe")&&exists_file(p)){scopy(g_ffmpeg_path,sizeof(g_ffmpeg_path),p);return 1;}
    if(sibling(p,sizeof(p),d,"..\\..\\ffmpeg.exe")&&exists_file(p)){scopy(g_ffmpeg_path,sizeof(g_ffmpeg_path),p);return 1;}
}
if(GetEnvironmentVariableA("SHARPEMU_BINK_ALLOW_PATH_FFMPEG",e,(DWORD)sizeof(e))>0 && e[0]=='1'){scopy(g_ffmpeg_path,sizeof(g_ffmpeg_path),"ffmpeg.exe");return 1;}return 0;}

static int append_quoted(char*d,usize cap,const char*s){usize i;if(!sapp(d,cap,"\""))return 0;for(i=0;s&&s[i];i++){char c[3];if(s[i]=='\"'){c[0]='\\';c[1]='\"';c[2]=0;}else{c[0]=s[i];c[1]=0;}if(!sapp(d,cap,c))return 0;}return sapp(d,cap,"\"");}

static int start_capture(const char*movie,int audio,u32 audio_tracks,HANDLE*proc,HANDLE*thread,HANDLE*readpipe){
    SECURITY_ATTRIBUTES sa;STARTUPINFOA si;PROCESS_INFORMATION pi;HANDLE r=0,w=0;char*cmd=(char*)HeapAlloc(GetProcessHeap(),HEAP_ZERO_MEMORY,4096);
    if(!cmd){seterr("command-buffer-oom");return 0;}
    zero(&sa,sizeof(sa));sa.nLength=sizeof(sa);sa.bInheritHandle=TRUE;
    if(!CreatePipe(&r,&w,&sa,0)){HeapFree(GetProcessHeap(),0,cmd);seterr("CreatePipe-failed");return 0;}
    SetHandleInformation(r,HANDLE_FLAG_INHERIT,0);
    zero(&si,sizeof(si));zero(&pi,sizeof(pi));si.cb=sizeof(si);si.dwFlags=STARTF_USESTDHANDLES;si.hStdInput=GetStdHandle(STD_INPUT_HANDLE);si.hStdOutput=w;si.hStdError=GetStdHandle(STD_ERROR_HANDLE);
    cmd[0]=0;append_quoted(cmd,4096,g_ffmpeg_path);sapp(cmd,4096," -hide_banner -loglevel error -nostdin -i ");append_quoted(cmd,4096,movie);
    if(audio){
        if(audio_tracks>1 && audio_tracks<=32){u32 i;sapp(cmd,4096," -filter_complex \"");for(i=0;i<audio_tracks;i++){sapp(cmd,4096,"[0:a:");app_u32(cmd,4096,i);sapp(cmd,4096,"]");}sapp(cmd,4096,"amix=inputs=");app_u32(cmd,4096,audio_tracks);sapp(cmd,4096,":normalize=0[a]\" -map \"[a]\"");}
        else{sapp(cmd,4096," -map 0:a:0");}
        sapp(cmd,4096," -vn -sn -dn -ac 2 -ar 48000 -c:a pcm_s16le -f s16le pipe:1");
    }
    else{sapp(cmd,4096," -map 0:v:0 -an -sn -dn -pix_fmt bgra -f rawvideo pipe:1");}
    if(!CreateProcessA(g_ffmpeg_path,cmd,NULL,NULL,TRUE,CREATE_NO_WINDOW,NULL,NULL,&si,&pi)){
        DWORD e=GetLastError();CloseHandle(r);CloseHandle(w);HeapFree(GetProcessHeap(),0,cmd);seterr(audio?"ffmpeg-audio-CreateProcess-failed-win32=":"ffmpeg-video-CreateProcess-failed-win32=");app_u32(g_last_error,sizeof(g_last_error),(u32)e);return 0;}
    HeapFree(GetProcessHeap(),0,cmd);CloseHandle(w);*proc=pi.hProcess;*thread=pi.hThread;*readpipe=r;return 1;
}

static int read_exact(HANDLE h,u8*dst,usize n,volatile long*skip){usize off=0;while(off<n){DWORD want=(DWORD)((n-off)>1048576u?1048576u:(n-off));DWORD got=0;if(skip&&*skip)return 0;if(!ReadFile(h,dst+off,want,&got,NULL)||got==0)return 0;off+=got;}return 1;}

static int read_header(const char*path,SeBinkInfo*info){HANDLE h;DWORD got=0;u8 b[44];
    // Use the normal filesystem path through CreateProcess later; for header read use ffmpeg itself? We only need KB2 fields.
    // Reuse CreateFileA through a tiny process-independent declaration below.
    typedef HANDLE (WINAPI *CreateFileAFn)(LPCSTR,DWORD,DWORD,LPVOID,DWORD,DWORD,HANDLE);
    typedef BOOL (WINAPI *ReadFileFn)(HANDLE,LPVOID,DWORD,DWORD*,LPVOID);
    (void)h;(void)got;(void)b;(void)info;(void)path;return 0;
}

// Header reader imports are declared here to keep the adapter CRT-free.
#define GENERIC_READ 0x80000000UL
#define FILE_SHARE_READ 0x00000001UL
#define OPEN_EXISTING 3UL
#define FILE_ATTRIBUTE_NORMAL 0x00000080UL
DLL_IMPORT HANDLE WINAPI CreateFileA(LPCSTR,DWORD,DWORD,LPVOID,DWORD,DWORD,HANDLE);

static int parse_header(const char*path,SeBinkInfo*info){HANDLE h;DWORD got=0;u8 b[44];if(!path||!info){seterr("invalid-open-arguments");return 0;}h=CreateFileA(path,GENERIC_READ,FILE_SHARE_READ,NULL,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,NULL);if(h==INVALID_HANDLE_VALUE){seterr("movie-open-failed");return 0;}zero(b,sizeof(b));if(!ReadFile(h,b,(DWORD)sizeof(b),&got,NULL)||got<sizeof(b)){CloseHandle(h);seterr("short-kb2-header");return 0;}CloseHandle(h);if(b[0]!='K'||b[1]!='B'||b[2]!='2'){seterr("not-kb2");return 0;}zero(info,sizeof(*info));info->frame_count=rd32(b+8);info->width=rd32(b+0x14);info->height=rd32(b+0x18);info->fps_num=rd32(b+0x1c);info->fps_den=rd32(b+0x20);info->audio_track_count=rd32(b+40);if(!info->frame_count||!info->width||!info->height||!info->fps_num||!info->fps_den||info->width>16384||info->height>16384||info->audio_track_count>256){seterr("invalid-kb2-header");return 0;}return 1;}

static void kill_proc(HANDLE p){DWORD code=0;if(!p)return;if(GetExitCodeProcess(p,&code)&&code==STILL_ACTIVE){TerminateProcess(p,0);WaitForSingleObject(p,1000);}}

static int init_wave(Movie*m){WAVEFORMATEX f;UINT r;u32 i;zero(&f,sizeof(f));f.wFormatTag=WAVE_FORMAT_PCM;f.nChannels=AUDIO_CHANNELS;f.nSamplesPerSec=AUDIO_RATE;f.wBitsPerSample=AUDIO_BITS;f.nBlockAlign=(u16)(AUDIO_CHANNELS*(AUDIO_BITS/8));f.nAvgBytesPerSec=f.nSamplesPerSec*f.nBlockAlign;f.cbSize=0;r=waveOutOpen(&m->wave,WAVE_MAPPER,&f,0,0,CALLBACK_NULL);if(r!=MMSYSERR_NOERROR){seterr("waveOutOpen-failed");return 0;}
    // ~42.7 ms per slot at 48 kHz stereo s16; twelve slots keep ~512 ms
    // queued independently of the guest's video-present frequency.
    m->audio_capacity=8192u;
    for(i=0;i<AUDIO_SLOT_COUNT;i++){m->audio_slots[i].bytes=(u8*)HeapAlloc(GetProcessHeap(),HEAP_ZERO_MEMORY,m->audio_capacity);if(!m->audio_slots[i].bytes){seterr("audio-buffer-oom");return 0;}zero(&m->audio_slots[i].header,sizeof(WAVEHDR));m->audio_slots[i].header.lpData=(LPSTR)m->audio_slots[i].bytes;m->audio_slots[i].header.dwBufferLength=m->audio_capacity;if(waveOutPrepareHeader(m->wave,&m->audio_slots[i].header,sizeof(WAVEHDR))!=MMSYSERR_NOERROR){seterr("waveOutPrepareHeader-failed");return 0;}}
    waveOutPause(m->wave);return 1;
}

static DWORD WINAPI audio_worker(LPVOID param){Movie*m=(Movie*)param;while(!m->skip_requested){AudioSlot*s=&m->audio_slots[m->audio_slot_cursor++%AUDIO_SLOT_COUNT];DWORD got=0;UINT wr;while(!(s->header.dwFlags&WHDR_DONE)&&m->audio_samples_submitted>=AUDIO_SLOT_COUNT){if(m->skip_requested)return 0;Sleep(1);}if(m->skip_requested)return 0;if(!ReadFile(m->audio_pipe,s->bytes,m->audio_capacity,&got,NULL)||got==0){m->audio_eof=1;return 0;}got-=got%(AUDIO_CHANNELS*(AUDIO_BITS/8));if(got==0)continue;s->header.dwBufferLength=got;wr=waveOutWrite(m->wave,&s->header,sizeof(WAVEHDR));if(wr!=MMSYSERR_NOERROR){seterr("waveOutWrite-failed");m->audio_eof=1;return 0;}m->audio_samples_submitted++;}return 0;}

static void cleanup_wave(Movie*m){u32 i;if(!m->wave)return;waveOutReset(m->wave);for(i=0;i<AUDIO_SLOT_COUNT;i++){if(m->audio_slots[i].bytes){waveOutUnprepareHeader(m->wave,&m->audio_slots[i].header,sizeof(WAVEHDR));HeapFree(GetProcessHeap(),0,m->audio_slots[i].bytes);m->audio_slots[i].bytes=0;}}waveOutClose(m->wave);m->wave=0;}

DLL_EXPORT u32 CDECL se_bink_abi_version(void){return 0x00010000u;}
DLL_EXPORT u32 CDECL se_bink_build_capabilities(void){return 0x0000000Fu;}
DLL_EXPORT const char* CDECL se_bink_backend_name(void){return "ffmpeg-core-headless-av-v75.0.4";}

DLL_EXPORT Movie* CDECL se_bink_open_utf8(const char*path,u32 flags,SeBinkInfo*out_info){SeBinkInfo info;Movie*m;(void)flags;g_last_error[0]=0;if(!parse_header(path,&info))return NULL;if(!locate_ffmpeg()){seterr("ffmpeg-core-runtime-not-found");return NULL;}m=(Movie*)HeapAlloc(GetProcessHeap(),HEAP_ZERO_MEMORY,sizeof(Movie));if(!m){seterr("out-of-memory");return NULL;}m->info=info;QueryPerformanceFrequency(&m->qpc_frequency);InitializeCriticalSection(&m->gate);
    if(!start_capture(path,0,0,&m->video_process,&m->video_thread,&m->video_pipe)){DeleteCriticalSection(&m->gate);HeapFree(GetProcessHeap(),0,m);return NULL;}
    if(info.audio_track_count>0){if(!start_capture(path,1,info.audio_track_count,&m->audio_process,&m->audio_thread,&m->audio_pipe)||!init_wave(m)){kill_proc(m->video_process);kill_proc(m->audio_process);if(m->video_pipe)CloseHandle(m->video_pipe);if(m->audio_pipe)CloseHandle(m->audio_pipe);if(m->video_thread)CloseHandle(m->video_thread);if(m->audio_thread)CloseHandle(m->audio_thread);if(m->video_process)CloseHandle(m->video_process);if(m->audio_process)CloseHandle(m->audio_process);cleanup_wave(m);DeleteCriticalSection(&m->gate);HeapFree(GetProcessHeap(),0,m);return NULL;}m->audio_active=1;m->audio_worker_thread=CreateThread(NULL,0,audio_worker,m,0,NULL);if(!m->audio_worker_thread){seterr("audio-worker-create-failed");kill_proc(m->video_process);kill_proc(m->audio_process);if(m->video_pipe)CloseHandle(m->video_pipe);if(m->audio_pipe)CloseHandle(m->audio_pipe);if(m->video_thread)CloseHandle(m->video_thread);if(m->audio_thread)CloseHandle(m->audio_thread);if(m->video_process)CloseHandle(m->video_process);if(m->audio_process)CloseHandle(m->audio_process);cleanup_wave(m);DeleteCriticalSection(&m->gate);HeapFree(GetProcessHeap(),0,m);return NULL;}m->info.flags|=1u;}
    *out_info=m->info;return m;}

DLL_EXPORT int CDECL se_bink_decode_bgra(Movie*m,void*dst,usize dst_bytes,int pitch){usize row,frame_bytes;u8*tmp;u32 y;if(!m||!dst||!m->video_pipe){seterr("invalid-decode-arguments");return -1;}if(m->skip_requested||m->next_frame>=m->info.frame_count)return 0;frame_bytes=(usize)m->info.width*m->info.height*4u;if(dst_bytes<(usize)pitch*m->info.height||pitch<(int)(m->info.width*4u)){seterr("destination-too-small");return -2;}EnterCriticalSection(&m->gate);if(m->skip_requested){LeaveCriticalSection(&m->gate);return 0;}
    if(pitch==(int)(m->info.width*4u)){if(!read_exact(m->video_pipe,(u8*)dst,frame_bytes,&m->skip_requested)){seterr("ffmpeg-video-stream-ended");LeaveCriticalSection(&m->gate);return m->skip_requested?0:-3;}}
    else{tmp=(u8*)HeapAlloc(GetProcessHeap(),0,frame_bytes);if(!tmp){seterr("frame-temp-oom");LeaveCriticalSection(&m->gate);return -4;}if(!read_exact(m->video_pipe,tmp,frame_bytes,&m->skip_requested)){HeapFree(GetProcessHeap(),0,tmp);seterr("ffmpeg-video-stream-ended");LeaveCriticalSection(&m->gate);return -3;}row=(usize)m->info.width*4u;for(y=0;y<m->info.height;y++)memcpy((u8*)dst+(usize)y*pitch,tmp+(usize)y*row,row);HeapFree(GetProcessHeap(),0,tmp);}
    m->next_frame++;LeaveCriticalSection(&m->gate);return 1;}

DLL_EXPORT void CDECL se_bink_notify_presented(Movie*m){if(!m||m->presentation_started)return;EnterCriticalSection(&m->gate);if(!m->presentation_started){QueryPerformanceCounter(&m->clock_start);m->presentation_started=1;if(m->audio_active&&m->wave)waveOutRestart(m->wave);}LeaveCriticalSection(&m->gate);}

DLL_EXPORT int CDECL se_bink_get_clock_us(Movie*m,i64*us){LARGE_INTEGER now;MMTIME mt;if(!m||!us||!m->presentation_started)return 0;if(m->audio_active&&m->wave){zero(&mt,sizeof(mt));mt.wType=TIME_SAMPLES;if(waveOutGetPosition(m->wave,&mt,sizeof(mt))==MMSYSERR_NOERROR&&mt.wType==TIME_SAMPLES){*us=((i64)mt.u.sample*1000000LL)/AUDIO_RATE;return 1;}}if(m->qpc_frequency.QuadPart<=0)return 0;QueryPerformanceCounter(&now);*us=((now.QuadPart-m->clock_start.QuadPart)*1000000LL)/m->qpc_frequency.QuadPart;return 1;}

DLL_EXPORT void CDECL se_bink_request_skip(Movie*m){if(!m)return;InterlockedExchange(&m->skip_requested,1);if(m->wave)waveOutReset(m->wave);kill_proc(m->video_process);kill_proc(m->audio_process);if(m->audio_worker_thread)WaitForSingleObject(m->audio_worker_thread,1000);}

DLL_EXPORT void CDECL se_bink_close(Movie*m){if(!m)return;InterlockedExchange(&m->skip_requested,1);if(m->wave)waveOutReset(m->wave);kill_proc(m->video_process);kill_proc(m->audio_process);if(m->audio_worker_thread){WaitForSingleObject(m->audio_worker_thread,2000);CloseHandle(m->audio_worker_thread);m->audio_worker_thread=0;}if(m->video_pipe){CloseHandle(m->video_pipe);m->video_pipe=0;}if(m->audio_pipe){CloseHandle(m->audio_pipe);m->audio_pipe=0;}EnterCriticalSection(&m->gate);cleanup_wave(m);if(m->video_thread)CloseHandle(m->video_thread);if(m->audio_thread)CloseHandle(m->audio_thread);if(m->video_process)CloseHandle(m->video_process);if(m->audio_process)CloseHandle(m->audio_process);LeaveCriticalSection(&m->gate);DeleteCriticalSection(&m->gate);HeapFree(GetProcessHeap(),0,m);}

DLL_EXPORT const char* CDECL se_bink_last_error_utf8(void){return g_last_error[0]?g_last_error:"";}
