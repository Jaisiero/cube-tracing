#pragma once

#define DAXA_RAY_TRACING 1
#include <daxa/daxa.inl>

// #define MAX_LEVELS 2

// #define MAX_INSTANCES 4194304U // Theoretically 31'580'641 (4'294'967'296 / 136 [instance size])
// #define MAX_PRIMITIVES 134 217 728U // Theoretically 178'956'970 (4'294'967'296 / 24 [AABB size])
// #define MAX_MATERIALS 10000U

#define MAX_INSTANCES 983040U
#define MAX_PRIMITIVES 134217728U
#define MAX_MATERIALS 10000U
#define MAX_LIGHTS 10000U
#define MAX_TEXTURES 100ULL

#define PERFECT_PIXEL_ON 0
#define DIALECTRICS_DONT_BLOCK_LIGHT 1

// #define DYNAMIC_SUN_LIGHT 0
#define POINT_LIGHT_ON 1
// #define SUN_MIDDAY 1
#define SUN_MAX_INTENSITY 2000.0f
#define SUN_TOP_POSITION_X 0.0f
#define SUN_TOP_POSITION_Y 15.0f
#define SUN_TOP_POSITION_Z -5.0f

// #define LEVEL_0_VOXEL_EXTENT 0.25
// #define LEVEL_1_VOXEL_EXTENT 0.125
// #define VOXEL_EXTENT 0.015625f
#define AVOID_LIGHT_LEAKS 0.000
#define VOXEL_COUNT_BY_AXIS 8 // 2^3
#define CHUNK_VOXEL_COUNT VOXEL_COUNT_BY_AXIS * VOXEL_COUNT_BY_AXIS * VOXEL_COUNT_BY_AXIS
// #define VOXEL_EXTENT 0.015625f
#define VOXEL_EXTENT 0.03125f
#define HALF_VOXEL_EXTENT VOXEL_EXTENT * 0.5f
#define CHUNK_EXTENT VOXEL_EXTENT * VOXEL_COUNT_BY_AXIS

#define DAXA_PI 3.1415926535897932384626433832795f
#define DAXA_2PI 6.283185307179586476925286766559f
#define DAXA_4PI 12.566370614359172953850573533118f
#define INV_DAXA_PI 0.31830988618379067153776752674503f
#define INV_DAXA_2PI 0.15915494309189533576888376337251f
#define INV_DAXA_4PI 0.079577471545947667884441881686255f

#define HLF_MAX 6.5504e+4F // max value for half float
#define HLF_MIN 1.175494351e-38F  // min value for float

#define SAMPLES_PER_PIXEL 1
#define SAMPLE_OFFSET 1e-3f // Multi sample offset
#define MAX_DEPTH 3
#define AVOID_VOXEL_COLLAIDE HLF_MIN   // minimum offset to avoid voxel collision
#define CUBE_FACE_COUNT 6

#define PERLIN_FACTOR 500

#define SCREEN_SIZE_X 3840
#define SCREEN_SIZE_Y 2160

#define MAX_RESERVOIRS SCREEN_SIZE_X * SCREEN_SIZE_Y

#define PERFECT_PIXEL_BIT 1U << 0
#define TAA_BIT 1U << 1

struct AABB
{
  daxa_f32vec3 minimum;
  daxa_f32vec3 maximum;
};

struct OBJECT_INFO
{
  daxa_u32 instance_id;
  daxa_u32 primitive_id;
};

struct OBJECT_HIT
{
  OBJECT_INFO object;
  daxa_f32vec3 hit;
};

struct Ray
{
  daxa_f32vec3 origin;
  daxa_f32vec3 direction;
};


struct HIT_PAY_LOAD
{
    daxa_f32vec3 hit_value;
    // daxa_f32vec3 throughput;
    daxa_u32 depth;
    daxa_b32 done;
    daxa_u32 seed;
    daxa_f32 distance;
    daxa_f32vec3 world_hit;
    daxa_f32vec3 world_nrm;
    daxa_u32 mat_index;
    daxa_f32vec3 ray_scatter_dir;
    OBJECT_INFO instance_hit;
};

struct HIT_INDIRECT_PAY_LOAD
{
    daxa_f32vec3 hit_value;
    daxa_u32 depth;
    daxa_u32 seed;
};

struct HIT_MAT_PAY_LOAD
{
    daxa_f32vec3 hit;
    daxa_f32vec3 nrm;
    daxa_f32vec3 hit_value;
    daxa_ImageViewId texture_id;
    daxa_SamplerId sampler_id;
};

struct HIT_SCATTER_PAY_LOAD
{
    daxa_f32vec3 hit;
    daxa_f32vec3 nrm;
    daxa_f32vec3 ray_dir;
    daxa_u32 seed;
    daxa_f32vec3 scatter_dir;
    daxa_u32 mat_idx;
    daxa_b32 done;
    OBJECT_INFO instance_hit;
    daxa_f32 pdf;
};

struct HIT_INFO
{
  daxa_b32 is_hit;
  daxa_f32 hit_distance;
  daxa_f32 exit_distance;
  daxa_f32vec3 world_hit;
  daxa_f32vec3 world_nrm;
  daxa_f32vec3 obj_hit;
  OBJECT_INFO instance_hit;
  daxa_f32vec3 primitive_center;
  daxa_u32 material_index;
  daxa_f32vec2 uv;
};

struct HIT_INFO_INPUT
{
  daxa_f32vec3 world_hit;
  daxa_f32vec3 world_nrm;
  daxa_f32 distance;
  daxa_f32vec3 scatter_dir;
  OBJECT_INFO instance_hit;
  daxa_u32 mat_idx;
};

struct HIT_INFO_OUTPUT
{
    daxa_f32vec3 world_hit;
    daxa_f32vec3 world_nrm;
    OBJECT_INFO instance_hit;
    daxa_f32vec3 scatter_dir;
    daxa_u32 mat_idx;
    daxa_u32 seed;
    daxa_u32 depth;
};


struct camera_view{ 
    daxa_f32mat4x4 inv_view;
    daxa_f32mat4x4 inv_proj;
    daxa_f32 defocus_angle;
    daxa_f32 focus_dist;
    daxa_f32mat4x4 prev_inv_view;
    daxa_f32mat4x4 prev_inv_proj;
};
DAXA_DECL_BUFFER_PTR(camera_view)


struct LIGHT_CONFIG {
    daxa_u32 point_light_count;
    daxa_f32 point_light_pdf;
    daxa_u32 cube_light_count;
    daxa_f32 cube_light_pdf;
    daxa_u32 sphere_light_count;
    daxa_f32 sphere_light_pdf;
    daxa_u32 analytic_light_count;
    daxa_f32 analytic_light_pdf;
    daxa_u32 env_map_count;
    daxa_f32 env_map_pdf;
    daxa_u32 light_count;
};

struct Status
{
    daxa_u32 frame_number;
    daxa_u64 num_accumulated_frames;
    daxa_u32vec2 pixel;
    daxa_u32 is_active;
    daxa_u64 light_config_address;
    daxa_u32 obj_count;
    daxa_f32 time;
    daxa_b32 is_afternoon;
    daxa_u32 max_depth;
};
DAXA_DECL_BUFFER_PTR(Status)

struct INSTANCE
{
    daxa_f32mat4x4 transform;
    daxa_f32mat4x4 prev_transform;
    daxa_u32 first_primitive_index;
    daxa_u32 primitive_count;
};

struct WORLD
{
    daxa_u64 instance_address;
    daxa_u64 primitive_address;
    daxa_u64 aabb_address;
    daxa_u64 material_address;
    daxa_u64 light_address;
};
DAXA_DECL_BUFFER_PTR(WORLD)

struct PRIMITIVE
{
    daxa_u32 material_index;
};




#define MATERIAL_TYPE_LAMBERTIAN 0
#define MATERIAL_TYPE_METAL 1
#define MATERIAL_TYPE_DIELECTRIC 2
#define MATERIAL_TYPE_CONSTANT_MEDIUM 3
#define MATERIAL_TYPE_MAX_ENUM 4

#define MATERIAL_TYPE_MASK 0xFF
#define MATERIAL_TEXTURE_ON 1U << 31
#define MATERIAL_PERLIN_ON 1U << 30

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
    // daxa_ImageViewId   texture_id;
    // daxa_SamplerId   sampler_id;
};




struct INTERSECT {
    daxa_b32 is_hit;
    daxa_f32 distance;
    daxa_f32vec3 world_hit;
    daxa_f32vec3 world_nrm;
    daxa_f32vec3 wo;
    daxa_f32vec3 wi;
    OBJECT_INFO instance_hit;
    daxa_u32 material_idx;
    MATERIAL mat;
};


#define GEOMETRY_LIGHT_POINT 0
#define GEOMETRY_LIGHT_CUBE 1
#define GEOMETRY_LIGHT_SPEHERE 2
#define GEOMETRY_LIGHT_ANALITIC 3
#define GEOMETRY_LIGHT_ENV_MAP 4
#define GEOMETRY_LIGHT_MAX_ENUM GEOMETRY_LIGHT_ENV_MAP + 1

struct LIGHT
{
    daxa_f32vec3 position;
    daxa_f32vec3 emissive;
    OBJECT_INFO instance_info;
    daxa_f32 size;
    daxa_u32 type; // 0: point, 1: quad, 2: sphere
};


// struct STATUS_OUTPUT
// {
//     OBJECT_INFO instance_hit;
//     daxa_f32 hit_distance;
//     daxa_f32 exit_distance;
//     daxa_f32vec3 hit_position;
//     daxa_f32vec3 hit_normal;
//     daxa_f32vec3 origin;
//     daxa_f32vec3 direction;
//     daxa_f32vec3 primitive_center;
//     daxa_u32 material_index;
//     daxa_f32vec2 uv;
// };
// DAXA_DECL_BUFFER_PTR(STATUS_OUTPUT)


struct RESTIR {
    daxa_u64 previous_reservoir_address;
    daxa_u64 intermediate_reservoir_address;
    daxa_u64 reservoir_address;
    daxa_u64 previous_di_address;
    daxa_u64 di_address;
    daxa_u64 velocity_address;
    daxa_u64 pixel_reconnection_data_address;
    daxa_u64 output_path_reservoir_address;
    daxa_u64 temporal_path_reservoir_address;
    daxa_u64 indirect_color_address;
};
DAXA_DECL_BUFFER_PTR(RESTIR)

struct RESERVOIR
{
    daxa_u32 Y; // index of most important light
    daxa_u32 seed; // random seed for resampling
    daxa_f32 W_y; // light weight
    daxa_f32 W_sum; // sum of all weights for all lights processed
    daxa_f32 M; // number of lights processed for this reservoir
    daxa_f32vec3 F; // integrand of the light
};




// credits: Generalized Resampled Importance Sampling: Foundations of ReSTIR - Daqi 2022
struct RECONNECTION_DATA
{
    OBJECT_HIT rc_prev_hit;
    daxa_f32vec3 rc_prev_wo;
    daxa_f32vec3 path_throughput;
};

#define RCDATA_PAD_SIZE 2U
#define MAX_RESTIR_PT_NEIGHBOR_COUNT 3U
#define RCDATA_PATH_NUM MAX_RESTIR_PT_NEIGHBOR_COUNT * 2U // 2 for each depth cause we need to evaluate that the reconnection is bijective


struct PIXEL_RECONNECTION_DATA 
{
    RECONNECTION_DATA data[RCDATA_PATH_NUM];
};


#if BPR// path reuse
const int K_RC_ATTR_COUNT = 2;
#else
const int K_RC_ATTR_COUNT = 1;
#endif


// TODO: not sure if this is needed
// struct PATH_REUSE_MIS_WEIGHT
// {
//     float rc_BSDF_MIS_weight;
//     float rc_NEE_MIS_weight;
// };

// 88/128 B
struct PATH_RESERVOIR
{
    daxa_f32 M; // this is a float, because temporal history length is allowed to be a fraction. 
    daxa_f32 weight; // during RIS and when used as a "RisState", this is w_sum; during RIS when used as an incoming reservoir or after RIS, this is 1/p(y) * 1/M * w_sum
    daxa_u32 path_flags; // this is a path type indicator, see the struct definition for details
    daxa_u32 rc_random_seed; // saved random seed after rc_vertex (due to the need of blending half-vector reuse and random number replay)
    daxa_f32vec3 F; // cached integrand (always updated after a new path is chosen in RIS)
    daxa_f32 light_pdf; // NEE light pdf (might change after shift if transmission is included since light sampling considers "upperHemisphere" of the previous bounce)?
    daxa_f32vec3 cached_jacobian; // saved previous vertex scatter PDF, scatter PDF, and geometry term at rc_vertex (used when rc_vertex is not v2)
    daxa_u32 init_random_seed; // saved random seed at the first bounce (for recovering the random distance threshold for hybrid shift)
    OBJECT_HIT rc_vertex_hit; // hitinfo of the reconnection vertex
    daxa_f32vec3 rc_vertex_wi[K_RC_ATTR_COUNT]; // incident direction on reconnection vertex
    daxa_f32vec3 rc_vertex_irradiance[K_RC_ATTR_COUNT]; // sampled irradiance on reconnection vertex

#if BPR
    daxa_f32 rc_light_pdf; 
    daxa_f32vec3 rc_vertex_BSDF_light_sampling_irradiance;
#endif
};

struct VELOCITY
{
    daxa_f32vec2 velocity;
};

struct DIRECT_ILLUMINATION_INFO
{
    daxa_f32vec3 position;
    daxa_f32 distance;
    daxa_f32vec3 normal;
    daxa_f32vec3 ray_origin;
    daxa_u32 seed;
    OBJECT_INFO instance_hit;
    daxa_u32 mat_index;
    daxa_f32 confidence;
};

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

struct PushConstant
{
    daxa_u32vec2 size;
    daxa_TlasId tlas;
    daxa_ImageViewId swapchain;
    daxa_ImageViewId previous_swapchain;
    daxa_ImageViewId taa_frame;
    daxa_ImageViewId taa_prev_frame;
    daxa_BufferPtr(camera_view) camera_buffer;
    daxa_BufferPtr(Status) status_buffer;
    daxa_BufferPtr(WORLD) world_buffer;
    // daxa_RWBufferPtr(STATUS_OUTPUT) status_output_buffer; 
    daxa_RWBufferPtr(RESTIR) restir_buffer;
    // daxa_RWBufferPtr(HIT_DISTANCES) hit_distance_buffer;
    // daxa_RWBufferPtr(INSTANCE_LEVELS) instance_level_buffer;
    // daxa_RWBufferPtr(INSTANCE_DISTANCES) instance_distance_buffer;
    // daxa_RWBufferPtr(PRIMITIVE_AABBS) aabb_buffer;
};