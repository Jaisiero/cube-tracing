#pragma once

#define DAXA_RAY_TRACING 1
#include <daxa/daxa.inl>

#define MAX_INSTANCES 10000

struct Camera { 
    daxa_f32mat4x4 inv_view;
    daxa_f32mat4x4 inv_proj;
};
DAXA_DECL_BUFFER_PTR(Camera)

struct INSTANCE
{
    daxa_f32mat4x4 transform;
    daxa_f32vec3 color;
};

struct INSTANCES
{
    INSTANCE instances[MAX_INSTANCES];
};
DAXA_DECL_BUFFER_PTR(INSTANCES)

struct PushConstant
{
    daxa_u32vec2 size;
    daxa_TlasId tlas;
    daxa_ImageViewId swapchain;
    daxa_BufferPtr(Camera) camera_buffer;
    daxa_BufferPtr(INSTANCES) instance_buffer;
};