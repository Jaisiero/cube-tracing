#pragma once
#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>
#include "shared.inl"

DAXA_DECL_PUSH_CONSTANT(PushConstant, p)

layout(location = 0) rayPayloadInEXT HIT_PAY_LOAD prd;
layout(location = 1) rayPayloadEXT bool is_shadowed;

layout(location = 3) callableDataEXT HIT_MAT_PAY_LOAD hit_call;
layout(location = 4) callableDataEXT HIT_SCATTER_PAY_LOAD call_scatter;