#pragma once

#define DAXA_RAY_TRACING 1
#include <daxa/daxa.inl>

// #define MAX_LEVELS 2

#define MAX_INSTANCES 10000
#define MAX_PRIMITIVES 100000
#define MAX_MATERIALS 10000
#define MAX_LIGHTS 20
#define MAX_TEXTURES 100ULL

#define DEBUG_NORMALS_ON 0
#define PERFECT_PIXEL_ON 1
#define DIALECTRICS_DONT_BLOCK_LIGHT 1
#define ACCUMULATOR_ON 0
#define DYNAMIC_SUN_LIGHT 0

// #define LEVEL_0_VOXEL_EXTENT 0.25
// #define LEVEL_1_VOXEL_EXTENT 0.125

#define VOXEL_EXTENT 0.125f
#define AVOID_LIGHT_LEAKS 0.000
#define VOXEL_COUNT_BY_AXIS 8 // 2^3
#define CHUNK_VOXEL_COUNT VOXEL_COUNT_BY_AXIS * VOXEL_COUNT_BY_AXIS * VOXEL_COUNT_BY_AXIS

#define SAMPLES_PER_PIXEL 5
#define SAMPLE_OFFSET 1e-6f // Multi sample offset
#define MAX_DEPTH 5
#define DELTA_RAY 0.0001f   // Delta ray offset for shadow rays
#define AVOID_VOXEL_COLLAIDE 1e-6f   // Delta ray offset for shadow rays


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

struct HIT_INFO
{
  daxa_b32 is_hit;
  daxa_f32 hit_distance;
  daxa_f32 exit_distance;
  daxa_f32vec3 world_pos;
  daxa_f32vec3 world_nrm;
  daxa_i32 instance_id;
  daxa_i32 primitive_id;
  daxa_f32vec3 primitive_center;
  daxa_u32 material_index;
  daxa_f32vec2 uv;
};

struct camera_view{ 
    daxa_f32mat4x4 inv_view;
    daxa_f32mat4x4 inv_proj;
    daxa_f32 defocus_angle;
    daxa_f32 focus_dist;
};
DAXA_DECL_BUFFER_PTR(camera_view)

struct Status
{
    daxa_u32 frame_number;
    daxa_u32 num_accumulated_frames;
    daxa_u32vec2 pixel;
    daxa_b32 is_active;
    daxa_u32 light_count;
    daxa_f32 time;
    daxa_b32 is_afternoon;
};
DAXA_DECL_BUFFER_PTR(Status)

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




#define MATERIAL_TYPE_LAMBERTIAN 0
#define MATERIAL_TYPE_METAL 1
#define MATERIAL_TYPE_DIELECTRIC 2
#define MATERIAL_TYPE_CONSTANT_MEDIUM 3
#define MATERIAL_TYPE_MAX_ENUM 4

#define MATERIAL_TYPE_MASK 0xFF
#define MATERIAL_TEXTURE_ON 1U << 31

struct MATERIAL
{
    daxa_u32 type;      // lowest 8 bits -> 0: lambertian, 1: metal, 2: dielectric (glass), 3: constant medium (fog)
                        // uppest bit -> texture on/off
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
    daxa_ImageViewId   texture_id;
    daxa_SamplerId   sampler_id;
};

struct MATERIALS
{
    MATERIAL materials[MAX_MATERIALS];
};
DAXA_DECL_BUFFER_PTR(MATERIALS)


struct LIGHT
{
    daxa_f32vec3 position;
    daxa_f32 intensity;
    daxa_f32 distance;
    daxa_u32 type; // 0: point light, 1: directional light
};

struct LIGHTS
{
    LIGHT lights[MAX_LIGHTS];
};
DAXA_DECL_BUFFER_PTR(LIGHTS)


struct STATUS_OUTPUT
{
    daxa_u32 instance_id;
    daxa_u32 primitive_id;
    daxa_f32 hit_distance;
    daxa_f32 exit_distance;
    daxa_f32vec3 hit_position;
    daxa_f32vec3 hit_normal;
    daxa_f32vec3 origin;
    daxa_f32vec3 direction;
    daxa_f32vec3 primitive_center;
    daxa_u32 material_index;
    daxa_f32vec2 uv;
};
DAXA_DECL_BUFFER_PTR(STATUS_OUTPUT)

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

// #define WIDTH_RES 3840
// #define HEIGHT_RES 2160

// struct HIT_DISTANCE
// {
//     daxa_f32 distance;
//     daxa_f32vec3 position;
//     daxa_f32vec3 normal;
//     daxa_u32 instance_index;
//     daxa_u32 primitive_index;
// };

// struct HIT_DISTANCES
// {
//     HIT_DISTANCE hit_distances[WIDTH_RES*HEIGHT_RES];
// };
// DAXA_DECL_BUFFER_PTR(HIT_DISTANCES)

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
    daxa_BufferPtr(camera_view) camera_buffer;
    daxa_BufferPtr(Status) status_buffer;
    daxa_BufferPtr(INSTANCES) instance_buffer;
    daxa_BufferPtr(PRIMITIVES) primitives_buffer;
    daxa_BufferPtr(MATERIALS) materials_buffer;
    daxa_BufferPtr(LIGHTS) light_buffer;
    daxa_RWBufferPtr(STATUS_OUTPUT) status_output_buffer; 
    // daxa_RWBufferPtr(HIT_DISTANCES) hit_distance_buffer;
    // daxa_RWBufferPtr(INSTANCE_LEVELS) instance_level_buffer;
    // daxa_RWBufferPtr(INSTANCE_DISTANCES) instance_distance_buffer;
    // daxa_RWBufferPtr(PRIMITIVE_AABBS) aabb_buffer;
};