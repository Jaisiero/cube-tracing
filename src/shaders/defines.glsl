#pragma once
#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>
#include "shared.inl"

DAXA_DECL_PUSH_CONSTANT(PushConstant, p)

#if DAXA_SHADER_STAGE == DAXA_SHADER_STAGE_CLOSEST_HIT
layout(location = 0) rayPayloadInEXT HIT_PAY_LOAD prd;
layout(location = 1) rayPayloadEXT bool is_shadowed;
layout(location = 3) callableDataEXT HIT_MAT_PAY_LOAD hit_call;
layout(location = 4) callableDataEXT HIT_SCATTER_PAY_LOAD call_scatter;
#elif DAXA_SHADER_STAGE == DAXA_SHADER_STAGE_CALLABLE
layout(location = 4) callableDataInEXT HIT_SCATTER_PAY_LOAD call_scatter;
#endif

#define DEBUG_NORMALS_ON 0
#define LIGHT_SAMPLING_ON 1
#define RESERVOIR_ON 1
#define MIS_ON 0
#define INDIRECT_ILLUMINATION_ON 1
#define CALLABLE_ON 1
// #define DEBUG_NORMALS 1