#pragma once
#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>
#include "defines.glsl"


PATH_RESERVOIR get_output_path_reservoir_by_index(daxa_u32 reservoir_index) {
    OUTPUT_PATH_RESERVOIR_BUFFER output_path_reservoir_buffer = OUTPUT_PATH_RESERVOIR_BUFFER(deref(p.restir_buffer).output_path_reservoir_address);
    return output_path_reservoir_buffer.path_reservoirs[reservoir_index];
}

void set_output_path_reservoir_by_index(daxa_u32 reservoir_index, PATH_RESERVOIR reservoir) {
    OUTPUT_PATH_RESERVOIR_BUFFER output_path_reservoir_buffer = OUTPUT_PATH_RESERVOIR_BUFFER(deref(p.restir_buffer).output_path_reservoir_address);
    output_path_reservoir_buffer.path_reservoirs[reservoir_index] = reservoir;
}

PATH_RESERVOIR get_temporal_path_reservoir_by_index(daxa_u32 reservoir_index) {
    TEMPORAL_PATH_RESERVOIR_BUFFER temporal_path_reservoir_buffer = TEMPORAL_PATH_RESERVOIR_BUFFER(deref(p.restir_buffer).temporal_path_reservoir_address);
    return temporal_path_reservoir_buffer.path_reservoirs[reservoir_index];
}

void set_temporal_path_reservoir_by_index(daxa_u32 reservoir_index, PATH_RESERVOIR reservoir) {
    TEMPORAL_PATH_RESERVOIR_BUFFER temporal_path_reservoir_buffer = TEMPORAL_PATH_RESERVOIR_BUFFER(deref(p.restir_buffer).temporal_path_reservoir_address);
    temporal_path_reservoir_buffer.path_reservoirs[reservoir_index] = reservoir;
}

PIXEL_RECONNECTION_DATA get_reconnection_data_from_current_frame(daxa_u32 pixel_index) {
    PIXEL_RECONNECTION_DATA_BUFFER reconnection_data_buffer = PIXEL_RECONNECTION_DATA_BUFFER(deref(p.restir_buffer).pixel_reconnection_data_address);
    return reconnection_data_buffer.reconnections[pixel_index];
}

void set_reconnection_data_from_current_frame(daxa_u32 pixel_index, PIXEL_RECONNECTION_DATA reconnection_info) {
    PIXEL_RECONNECTION_DATA_BUFFER reconnection_data_buffer = PIXEL_RECONNECTION_DATA_BUFFER(deref(p.restir_buffer).pixel_reconnection_data_address);
    reconnection_data_buffer.reconnections[pixel_index] = reconnection_info;
}

// maximum length: 15
void path_reservoir_insert_path_length(inout PATH_RESERVOIR reservoir, daxa_i32 path_length)
{
    reservoir.path_flags &= ~0xF;
    reservoir.path_flags |= (path_length & 0xF);
}

// maximum length: 15
void path_reservoir_insert_rc_vertex_length(inout PATH_RESERVOIR reservoir, daxa_i32 rc_vertex_length)
{
    reservoir.path_flags &= ~0xF0;
    reservoir.path_flags |= (rc_vertex_length & 0xF) << 4;
}

void path_reservoir_insert_last_vertex_nee(inout PATH_RESERVOIR reservoir, daxa_b32 last_vertex_nee)
{
    reservoir.path_flags &= ~0x10000;
    reservoir.path_flags |= (int(last_vertex_nee) & 1) << 16;
}

void path_reservoir_insert_is_specular_bounce(inout PATH_RESERVOIR reservoir, daxa_b32 is_specular_bounce, daxa_b32 before_rc_vertex)
{
    reservoir.path_flags &= (before_rc_vertex ? ~(0x4000000) : ~(0x8000000));
    if (is_specular_bounce) reservoir.path_flags |= 1 << (before_rc_vertex ? 26 : 27);
}

void path_reservoir_insert_light_type(inout PATH_RESERVOIR reservoir, daxa_u32 light_type)
{
    reservoir.path_flags &= ~0xc0000;
    reservoir.path_flags |= ((daxa_i32(light_type) & 3) << 18);
}


void path_reservoir_initialise(inout PATH_RESERVOIR reservoir)
{
  reservoir.M = 0.0;
  reservoir.weight = 0.0;
  reservoir.path_flags = 0;
  path_reservoir_insert_rc_vertex_length(reservoir, MAX_DEPTH);
  reservoir.rc_random_seed = 0;
  reservoir.F = daxa_f32vec3(0.0);
  reservoir.light_pdf = 0.0;
  reservoir.cached_jacobian = daxa_f32vec3(0.0);
  reservoir.init_random_seed = 0;
  reservoir.rc_vertex_hit = INSTANCE_HIT(MAX_INSTANCES-1, MAX_PRIMITIVES-1);
  reservoir.rc_vertex_wi[0] = daxa_f32vec3(0.0);
  reservoir.rc_vertex_irradiance[0] = daxa_f32vec3(0.0);
}

float to_scalar(daxa_f32vec3 color)
{
  return dot(color, daxa_f32vec3(0.299, 0.587, 0.114)); // luminance
}

daxa_b32 path_reservoir_update(inout PATH_RESERVOIR reservoir, daxa_f32vec3 in_F, daxa_f32 p, inout daxa_u32 seed)
{
  reservoir.M += 1.0;

  daxa_f32 w = to_scalar(in_F) / p;

  if (isnan(w) || w == 0.f) return false;
  
  reservoir.weight += w;

  if (rnd(seed) * reservoir.weight <= w)
  {
    reservoir.F = in_F;
    return true;
  }

  return false;
}

// daxa_u32 get_reservoir_light_index(in RESERVOIR reservoir)
// {
//   return reservoir.Y;
// }

// daxa_b32 is_reservoir_valid(in RESERVOIR reservoir)
// {
//   return reservoir.M > 0.0;
// }
