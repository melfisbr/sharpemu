cmake_minimum_required(VERSION 3.23)

if(POLICY CMP0091)
    cmake_policy(SET CMP0091 NEW)
endif()

project(SharpEmuVulkanDlssProvider LANGUAGES CXX)

set(NGX_SDK_ROOT "" CACHE PATH "NVIDIA DLSS SDK root")
set(VULKAN_HEADERS_ROOT "" CACHE PATH "Khronos Vulkan-Headers root")
set(NGX_LIBRARY "" CACHE FILEPATH "NVIDIA NGX Vulkan static library")

if(NOT EXISTS "${NGX_SDK_ROOT}/include/nvsdk_ngx_vk.h")
    message(FATAL_ERROR "NGX_SDK_ROOT must contain include/nvsdk_ngx_vk.h")
endif()
if(NOT EXISTS "${VULKAN_HEADERS_ROOT}/include/vulkan/vulkan.h")
    message(FATAL_ERROR "VULKAN_HEADERS_ROOT must contain include/vulkan/vulkan.h")
endif()
if(NOT EXISTS "${NGX_LIBRARY}")
    message(FATAL_ERROR "NGX_LIBRARY not found: ${NGX_LIBRARY}")
endif()

add_library(
    SharpEmu.VulkanUpscaler.Native
    SHARED
    src/provider_dlss_ngx_vk.cpp)

target_compile_features(
    SharpEmu.VulkanUpscaler.Native
    PRIVATE cxx_std_20)

target_compile_definitions(
    SharpEmu.VulkanUpscaler.Native
    PRIVATE
    WIN32_LEAN_AND_MEAN
    NOMINMAX)

target_include_directories(
    SharpEmu.VulkanUpscaler.Native
    PRIVATE
    include
    "${NGX_SDK_ROOT}/include"
    "${VULKAN_HEADERS_ROOT}/include")

# NVIDIA's Windows x64 static NGX Vulkan library is built with the static
# MSVC runtime. Match it to avoid LNK2038 RuntimeLibrary mismatches.
if(MSVC)
    set_property(
        TARGET SharpEmu.VulkanUpscaler.Native
        PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded")
endif()

# Vulkan entry points are resolved dynamically from vulkan-1.dll.
target_link_libraries(
    SharpEmu.VulkanUpscaler.Native
    PRIVATE
    "${NGX_LIBRARY}")

set_target_properties(
    SharpEmu.VulkanUpscaler.Native
    PROPERTIES
    OUTPUT_NAME "SharpEmu.VulkanUpscaler.Native"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/upscalers"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/upscalers")
