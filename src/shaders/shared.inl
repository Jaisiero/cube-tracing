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
#define MAX_LIGHTS 400U
#define MAX_TEXTURES 100ULL

#define PERFECT_PIXEL_ON 0
#define DIALECTRICS_DONT_BLOCK_LIGHT 1

#define DYNAMIC_SUN_LIGHT 0
#define SUN_MIDDAY 0
#define SUN_MAX_INTENSITY 5000.0f

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
#define INV_DAXA_PI 0.31830988618379067153776752674503f

#define SAMPLES_PER_PIXEL 1
#define SAMPLE_OFFSET 1e-6f // Multi sample offset
#define MAX_DEPTH 3
#define AVOID_VOXEL_COLLAIDE 1e-9f   // Delta ray offset for shadow rays

#define PERLIN_FACTOR 500

#define SCREEN_SIZE_X 3840
#define SCREEN_SIZE_Y 2160

#define MAX_RESERVOIRS SCREEN_SIZE_X * SCREEN_SIZE_Y

struct AABB
{
  daxa_f32vec3 minimum;
  daxa_f32vec3 maximum;
};

struct INSTANCE_HIT
{
  daxa_u32 instance_id;
  daxa_u32 primitive_id;
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
    INSTANCE_HIT instance_hit;
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
    INSTANCE_HIT instance_hit;
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
  INSTANCE_HIT instance_hit;
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
  INSTANCE_HIT instance_hit;
  daxa_u32 mat_idx;
  daxa_u32 seed;
  daxa_u32 depth;
};

struct HIT_INFO_OUTPUT
{
    daxa_f32vec3 world_hit;
    daxa_f32vec3 world_nrm;
    INSTANCE_HIT instance_hit;
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

struct Status
{
    daxa_u32 frame_number;
    daxa_u32 num_accumulated_frames;
    daxa_u32vec2 pixel;
    daxa_b32 is_active;
    daxa_u32 light_count;
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
    daxa_ImageViewId   texture_id;
    daxa_SamplerId   sampler_id;
};




struct INTERSECT {
    daxa_b32 is_hit;
    daxa_f32 distance;
    daxa_f32vec3 world_hit;
    daxa_f32vec3 world_nrm;
    daxa_f32vec3 scatter_dir;
    INSTANCE_HIT instance_hit;
    daxa_u32 material_idx;
    MATERIAL mat;
};


#define GEOMETRY_LIGHT_POINT 0
#define GEOMETRY_LIGHT_CUBE 1
#define GEOMETRY_LIGHT_SPEHERE 2
#define GEOMETRY_LIGHT_MAX_ENUM 3

struct LIGHT
{
    daxa_f32vec3 position;
    daxa_f32vec3 emissive;
    INSTANCE_HIT instance_info;
    daxa_u32 type; // 0: point, 1: quad, 2: sphere
};


// struct STATUS_OUTPUT
// {
//     INSTANCE_HIT instance_hit;
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
};
DAXA_DECL_BUFFER_PTR(RESTIR)

struct RESERVOIR
{
    daxa_u32 Y; // index of most important light
    daxa_f32 W_y; // light weight
    daxa_f32 W_sum; // sum of all weights for all lights processed
    daxa_f32 M; // number of lights processed for this reservoir
    daxa_f32 p_hat; // p_hat of the light
};




// credits: Generalized Resampled Importance Sampling: Foundations of ReSTIR - Daqi 2022
struct RECONNECTION_DATA
{
    INSTANCE_HIT instance_hit;
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
    daxa_f32 weight; // during RIS and when used as a "RisState", this is w_sum; during RIS when used as an incoming reseroivr or after RIS, this is 1/p(y) * 1/M * w_sum
    daxa_i32 path_flags; // this is a path type indicator, see the struct definition for details
    daxa_u32 rc_random_seed; // saved random seed after rcVertex (due to the need of blending half-vector reuse and random number replay)
    daxa_f32vec3 F; // cached integrand (always updated after a new path is chosen in RIS)
    daxa_f32 light_pdf; // NEE light pdf (might change after shift if transmission is included since light sampling considers "upperHemisphere" of the previous bounce)?
    daxa_f32vec3 cached_jacobian; // saved previous vertex scatter PDF, scatter PDF, and geometry term at rcVertex (used when rcVertex is not v2)
    daxa_u32 init_random_seed; // saved random seed at the first bounce (for recovering the random distance threshold for hybrid shift)
    INSTANCE_HIT rc_vertex_hit; // hitinfo of the reconnection vertex
    daxa_f32vec3 rc_vertex_wi[K_RC_ATTR_COUNT]; // incident direction on reconnection vertex
    daxa_f32vec3 rc_vertex_irradiance[K_RC_ATTR_COUNT]; // sampled irradiance on reconnection vertex

#if BPR
    daxa_f32 rc_light_pdf; 
    daxa_f32vec3 rc_vertex_BSDF_light_sampling_irradiance;
#endif
};

/// Builds a Path and a PathPrefix.
struct PATH_BUILDER
{
    INSTANCE_HIT rc_vertex_hit;
    daxa_f32vec3 rc_vertex_wi[K_RC_ATTR_COUNT];
    daxa_u32 cached_random_seed;
    // TinyUniformSampleGenerator sg;
    daxa_u32 rc_vertex_length;
    daxa_u32 path_flags; // this is a path type indicator, see the struct definition for details
    daxa_f32vec3 cached_jacobian;
};

/** Live state for the path tracer.
 */
struct PATH_STATE
{
    daxa_u32 id; ///< Path ID encodes (pixel, sampleIdx) with 12 bits each for pixel x|y and 8 bits for sample index.

    // daxa_u16
    daxa_u32
        flags; ///< Flags indicating the current status. This can be multiple PathFlags flags OR'ed together.
    // daxa_u16
    daxa_u32
        length; ///< Path length (0 at origin, 1 at first secondary hit, etc.).
    // daxa_u16
    daxa_u32
        rejected_hits; ///< Number of false intersections rejected along the path. This is used as a safeguard to avoid deadlock in pathological cases.
    // daxa_f16
    daxa_f32
        scene_length;         ///< Path length in scene units (0.f at primary hit).
    daxa_u32 bounce_counters; ///< Packed counters for different types of bounces (see BounceType).

    // Scatter ray
    daxa_f32vec3 origin; ///< Origin of the scatter ray.
    daxa_f32vec3 dir;    ///< Scatter ray normalized direction.
    daxa_f32vec3 pdf;    ///< Pdf for generating the scatter ray.
    daxa_f32vec3 normal; ///< Shading normal at the scatter ray origin.
    INSTANCE_HIT hit;    ///< Hit information for the scatter ray. This is populated at committed triangle hits.

    daxa_f32vec3 thp;       ///< Path throughput.
    daxa_f32vec3 prefix_thp; /// daqi: used for computing rcVertexIrradiance[1]

    // daxa_f32vec3 rc_vertex_path_tree_irradiance; // TODO: for volume rendering

    daxa_f32vec3 L;            ///< Accumulated path contribution.
    // daxa_f32vec3 L_delta_direct; // daqi: save the direct lighting on delta surfaces

    // daxa_f32      russianRoulettePdf = 1.f;
    daxa_f32vec3 shared_scatter_dir;
    daxa_f32 prev_scatter_pdf;

    INSTANCE_HIT rc_prev_vertex_hit; // daqi: save the previous vertex of rcVertex, used in hybrid shift replay, for later reconnection
    daxa_f32vec3 rc_prev_vertex_wo;  // daqi: save the outgoing direction at the previous vertex of rcVertex, used in hybrid shift replay, for later reconnection

    daxa_f32 hit_dist; // for NRD

    // InteriorList interiorList;      ///< Interior list. Keeping track of a stack of materials with medium properties.
    // SampleGenerator sg;             ///< Sample generator state. Typically 4-16B.

    PATH_BUILDER path_builder; ///< Importance samples the path from the path tree.
    PATH_RESERVOIR path_reservoir;

    // TODO: pack those as flags
    daxa_b32 enable_random_replay;    // daqi: indicate the pathtracer is doing random number replay (being called from resampling stage)
    daxa_b32 random_replay_is_NEE;     // daqi: indicate the base path is a NEE path, therefore the random replay should also terminates as a NEE path
    daxa_b32 random_replay_is_escaped; // daqi: indicate the base path is a escaped path, therefore the random replay should also terminates as a escaped path
    daxa_u32 random_replay_length;    // daqi: the length of the random replay (same as the path length of the base path)
    daxa_b32 use_hybrid_shift;
    // this is used for hybrid shift or hybrid shift is being MIS'ed with (at both initial candidate generation and resampling)
    daxa_b32 is_replay_for_hybrid_shift;        // daqi: indicate that a random number replay is done with the hybrid shift in mind (invalidated if invertibility is violated)
    daxa_b32 is_last_vertex_classified_as_rough; // daqi: remembers if last vertex is classified as a diffuse vertex (used for specularskip in hybrid shift)
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
    daxa_f32vec3 scatter_dir;
    daxa_u32 seed;
    INSTANCE_HIT instance_hit;
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