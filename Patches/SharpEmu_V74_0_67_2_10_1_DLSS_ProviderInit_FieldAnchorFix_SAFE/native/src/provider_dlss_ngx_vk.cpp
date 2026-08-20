#include "sharpemu_vulkan_upscaler.h"

#include <windows.h>
#include <vulkan/vulkan.h>
#include <nvsdk_ngx.h>
#include <nvsdk_ngx_vk.h>
#include <nvsdk_ngx_helpers.h>
#include <nvsdk_ngx_helpers_vk.h>

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <mutex>
#include <string>
#include <vector>

static_assert(
    static_cast<int>(NVSDK_NGX_ENGINE_TYPE_CUSTOM) == 0,
    "Unexpected NVIDIA NGX custom-engine enum value");

namespace {
VkInstance g_instance = VK_NULL_HANDLE;
VkPhysicalDevice g_physical = VK_NULL_HANDLE;
VkDevice g_device = VK_NULL_HANDLE;
NVSDK_NGX_Parameter* g_params = nullptr;
NVSDK_NGX_Handle* g_feature = nullptr;
uint32_t g_in_w = 0, g_in_h = 0, g_out_w = 0, g_out_h = 0;
int32_t g_quality = -1;
bool g_initialized = false;
HMODULE g_vulkan_loader = nullptr;
PFN_vkGetInstanceProcAddr g_gipa = nullptr;
PFN_vkGetDeviceProcAddr g_gdpa = nullptr;
std::mutex g_mutex;
std::string g_last_error;

// Stable SharpEmu CUSTOM-engine project identifier.
// SHARPEMU_NGX_PROJECT_ID may override it for downstream/private builds.
constexpr const char* kSharpEmuProjectId =
    "7b43c0e8-9f21-4e57-b6d4-0c1ea2f04a67";
constexpr const char* kSharpEmuEngineVersion = "SharpEmu-V74.0.67.2.8";

static bool env_true(const char* name) {
    const char* v = std::getenv(name);
    if (!v) return false;
    return _stricmp(v, "1") == 0 || _stricmp(v, "true") == 0 ||
           _stricmp(v, "yes") == 0 || _stricmp(v, "on") == 0;
}

static const char* selected_project_id() {
    const char* configured = std::getenv("SHARPEMU_NGX_PROJECT_ID");
    return configured && std::strlen(configured) >= 36
        ? configured
        : kSharpEmuProjectId;
}

static std::filesystem::path ngx_data_path() {
    if (const char* configured = std::getenv("SHARPEMU_DLSS_DATA_PATH")) {
        return std::filesystem::path(configured);
    }

    std::error_code ec;
    auto path =
        std::filesystem::temp_directory_path(ec) /
        L"SharpEmu-NGX";
    std::filesystem::create_directories(path, ec);
    return path;
}

static void set_error(std::string value) {
    g_last_error = std::move(value);
}

static void ngx_log(const char* stage, NVSDK_NGX_Result result) {
    std::fprintf(
        stderr,
        "[V74.0.67.2.8][DLSS][NGX] stage=%s result=0x%llX success=%d\n",
        stage,
        static_cast<unsigned long long>(result),
        NVSDK_NGX_SUCCEED(result) ? 1 : 0);
    std::fflush(stderr);
}

static bool ensure_vulkan_loader() {
    if (g_vulkan_loader && g_gipa && g_gdpa) return true;

    g_vulkan_loader = LoadLibraryW(L"vulkan-1.dll");
    if (!g_vulkan_loader) {
        const auto code = static_cast<unsigned long>(GetLastError());
        set_error("LoadLibraryW(vulkan-1.dll) failed: " + std::to_string(code));
        std::fprintf(
            stderr,
            "[V74.0.67.2.8][DLSS][NGX] stage=load_vulkan_loader result=%lu success=0\n",
            code);
        std::fflush(stderr);
        return false;
    }

    g_gipa = reinterpret_cast<PFN_vkGetInstanceProcAddr>(
        GetProcAddress(g_vulkan_loader, "vkGetInstanceProcAddr"));
    g_gdpa = reinterpret_cast<PFN_vkGetDeviceProcAddr>(
        GetProcAddress(g_vulkan_loader, "vkGetDeviceProcAddr"));

    if (!g_gipa || !g_gdpa) {
        set_error("Vulkan loader does not expose vkGetInstanceProcAddr/vkGetDeviceProcAddr");
        std::fprintf(
            stderr,
            "[V74.0.67.2.8][DLSS][NGX] stage=resolve_vulkan_procaddr success=0 gipa=%d gdpa=%d\n",
            g_gipa ? 1 : 0,
            g_gdpa ? 1 : 0);
        std::fflush(stderr);
        FreeLibrary(g_vulkan_loader);
        g_vulkan_loader = nullptr;
        g_gipa = nullptr;
        g_gdpa = nullptr;
        return false;
    }

    std::fprintf(
        stderr,
        "[V74.0.67.2.8][DLSS][NGX] stage=load_vulkan_loader success=1\n");
    std::fflush(stderr);
    return true;
}

static NVSDK_NGX_FeatureDiscoveryInfo discovery_info() {
    static std::wstring dataPath = ngx_data_path().wstring();

    NVSDK_NGX_FeatureDiscoveryInfo info{};
    info.SDKVersion = NVSDK_NGX_Version_API;
    info.FeatureID = NVSDK_NGX_Feature_SuperSampling;
    info.Identifier.IdentifierType =
        NVSDK_NGX_Application_Identifier_Type_Project_Id;
    info.Identifier.v.ProjectDesc.ProjectId = selected_project_id();
    info.Identifier.v.ProjectDesc.EngineType =
        NVSDK_NGX_ENGINE_TYPE_CUSTOM;
    info.Identifier.v.ProjectDesc.EngineVersion =
        kSharpEmuEngineVersion;
    info.ApplicationDataPath = dataPath.c_str();
    info.FeatureInfo = nullptr;
    return info;
}

static int write_extension_properties(
    VkExtensionProperties* properties,
    uint32_t count,
    char* buffer,
    int capacity) {

    std::string joined;
    for (uint32_t i = 0; i < count; ++i) {
        const char* name = properties[i].extensionName;
        if (!name || !*name) continue;
        if (!joined.empty()) joined.push_back(';');
        joined += name;
    }

    if (!buffer || capacity <= 0)
        return static_cast<int>(joined.size());

    if (joined.size() >= static_cast<size_t>(capacity)) {
        set_error("native extension buffer too small");
        return -2;
    }

    if (!joined.empty())
        std::memcpy(buffer, joined.data(), joined.size());
    return static_cast<int>(joined.size());
}

static int write_instance_extensions(char* buffer, int capacity) {
    auto info = discovery_info();
    uint32_t count = 0;
    VkExtensionProperties* properties = nullptr;

    const NVSDK_NGX_Result result =
        NVSDK_NGX_VULKAN_GetFeatureInstanceExtensionRequirements(
            &info,
            &count,
            &properties);
    ngx_log("instance_extension_requirements", result);

    if (NVSDK_NGX_FAILED(result)) {
        set_error(
            "NVSDK_NGX_VULKAN_GetFeatureInstanceExtensionRequirements failed: " +
            std::to_string(static_cast<long long>(result)));
        return -3;
    }

    std::fprintf(
        stderr,
        "[V74.0.67.2.8][DLSS][NGX] stage=instance_extension_requirements count=%u\n",
        count);
    std::fflush(stderr);

    if (count == 0 || !properties) return 0;
    return write_extension_properties(properties, count, buffer, capacity);
}

static int write_device_extensions(
    uint64_t instanceHandle,
    uint64_t physicalHandle,
    char* buffer,
    int capacity) {

    const auto instance = reinterpret_cast<VkInstance>(
        static_cast<uintptr_t>(instanceHandle));
    const auto physical = reinterpret_cast<VkPhysicalDevice>(
        static_cast<uintptr_t>(physicalHandle));

    if (!instance || !physical) {
        set_error("device-extension query received null VkInstance/VkPhysicalDevice");
        return -4;
    }

    auto info = discovery_info();

    NVSDK_NGX_FeatureRequirement requirement{};
    const NVSDK_NGX_Result requirementResult =
        NVSDK_NGX_VULKAN_GetFeatureRequirements(
            instance,
            physical,
            &info,
            &requirement);
    ngx_log("feature_requirements", requirementResult);

    if (NVSDK_NGX_FAILED(requirementResult)) {
        set_error(
            "NVSDK_NGX_VULKAN_GetFeatureRequirements failed: " +
            std::to_string(static_cast<long long>(requirementResult)));
        return -5;
    }

    std::fprintf(
        stderr,
        "[V74.0.67.2.8][DLSS][NGX] stage=feature_requirements support_mask=0x%X min_hw=0x%X min_os=%s\n",
        static_cast<unsigned int>(requirement.FeatureSupported),
        requirement.MinHWArchitecture,
        requirement.MinOSVersion);
    std::fflush(stderr);

    // Per NGX, FeatureSupported == 0 means supported.
    if (requirement.FeatureSupported != 0) {
        set_error(
            "DLSS Super Resolution feature requirements are not satisfied; support mask=" +
            std::to_string(
                static_cast<unsigned int>(requirement.FeatureSupported)));
        return -6;
    }

    uint32_t count = 0;
    VkExtensionProperties* properties = nullptr;
    const NVSDK_NGX_Result result =
        NVSDK_NGX_VULKAN_GetFeatureDeviceExtensionRequirements(
            instance,
            physical,
            &info,
            &count,
            &properties);
    ngx_log("device_extension_requirements", result);

    if (NVSDK_NGX_FAILED(result)) {
        set_error(
            "NVSDK_NGX_VULKAN_GetFeatureDeviceExtensionRequirements failed: " +
            std::to_string(static_cast<long long>(result)));
        return -7;
    }

    std::fprintf(
        stderr,
        "[V74.0.67.2.8][DLSS][NGX] stage=device_extension_requirements count=%u\n",
        count);
    std::fflush(stderr);

    if (count == 0 || !properties) return 0;
    return write_extension_properties(properties, count, buffer, capacity);
}

static NVSDK_NGX_PerfQuality_Value map_quality(int32_t q) {
    switch (q) {
        case 0: return NVSDK_NGX_PerfQuality_Value_DLAA;
        case 2: return NVSDK_NGX_PerfQuality_Value_Balanced;
        case 3: return NVSDK_NGX_PerfQuality_Value_MaxPerf;
        case 4: return NVSDK_NGX_PerfQuality_Value_UltraPerformance;
        case 1:
        default: return NVSDK_NGX_PerfQuality_Value_MaxQuality;
    }
}

static void release_feature() {
    if (g_feature) {
        const auto result =
            NVSDK_NGX_VULKAN_ReleaseFeature(g_feature);
        ngx_log("release_feature", result);
        g_feature = nullptr;
    }

    g_in_w = g_in_h = g_out_w = g_out_h = 0;
    g_quality = -1;
}

static int ensure_feature(
    const SharpEmuVkUpscalerDispatchDesc* d) {

    if (g_feature &&
        g_in_w == d->colorWidth && g_in_h == d->colorHeight &&
        g_out_w == d->outputWidth && g_out_h == d->outputHeight &&
        g_quality == d->quality) {
        return 0;
    }

    release_feature();

    // Temporal SR must enlarge. DLAA is the only equal-resolution mode.
    if (d->quality == 0) {
        if (d->colorWidth != d->outputWidth ||
            d->colorHeight != d->outputHeight) {
            set_error("DLAA requires equal input/output dimensions");
            std::fprintf(
                stderr,
                "[V74.0.67.2.8][DLSS][NGX] stage=create_feature reject=dlaa_requires_native input=%ux%u output=%ux%u\n",
                d->colorWidth,
                d->colorHeight,
                d->outputWidth,
                d->outputHeight);
            std::fflush(stderr);
            return -21;
        }
    }
    else if (d->colorWidth >= d->outputWidth ||
             d->colorHeight >= d->outputHeight) {
        set_error("DLSS SR received a non-upscale direction");
        std::fprintf(
            stderr,
            "[V74.0.67.2.8][DLSS][NGX] stage=create_feature reject=invalid_upscale_direction input=%ux%u output=%ux%u\n",
            d->colorWidth,
            d->colorHeight,
            d->outputWidth,
            d->outputHeight);
        std::fflush(stderr);
        return -22;
    }

    NVSDK_NGX_DLSS_Create_Params create{};
    create.Feature.InWidth = d->colorWidth;
    create.Feature.InHeight = d->colorHeight;
    create.Feature.InTargetWidth = d->outputWidth;
    create.Feature.InTargetHeight = d->outputHeight;
    create.Feature.InPerfQualityValue = map_quality(d->quality);
    create.InFeatureCreateFlags =
        NVSDK_NGX_DLSS_Feature_Flags_MVLowRes |
        NVSDK_NGX_DLSS_Feature_Flags_AutoExposure;

    if (env_true("SHARPEMU_VK_UPSCALER_HDR"))
        create.InFeatureCreateFlags |=
            NVSDK_NGX_DLSS_Feature_Flags_IsHDR;
    if (env_true("SHARPEMU_VK_UPSCALER_DEPTH_INVERTED"))
        create.InFeatureCreateFlags |=
            NVSDK_NGX_DLSS_Feature_Flags_DepthInverted;
    if (env_true("SHARPEMU_VK_UPSCALER_MV_JITTERED"))
        create.InFeatureCreateFlags |=
            NVSDK_NGX_DLSS_Feature_Flags_MVJittered;

    create.InEnableOutputSubrects = false;

    const auto cmd = reinterpret_cast<VkCommandBuffer>(
        static_cast<uintptr_t>(d->commandBuffer));

    const NVSDK_NGX_Result result =
        NGX_VULKAN_CREATE_DLSS_EXT1(
            g_device,
            cmd,
            0,
            0,
            &g_feature,
            g_params,
            &create);
    ngx_log("create_dlss_feature", result);

    if (NVSDK_NGX_FAILED(result) || !g_feature) {
        set_error(
            "NGX_VULKAN_CREATE_DLSS_EXT1 failed: " +
            std::to_string(static_cast<long long>(result)));
        g_feature = nullptr;
        return -20;
    }

    g_in_w = d->colorWidth;
    g_in_h = d->colorHeight;
    g_out_w = d->outputWidth;
    g_out_h = d->outputHeight;
    g_quality = d->quality;

    std::fprintf(
        stderr,
        "[V74.0.67.2.8][DLSS][NGX] stage=create_dlss_feature success=1 input=%ux%u output=%ux%u quality=%d\n",
        g_in_w,
        g_in_h,
        g_out_w,
        g_out_h,
        g_quality);
    std::fflush(stderr);
    return 0;
}
}

extern "C" SHARPEMU_UPSCALER_EXPORT int
sharpemu_vk_upscaler_get_instance_extensions(
    uint64_t,
    uint64_t,
    char* buffer,
    int capacity) {

    std::lock_guard<std::mutex> lock(g_mutex);
    g_last_error.clear();
    return write_instance_extensions(buffer, capacity);
}

extern "C" SHARPEMU_UPSCALER_EXPORT int
sharpemu_vk_upscaler_get_device_extensions(
    uint64_t instance,
    uint64_t physicalDevice,
    char* buffer,
    int capacity) {

    std::lock_guard<std::mutex> lock(g_mutex);
    g_last_error.clear();
    return write_device_extensions(
        instance,
        physicalDevice,
        buffer,
        capacity);
}

extern "C" SHARPEMU_UPSCALER_EXPORT uint32_t
sharpemu_vk_upscaler_get_capabilities(void) {
    return SHARPEMU_UPSCALER_CAP_DLSS |
           SHARPEMU_UPSCALER_CAP_TEMPORAL;
}

extern "C" SHARPEMU_UPSCALER_EXPORT int
sharpemu_vk_upscaler_initialize(
    const SharpEmuVkUpscalerInitDesc* d) {

    std::lock_guard<std::mutex> lock(g_mutex);
    g_last_error.clear();

    if (!d || d->abiVersion != 1 || d->size < sizeof(*d)) {
        set_error("invalid SharpEmu upscaler init descriptor");
        return -1;
    }

    if (d->vendorId != 0x10DEu) {
        set_error("DLSS provider requires NVIDIA vendor 0x10DE");
        return -2;
    }

    if (!ensure_vulkan_loader()) {
        return -6;
    }

    g_instance = reinterpret_cast<VkInstance>(
        static_cast<uintptr_t>(d->instance));
    g_physical = reinterpret_cast<VkPhysicalDevice>(
        static_cast<uintptr_t>(d->physicalDevice));
    g_device = reinterpret_cast<VkDevice>(
        static_cast<uintptr_t>(d->device));

    if (!g_instance || !g_physical || !g_device) {
        set_error("null Vulkan instance/physical-device/device passed to NGX");
        return -3;
    }

    const char* project = selected_project_id();
    const char* configuredProject =
        std::getenv("SHARPEMU_NGX_PROJECT_ID");

    std::fprintf(
        stderr,
        "[V74.0.67.2.8][DLSS][NGX] stage=project_id source=%s id=%s\n",
        configuredProject && std::strlen(configuredProject) >= 36
            ? "environment"
            : "sharpemu-default",
        project);
    std::fflush(stderr);

    const auto dataPath = ngx_data_path().wstring();
    const NVSDK_NGX_Result init =
        NVSDK_NGX_VULKAN_Init_with_ProjectID(
            project,
            NVSDK_NGX_ENGINE_TYPE_CUSTOM,
            kSharpEmuEngineVersion,
            dataPath.c_str(),
            g_instance,
            g_physical,
            g_device,
            g_gipa,
            g_gdpa,
            nullptr,
            NVSDK_NGX_Version_API);
    ngx_log("init_project_id", init);

    if (NVSDK_NGX_FAILED(init)) {
        set_error(
            "NVSDK_NGX_VULKAN_Init_with_ProjectID failed: " +
            std::to_string(static_cast<long long>(init)));
        g_instance = VK_NULL_HANDLE;
        g_physical = VK_NULL_HANDLE;
        g_device = VK_NULL_HANDLE;
        return -4;
    }

    const NVSDK_NGX_Result params =
        NVSDK_NGX_VULKAN_GetCapabilityParameters(&g_params);
    ngx_log("get_capability_parameters", params);

    if (NVSDK_NGX_FAILED(params) || !g_params) {
        set_error(
            "NVSDK_NGX_VULKAN_GetCapabilityParameters failed: " +
            std::to_string(static_cast<long long>(params)));
        NVSDK_NGX_VULKAN_Shutdown1(g_device);
        g_params = nullptr;
        g_instance = VK_NULL_HANDLE;
        g_physical = VK_NULL_HANDLE;
        g_device = VK_NULL_HANDLE;
        return -5;
    }

    g_initialized = true;

    std::fprintf(
        stderr,
        "[V74.0.67.2.8][DLSS][NGX] stage=initialize success=1 vendor=0x%X queue_family=%u output=%ux%u\n",
        d->vendorId,
        d->queueFamilyIndex,
        d->outputWidth,
        d->outputHeight);
    std::fflush(stderr);
    return 0;
}

extern "C" SHARPEMU_UPSCALER_EXPORT int
sharpemu_vk_upscaler_dispatch(
    const SharpEmuVkUpscalerDispatchDesc* d) {

    std::lock_guard<std::mutex> lock(g_mutex);
    g_last_error.clear();

    if (!g_initialized || !d ||
        d->abiVersion != 1 || d->size < sizeof(*d)) {
        set_error("DLSS dispatch before successful initialization or invalid descriptor");
        return -10;
    }

    if (d->backend != SHARPEMU_UPSCALER_DLSS) {
        set_error("DLSS provider received a non-DLSS backend request");
        return -11;
    }

    if (!d->commandBuffer ||
        !d->colorImage || !d->colorView ||
        !d->outputImage || !d->outputView ||
        !d->depthImage || !d->depthView ||
        !d->motionImage || !d->motionView) {
        set_error("DLSS dispatch requires command/color/output/depth/motion Vulkan handles");
        return -12;
    }

    const int feature = ensure_feature(d);
    if (feature != 0) return feature;

    const VkImageSubresourceRange colorRange{
        VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
    const VkImageSubresourceRange depthRange{
        VK_IMAGE_ASPECT_DEPTH_BIT, 0, 1, 0, 1};

    auto color = NVSDK_NGX_Create_ImageView_Resource_VK(
        reinterpret_cast<VkImageView>(
            static_cast<uintptr_t>(d->colorView)),
        reinterpret_cast<VkImage>(
            static_cast<uintptr_t>(d->colorImage)),
        colorRange,
        static_cast<VkFormat>(d->colorFormat),
        d->colorWidth,
        d->colorHeight,
        false);

    auto output = NVSDK_NGX_Create_ImageView_Resource_VK(
        reinterpret_cast<VkImageView>(
            static_cast<uintptr_t>(d->outputView)),
        reinterpret_cast<VkImage>(
            static_cast<uintptr_t>(d->outputImage)),
        colorRange,
        static_cast<VkFormat>(d->outputFormat),
        d->outputWidth,
        d->outputHeight,
        true);

    auto depth = NVSDK_NGX_Create_ImageView_Resource_VK(
        reinterpret_cast<VkImageView>(
            static_cast<uintptr_t>(d->depthView)),
        reinterpret_cast<VkImage>(
            static_cast<uintptr_t>(d->depthImage)),
        depthRange,
        static_cast<VkFormat>(d->depthFormat),
        d->depthWidth,
        d->depthHeight,
        false);

    auto motion = NVSDK_NGX_Create_ImageView_Resource_VK(
        reinterpret_cast<VkImageView>(
            static_cast<uintptr_t>(d->motionView)),
        reinterpret_cast<VkImage>(
            static_cast<uintptr_t>(d->motionImage)),
        colorRange,
        static_cast<VkFormat>(d->motionFormat),
        d->motionWidth,
        d->motionHeight,
        false);

    NVSDK_NGX_VK_DLSS_Eval_Params eval{};
    eval.Feature.pInColor = &color;
    eval.Feature.pInOutput = &output;
    eval.Feature.InSharpness =
        std::clamp(d->sharpness, 0.0f, 1.0f);
    eval.pInDepth = &depth;
    eval.pInMotionVectors = &motion;
    eval.InJitterOffsetX = d->jitterX;
    eval.InJitterOffsetY = d->jitterY;
    eval.InRenderSubrectDimensions = {
        d->colorWidth,
        d->colorHeight};
    eval.InReset = d->reset ? 1 : 0;
    eval.InMVScaleX =
        d->motionVectorScaleX == 0.0f
            ? 1.0f
            : d->motionVectorScaleX;
    eval.InMVScaleY =
        d->motionVectorScaleY == 0.0f
            ? 1.0f
            : d->motionVectorScaleY;
    eval.InPreExposure = 1.0f;
    eval.InExposureScale = 1.0f;
    eval.InFrameTimeDeltaInMsec =
        std::max(d->frameTimeMilliseconds, 0.01f);

    const auto cmd = reinterpret_cast<VkCommandBuffer>(
        static_cast<uintptr_t>(d->commandBuffer));

    const NVSDK_NGX_Result result =
        NGX_VULKAN_EVALUATE_DLSS_EXT(
            cmd,
            g_feature,
            g_params,
            &eval);
    ngx_log("evaluate_dlss", result);

    if (NVSDK_NGX_FAILED(result)) {
        set_error(
            "NGX_VULKAN_EVALUATE_DLSS_EXT failed: " +
            std::to_string(static_cast<long long>(result)));
        return -14;
    }

    std::fprintf(
        stderr,
        "[V74.0.67.2.8][DLSS][NGX] stage=evaluate_dlss success=1 frame=%llu input=%ux%u output=%ux%u\n",
        static_cast<unsigned long long>(d->frameId),
        d->colorWidth,
        d->colorHeight,
        d->outputWidth,
        d->outputHeight);
    std::fflush(stderr);
    return 0;
}

extern "C" SHARPEMU_UPSCALER_EXPORT void
sharpemu_vk_upscaler_shutdown(void) {
    std::lock_guard<std::mutex> lock(g_mutex);

    release_feature();

    if (g_params) {
        const auto result =
            NVSDK_NGX_VULKAN_DestroyParameters(g_params);
        ngx_log("destroy_parameters", result);
        g_params = nullptr;
    }

    if (g_initialized && g_device) {
        const auto result =
            NVSDK_NGX_VULKAN_Shutdown1(g_device);
        ngx_log("shutdown", result);
    }

    g_initialized = false;
    g_instance = VK_NULL_HANDLE;
    g_physical = VK_NULL_HANDLE;
    g_device = VK_NULL_HANDLE;

    if (g_vulkan_loader) {
        FreeLibrary(g_vulkan_loader);
        g_vulkan_loader = nullptr;
    }

    g_gipa = nullptr;
    g_gdpa = nullptr;
    g_last_error.clear();
}

extern "C" SHARPEMU_UPSCALER_EXPORT const char*
sharpemu_vk_upscaler_get_last_error(void) {
    std::lock_guard<std::mutex> lock(g_mutex);
    return g_last_error.c_str();
}
