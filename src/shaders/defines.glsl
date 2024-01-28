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
#define ACCUMULATOR_ON 0

#define LIGHT_SAMPLING_ON 1
#define RESERVOIR_ON 1
#define RESERVOIR_TEMPORAL_ON 1
#define RESERVOIR_SPATIAL_ON 1

#define INDIRECT_ILLUMINATION_ON 0
#define MIS_ON 0
#define CALLABLE_ON 1
// #define DEBUG_NORMALS 1

#define DELTA_RAY 1e-6f   // Delta ray offset for shadow rays
#define MAX_DISTANCE 1e9f // Max distance for shadow rays

// TODO: M by parameter?
const daxa_u32 M = 32;
const daxa_f32 INFLUENCE_FROM_THE_PAST_THRESHOLD = 10.0f;
const daxa_u32 NUM_OF_NEIGHBORS = 8;
const daxa_f32 NEIGHBORS_RADIUS = 10.0f;

layout(buffer_reference, scalar) buffer INSTANCES_BUFFER {INSTANCE instances[MAX_INSTANCES]; }; // Positions of an object
layout(buffer_reference, scalar) buffer PRIMITIVE_BUFFER {PRIMITIVE primitives[MAX_PRIMITIVES]; }; // Primitive data
layout(buffer_reference, scalar) buffer AABB_BUFFER {AABB aabbs[MAX_PRIMITIVES]; }; // Positions of a primitive
layout(buffer_reference, scalar) buffer MATERIAL_BUFFER {MATERIAL materials[MAX_MATERIALS]; }; // Materials
layout(buffer_reference, scalar) buffer LIGHT_BUFFER {LIGHT lights[MAX_LIGHTS]; }; // Lights

layout(buffer_reference, scalar) buffer PREV_RESERVOIR_BUFFER {RESERVOIR reservoirs[MAX_RESERVOIRS]; }; // Reservoirs from the previous frame
layout(buffer_reference, scalar) buffer INT_RESERVOIR_BUFFER {RESERVOIR reservoirs[MAX_RESERVOIRS]; }; // Intermediate reservoirs
layout(buffer_reference, scalar) buffer RESERVOIR_BUFFER {RESERVOIR reservoirs[MAX_RESERVOIRS]; }; // Reservoirs from the current frame
layout(buffer_reference, scalar) buffer VELOCITY_BUFFER {VELOCITY velocities[MAX_RESERVOIRS]; }; // Velocities
layout(buffer_reference, scalar) buffer PREV_DI_BUFFER {DIRECT_ILLUMINATION_INFO di_info[MAX_RESERVOIRS]; }; // Direct illumination info
layout(buffer_reference, scalar) buffer DI_BUFFER {DIRECT_ILLUMINATION_INFO di_info[MAX_RESERVOIRS]; }; // Direct illumination info