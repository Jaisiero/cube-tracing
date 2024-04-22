#pragma once
#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>
#include "defines.glsl"


DIRECT_ILLUMINATION_INFO get_di_from_previous_frame(daxa_u32 di_index) {
    PREV_DI_BUFFER prev_di_buffer = PREV_DI_BUFFER(deref(p.restir_buffer).previous_di_address);
    return prev_di_buffer.di_info[di_index];
}

void set_di_from_previous_frame(daxa_u32 di_index, DIRECT_ILLUMINATION_INFO di_info) {
    PREV_DI_BUFFER prev_di_buffer = PREV_DI_BUFFER(deref(p.restir_buffer).previous_di_address);
    prev_di_buffer.di_info[di_index] = di_info;
}

void reset_di_from_previous_frame_distance(daxa_u32 di_index) {
    PREV_DI_BUFFER prev_di_buffer = PREV_DI_BUFFER(deref(p.restir_buffer).previous_di_address);
    prev_di_buffer.di_info[di_index].distance = 0.0;
}

DIRECT_ILLUMINATION_INFO get_di_from_current_frame(daxa_u32 di_index) {
    DI_BUFFER di_buffer = DI_BUFFER(deref(p.restir_buffer).di_address);
    return di_buffer.di_info[di_index];
}

void set_di_from_current_frame(daxa_u32 di_index, DIRECT_ILLUMINATION_INFO di_info) {
    DI_BUFFER di_buffer = DI_BUFFER(deref(p.restir_buffer).di_address);
    di_buffer.di_info[di_index] = di_info;
}

void set_di_seed_from_current_frame(daxa_u32 di_index, daxa_u32 seed) {
    DI_BUFFER di_buffer = DI_BUFFER(deref(p.restir_buffer).di_address);
    di_buffer.di_info[di_index].seed = seed;
}

RESERVOIR get_reservoir_from_previous_frame_by_index(daxa_u32 reservoir_index) {
    PREV_RESERVOIR_BUFFER prev_reservoir_buffer = PREV_RESERVOIR_BUFFER(deref(p.restir_buffer).previous_reservoir_address);
    return prev_reservoir_buffer.reservoirs[reservoir_index];
}

void set_reservoir_from_previous_frame_by_index(daxa_u32 reservoir_index, RESERVOIR reservoir) {
    PREV_RESERVOIR_BUFFER prev_reservoir_buffer = PREV_RESERVOIR_BUFFER(deref(p.restir_buffer).previous_reservoir_address);
    prev_reservoir_buffer.reservoirs[reservoir_index] = reservoir;
}

RESERVOIR get_reservoir_from_intermediate_frame_by_index(daxa_u32 reservoir_index) {
    INT_RESERVOIR_BUFFER int_reservoir_buffer = INT_RESERVOIR_BUFFER(deref(p.restir_buffer).intermediate_reservoir_address);
    return int_reservoir_buffer.reservoirs[reservoir_index];
}

void set_reservoir_from_intermediate_frame_by_index(daxa_u32 reservoir_index, RESERVOIR reservoir) {
    INT_RESERVOIR_BUFFER int_reservoir_buffer = INT_RESERVOIR_BUFFER(deref(p.restir_buffer).intermediate_reservoir_address);
    int_reservoir_buffer.reservoirs[reservoir_index] = reservoir;
}

RESERVOIR get_reservoir_from_current_frame_by_index(daxa_u32 reservoir_index) {
    RESERVOIR_BUFFER reservoir_buffer = RESERVOIR_BUFFER(deref(p.restir_buffer).reservoir_address);
    return reservoir_buffer.reservoirs[reservoir_index];
}

void set_reservoir_from_current_frame_by_index(daxa_u32 reservoir_index, RESERVOIR reservoir) {
    RESERVOIR_BUFFER reservoir_buffer = RESERVOIR_BUFFER(deref(p.restir_buffer).reservoir_address);
    reservoir_buffer.reservoirs[reservoir_index] = reservoir;
}