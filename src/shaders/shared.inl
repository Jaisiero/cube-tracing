#pragma once

#define DAXA_RAY_TRACING 1
#include <daxa/daxa.inl>

#define MAX_LEVELS 2

#define MAX_INSTANCES 10000
#define MAX_PRIMITIVES 100000

#define LEVEL_0_HALF_EXTENT 0.25
#define LEVEL_1_HALF_EXTENT 0.05

struct Camera { 
    daxa_f32mat4x4 inv_view;
    daxa_f32mat4x4 inv_proj;
    daxa_f32 LOD_distance;
};
DAXA_DECL_BUFFER_PTR(Camera)

struct INSTANCE
{
    daxa_f32mat4x4 transform;
    daxa_f32vec3 color;
    daxa_u32 first_primitive_index;
    daxa_u32 primitive_count;
    daxa_u32 level_index;
};

struct INSTANCES
{
    INSTANCE instances[MAX_INSTANCES];
};
DAXA_DECL_BUFFER_PTR(INSTANCES)

struct PRIMITIVE
{
    daxa_f32vec3 center;
};

struct PRIMITIVES
{
    PRIMITIVE primitives[MAX_PRIMITIVES];
};
DAXA_DECL_BUFFER_PTR(PRIMITIVES)

struct INSTANCE_LEVEL
{
    daxa_u32 level_index;
};

struct INSTANCE_LEVELS
{
    INSTANCE_LEVEL instance_levels[MAX_INSTANCES];
};
DAXA_DECL_BUFFER_PTR(INSTANCE_LEVELS)

struct PushConstant
{
    daxa_u32vec2 size;
    daxa_TlasId tlas;
    daxa_ImageViewId swapchain;
    daxa_BufferPtr(Camera) camera_buffer;
    daxa_BufferPtr(INSTANCES) instance_buffer;
    daxa_BufferPtr(PRIMITIVES) primitives_buffer;
    daxa_RWBufferPtr(INSTANCE_LEVELS) instance_level_buffer;
};