#pragma once
#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>
#include "shared.inl"

DAXA_DECL_PUSH_CONSTANT(PushConstant, p)

#if DAXA_SHADER_STAGE == DAXA_SHADER_STAGE_RAYGEN
layout(location = 0) rayPayloadEXT HIT_PAY_LOAD prd;
layout(location = 1) rayPayloadEXT bool is_shadowed;
layout(location = 4) callableDataEXT HIT_SCATTER_PAY_LOAD call_scatter;
#elif DAXA_SHADER_STAGE == DAXA_SHADER_STAGE_CLOSEST_HIT
layout(location = 0) rayPayloadInEXT HIT_PAY_LOAD prd;
layout(location = 1) rayPayloadEXT bool is_shadowed;
layout(location = 3) callableDataEXT HIT_MAT_PAY_LOAD hit_call;
layout(location = 4) callableDataEXT HIT_SCATTER_PAY_LOAD call_scatter;
#elif DAXA_SHADER_STAGE == DAXA_SHADER_STAGE_CALLABLE
layout(location = 4) callableDataInEXT HIT_SCATTER_PAY_LOAD call_scatter;
#elif DAXA_SHADER_STAGE == DAXA_SHADER_STAGE_ANY_HIT
layout(location = 0) rayPayloadInEXT HIT_PAY_LOAD prd;
#endif

#define DEBUG_NORMALS_ON 0
#define ACCUMULATOR_ON 1
#define FORCE_ACCUMULATOR_ON 0

#define RESTIR_ON 1
#define RESTIR_DI_ON 1
#define RESTIR_DI_TEMPORAL_ON 0
#define RESTIR_DI_SPATIAL_ON 0
#define RESTIR_PT_ON 1
#define RESTIR_PT_TEMPORAL_ON 1
#define RESTIR_PT_SPATIAL_ON 1

#define DIRECT_ILLUMINATION_ON 1
#define DIRECT_EMITTANCE_ON 1
#define INDIRECT_ILLUMINATION_ON 0
#define CALLABLE_ON 1

#define KNOWN_LIGHT_POSITION 1

#define COSINE_HEMISPHERE_SAMPLING 1
#define USE_POWER_HEURISTIC 1
#define USE_POWER_EXP_HEURISTIC 0

#define DELTA_RAY 1e-6f   // Delta ray offset for shadow rays
#define MAX_DISTANCE 1e9f // Max distance for shadow rays
#define MIN_COS_THETA 1e-6f


// TODO: M by parameter?
const daxa_u32 MIN_RIS_SAMPLE_COUNT = 4;
const daxa_u32 MAX_RIS_SAMPLE_COUNT = 32;
const daxa_f32 MIN_INFLUENCE_FROM_THE_PAST_THRESHOLD = 10.0f;
const daxa_f32 MAX_INFLUENCE_FROM_THE_PAST_THRESHOLD = 20.0f;
const daxa_u32 MIN_NUM_OF_NEIGHBORS = 3;
const daxa_u32 MAX_NUM_OF_NEIGHBORS = 8;
const daxa_f32 MIN_NEIGHBORS_RADIUS = 2.0f;
const daxa_f32 MAX_NEIGHBORS_RADIUS = 25.0f;
const daxa_f32 MIN_CLOSE_NEIGHBORS_RADIUS = 2.0f;
const daxa_f32 MAX_CLOSE_NEIGHBORS_RADIUS = 5.0f;
const daxa_f32 MAX_DISTANCE_TO_HIT = 1e3f;
const daxa_f32 REJECTING_THRESHOLD = 1.f;

const daxa_b32 TEMPORAL_UPDATE_FOR_DYNAMIC_SCENE = true;
const daxa_b32 NEAR_FIELD_REJECTION = true;
const daxa_f32 NEAR_FIELD_DISTANCE = HALF_VOXEL_EXTENT * 0.5f;
const daxa_b32 ROUGHNESS_BASED_REJECTION = false;
const daxa_f32 SPECULAR_ROUGHNESS_THRESHOLD = 0.2f; // 0.2f;
const daxa_b32 REJECT_BASED_ON_JACOBIAN = false;
const daxa_f32 JACOBIAN_REJECTION_THRESHOLD = 0.1f;
const daxa_f32 MAX_INFLUENCE_FROM_THE_PAST_THRESHOLD_PT = 20.0f;
const daxa_b32 USE_RUSSIAN_ROULETTE = false;
const daxa_b32 COMPUTE_ENVIRONMENT_LIGHT = true;
const daxa_i32 NEIGHBOR_COUNT = 3;
const daxa_i32 NEIGHBOR_RADIUS = 1;



// PATH FLAGS
const daxa_u32 PATH_FLAG_ACTIVE = 0x1;
const daxa_u32 PATH_FLAG_HIT = 0x2;
const daxa_u32 PATH_FLAG_TRANSMISSION = 0x4;
const daxa_u32 PATH_FLAG_SPECULAR = 0x8;
const daxa_u32 PATH_FLAG_DELTA = 0x10;
const daxa_u32 PATH_FLAG_VOLUME = 0x20;
const daxa_u32 PATH_FLAG_INSIDE_DIELECTRIC_VOLUME = 0x40;
const daxa_u32 PATH_FLAG_LIGHT_SAMPLED_UPPER = 0x80;
const daxa_u32 PATH_FLAG_LIGHT_SAMPLED_LOWER = 0x100;
const daxa_u32 PATH_FLAG_DIFFUSE_PRIMARY_HIT = 0x200;
const daxa_u32 PATH_FLAG_FREE_PATH = 0x400;
const daxa_u32 PATH_FLAG_SPECULAR_BOUNCE = 0x800;
const daxa_u32 PATH_FLAG_SPECULAR_PRIMARY_HIT = 0x1000;


// BOUNCE TYPES
const daxa_u32 BOUNCE_TYPE_DIFFUSE = 0;
const daxa_u32 BOUNCE_TYPE_SPECULAR = 1;
// const daxa_u32 BOUNCE_TYPE_TRANSMISSION = 2;
// const daxa_u32 BOUNCE_TYPE_VOLUME = 3;


// SHIFT MAPPING
const daxa_u32 SHIFT_MAPPING_RECONNECTION = 0;
const daxa_u32 SHIFT_MAPPING_RANDOM_REPLAY = 1;
const daxa_u32 SHIFT_MAPPING_HYBRID = 2;


struct SCENE_PARAMS{
    daxa_u32 light_count;
    daxa_u32 object_count;
    daxa_u32 max_depth;
    daxa_b32 temporal_update_for_dynamic_scene;
    daxa_u32 shift_mapping;
    daxa_u32 stategy_flags;
    daxa_b32 distance_based_rejection;
    daxa_f32 near_field_distance;
    daxa_b32 roughness_based_rejection;
    daxa_f32 roughness_threshold;
    daxa_b32 reject_based_on_jacobian;
    daxa_f32 jacobian_rejection_threshold;
    daxa_b32 use_russian_roulette;
    daxa_b32 compute_environment_light;
    daxa_u32 neighbor_count;
    daxa_i32 neighbor_radius;
};


layout(buffer_reference, scalar) buffer INSTANCES_BUFFER {INSTANCE instances[MAX_INSTANCES]; }; // Positions of an object
layout(buffer_reference, scalar) buffer PRIMITIVE_BUFFER {PRIMITIVE primitives[MAX_PRIMITIVES]; }; // Primitive data
layout(buffer_reference, scalar) buffer AABB_BUFFER {AABB aabbs[MAX_PRIMITIVES]; }; // Positions of a primitive
layout(buffer_reference, scalar) buffer MATERIAL_BUFFER {MATERIAL materials[MAX_MATERIALS]; }; // Materials
layout(buffer_reference, scalar) buffer LIGHT_BUFFER {LIGHT lights[MAX_LIGHTS]; }; // Lights
layout(buffer_reference, scalar) buffer LIGHT_CONFIG_BUFFER {LIGHT_CONFIG light_config; }; // Lights

layout(buffer_reference, scalar) buffer PREV_RESERVOIR_BUFFER {RESERVOIR reservoirs[MAX_RESERVOIRS]; }; // Reservoirs from the previous frame
layout(buffer_reference, scalar) buffer INT_RESERVOIR_BUFFER {RESERVOIR reservoirs[MAX_RESERVOIRS]; }; // Intermediate reservoirs
layout(buffer_reference, scalar) buffer RESERVOIR_BUFFER {RESERVOIR reservoirs[MAX_RESERVOIRS]; }; // Reservoirs from the current frame
layout(buffer_reference, scalar) buffer VELOCITY_BUFFER {VELOCITY velocities[MAX_RESERVOIRS]; }; // Velocities
layout(buffer_reference, scalar) buffer PREV_DI_BUFFER {DIRECT_ILLUMINATION_INFO di_info[MAX_RESERVOIRS]; }; // Direct illumination info
layout(buffer_reference, scalar) buffer DI_BUFFER {DIRECT_ILLUMINATION_INFO di_info[MAX_RESERVOIRS]; }; // Direct illumination info


layout(buffer_reference, scalar) buffer INDIRECT_COLOR_BUFFER {daxa_f32vec3 colors[MAX_RESERVOIRS]; }; // Indirect color


layout(buffer_reference, scalar) buffer PIXEL_RECONNECTION_DATA_BUFFER {PIXEL_RECONNECTION_DATA reconnections[MAX_RESERVOIRS]; }; // Pixel reconnection data
layout(buffer_reference, scalar) buffer OUTPUT_PATH_RESERVOIR_BUFFER {PATH_RESERVOIR path_reservoirs[MAX_RESERVOIRS]; }; // Path reservoirs
layout(buffer_reference, scalar) buffer TEMPORAL_PATH_RESERVOIR_BUFFER {PATH_RESERVOIR path_reservoirs[MAX_RESERVOIRS]; }; // Path reservoirs
