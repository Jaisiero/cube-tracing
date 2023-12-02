#pragma once

#define DAXA_RAY_TRACING 1
#include <daxa/daxa.inl>

// #define MAX_LEVELS 2

#define MAX_INSTANCES 10000
#define MAX_PRIMITIVES 100000
#define MAX_MATERIALS 10000

// #define LEVEL_0_HALF_EXTENT 0.25
// #define LEVEL_1_HALF_EXTENT 0.125

#define HALF_EXTENT 0.125f
#define VOXEL_COUNT_BY_AXIS 8 // 2^3
#define CHUNK_VOXEL_COUNT VOXEL_COUNT_BY_AXIS * VOXEL_COUNT_BY_AXIS * VOXEL_COUNT_BY_AXIS

#define SAMPLES_PER_PIXEL 5
#define SAMPLE_OFFSET 0.001 // Multi sample offset
#define MAX_DEPTH 5
#define DELTA_RAY 0.00001   // Delta ray offset for shadow rays
// #define DELTA_RAY 0.001
// #define DELTA_RAY 0.0001
// #define DELTA_RAY 0.00001


struct Aabb
{
  daxa_f32vec3 minimum;
  daxa_f32vec3 maximum;
};

struct Ray
{
  daxa_f32vec3 origin;
  daxa_f32vec3 direction;
};


struct light_info
{
  daxa_f32vec3 position;
  daxa_f32 intensity;
  daxa_f32 distance;
  daxa_u32 type;  // 0: point light, 1: directional light
};

struct Camera { 
    daxa_f32mat4x4 inv_view;
    daxa_f32mat4x4 inv_proj;
    // daxa_f32 LOD_distance;
    daxa_u32 frame_number;
};
DAXA_DECL_BUFFER_PTR(Camera)

struct INSTANCE
{
    daxa_f32mat4x4 transform;
    daxa_u32 first_primitive_index;
    daxa_u32 primitive_count;
    // daxa_i32 level_index;
};

struct INSTANCES
{
    INSTANCE instances[MAX_INSTANCES];
};
DAXA_DECL_BUFFER_PTR(INSTANCES)

struct PRIMITIVE
{
    daxa_f32vec3 center;
    daxa_u32 material_index;
};

struct PRIMITIVES
{
    PRIMITIVE primitives[MAX_PRIMITIVES];
};
DAXA_DECL_BUFFER_PTR(PRIMITIVES)

#define TEXTURE_TYPE_LAMBERTIAN 0
#define TEXTURE_TYPE_METAL 1
#define TEXTURE_TYPE_DIELECTRIC 2

struct MATERIAL
{
    daxa_u32 type;      // 0: lambertian, 1: metal, 2: dielectric
    daxa_f32vec3  ambient;
    daxa_f32vec3  diffuse;
    daxa_f32vec3  specular;
    daxa_f32vec3  transmittance;
    daxa_f32vec3  emission;
    daxa_f32 shininess;
    daxa_f32 roughness;
    daxa_f32 ior;       // index of refraction
    daxa_f32 dissolve;  // 1 == opaque; 0 == fully transparent
    daxa_i32   illum;     // illumination model (see http://www.fileformat.info/format/material/)
    daxa_i32   textureId;
};

struct MATERIALS
{
    MATERIAL materials[MAX_MATERIALS];
};
DAXA_DECL_BUFFER_PTR(MATERIALS)

// struct INSTANCE_LEVEL
// {
//     daxa_i32 level_index;
// };

// struct INSTANCE_LEVELS
// {
//     INSTANCE_LEVEL instance_levels[MAX_INSTANCES];
// };
// DAXA_DECL_BUFFER_PTR(INSTANCE_LEVELS)

// NOTE: Debugging

#define WIDTH_RES 3840
#define HEIGHT_RES 2160

struct HIT_DISTANCE
{
    daxa_f32 distance;
    daxa_f32vec3 position;
    daxa_f32vec3 normal;
    daxa_u32 instance_index;
    daxa_u32 primitive_index;
};

struct HIT_DISTANCES
{
    HIT_DISTANCE hit_distances[WIDTH_RES*HEIGHT_RES];
};
DAXA_DECL_BUFFER_PTR(HIT_DISTANCES)

// struct INSTANCE_DISTANCE
// {
//     daxa_f32 distance;
// };

// struct INSTANCE_DISTANCES
// {
//     INSTANCE_DISTANCE instance_distances[MAX_INSTANCES];
// };
// DAXA_DECL_BUFFER_PTR(INSTANCE_DISTANCES)

// struct PRIMITIVE_AABB
// {
//     Aabb aabb;
// };

// struct PRIMITIVE_AABBS
// {
//     PRIMITIVE_AABB aabbs[MAX_PRIMITIVES];
// };
// DAXA_DECL_BUFFER_PTR(PRIMITIVE_AABBS)

struct PushConstant
{
    daxa_u32vec2 size;
    daxa_TlasId tlas;
    daxa_ImageViewId swapchain;
    daxa_BufferPtr(Camera) camera_buffer;
    daxa_BufferPtr(INSTANCES) instance_buffer;
    daxa_BufferPtr(PRIMITIVES) primitives_buffer;
    daxa_BufferPtr(MATERIALS) materials_buffer;
    daxa_RWBufferPtr(HIT_DISTANCES) hit_distance_buffer;
    // daxa_RWBufferPtr(INSTANCE_LEVELS) instance_level_buffer;
    // daxa_RWBufferPtr(INSTANCE_DISTANCES) instance_distance_buffer;
    // daxa_RWBufferPtr(PRIMITIVE_AABBS) aabb_buffer;
};