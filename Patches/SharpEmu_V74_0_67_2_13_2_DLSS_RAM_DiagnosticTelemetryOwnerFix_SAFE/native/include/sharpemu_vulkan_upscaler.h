#pragma once
#include <stdint.h>

#ifdef _WIN32
#define SHARPEMU_UPSCALER_EXPORT __declspec(dllexport)
#else
#define SHARPEMU_UPSCALER_EXPORT
#endif

#ifdef __cplusplus
extern "C" {
#endif

enum SharpEmuVkUpscalerBackend {
    SHARPEMU_UPSCALER_OFF = 0,
    SHARPEMU_UPSCALER_AUTO = 1,
    SHARPEMU_UPSCALER_DLSS = 2,
    SHARPEMU_UPSCALER_FSR = 3,
};

enum SharpEmuVkUpscalerCapability {
    SHARPEMU_UPSCALER_CAP_DLSS = 1u << 0,
    SHARPEMU_UPSCALER_CAP_FSR = 1u << 1,
    SHARPEMU_UPSCALER_CAP_COLOR_ONLY = 1u << 2,
    SHARPEMU_UPSCALER_CAP_TEMPORAL = 1u << 3,
};

typedef struct SharpEmuVkUpscalerInitDesc {
    uint32_t size;
    uint32_t abiVersion;
    uint64_t instance;
    uint64_t physicalDevice;
    uint64_t device;
    uint64_t queue;
    uint32_t queueFamilyIndex;
    uint32_t vendorId;
    uint32_t outputWidth;
    uint32_t outputHeight;
    uint32_t reserved0;
} SharpEmuVkUpscalerInitDesc;

typedef struct SharpEmuVkUpscalerDispatchDesc {
    uint32_t size;
    uint32_t abiVersion;
    int32_t backend;
    int32_t quality;
    uint64_t commandBuffer;
    uint64_t colorImage;
    uint64_t colorView;
    uint32_t colorFormat;
    uint32_t colorWidth;
    uint32_t colorHeight;
    int32_t colorLayout;
    uint64_t outputImage;
    uint64_t outputView;
    uint32_t outputFormat;
    uint32_t outputWidth;
    uint32_t outputHeight;
    int32_t outputLayout;
    uint64_t depthImage;
    uint64_t depthView;
    uint32_t depthFormat;
    uint32_t depthWidth;
    uint32_t depthHeight;
    int32_t depthLayout;
    uint64_t motionImage;
    uint64_t motionView;
    uint32_t motionFormat;
    uint32_t motionWidth;
    uint32_t motionHeight;
    int32_t motionLayout;
    float jitterX;
    float jitterY;
    float motionVectorScaleX;
    float motionVectorScaleY;
    float sharpness;
    float frameTimeMilliseconds;
    uint32_t reset;
    uint32_t flags;
    uint64_t frameId;
} SharpEmuVkUpscalerDispatchDesc;

// UTF-8 semicolon-separated extension list. The returned length excludes NUL.
// 0 means no required extension; negative values mean negotiation failure.
SHARPEMU_UPSCALER_EXPORT int sharpemu_vk_upscaler_get_instance_extensions(
    uint64_t instance, uint64_t physicalDevice, char* buffer, int capacity);
SHARPEMU_UPSCALER_EXPORT int sharpemu_vk_upscaler_get_device_extensions(
    uint64_t instance, uint64_t physicalDevice, char* buffer, int capacity);
SHARPEMU_UPSCALER_EXPORT uint32_t sharpemu_vk_upscaler_get_capabilities(void);
SHARPEMU_UPSCALER_EXPORT int sharpemu_vk_upscaler_initialize(
    const SharpEmuVkUpscalerInitDesc* desc);
SHARPEMU_UPSCALER_EXPORT int sharpemu_vk_upscaler_dispatch(
    const SharpEmuVkUpscalerDispatchDesc* desc);
SHARPEMU_UPSCALER_EXPORT void sharpemu_vk_upscaler_shutdown(void);

// Optional diagnostic export; ABI v1 callers that do not know it remain valid.
SHARPEMU_UPSCALER_EXPORT const char* sharpemu_vk_upscaler_get_last_error(void);

#ifdef __cplusplus
}
#endif
