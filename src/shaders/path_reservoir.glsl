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

RECONNECTION_DATA get_reconnection_data_from_current_frame(daxa_u32 pixel_index, daxa_u32 slot) {
    PIXEL_RECONNECTION_DATA_BUFFER reconnection_data_buffer = PIXEL_RECONNECTION_DATA_BUFFER(deref(p.restir_buffer).pixel_reconnection_data_address);
    return reconnection_data_buffer.reconnections[pixel_index].data[slot];
}

void set_reconnection_data_from_current_frame(daxa_u32 pixel_index, daxa_u32 slot, RECONNECTION_DATA reconnection_info) {
    PIXEL_RECONNECTION_DATA_BUFFER reconnection_data_buffer = PIXEL_RECONNECTION_DATA_BUFFER(deref(p.restir_buffer).pixel_reconnection_data_address);
    reconnection_data_buffer.reconnections[pixel_index].data[slot] = reconnection_info;
}

// maximum length: 15
void path_reservoir_insert_path_length(inout PATH_RESERVOIR reservoir, daxa_i32 path_length)
{
    reservoir.path_flags &= ~0xF;
    reservoir.path_flags |= (path_length & 0xF);
}

daxa_u32 path_reservoir_get_path_length(daxa_i32 path_flags)
{
    return path_flags & 0xF;
}

// maximum length: 15
void path_reservoir_insert_rc_vertex_length(inout PATH_RESERVOIR reservoir, daxa_i32 rc_vertex_length)
{
    reservoir.path_flags &= ~0xF0;
    reservoir.path_flags |= (rc_vertex_length & 0xF) << 4;
}

daxa_u32 path_reservoir_get_reconnection_length(daxa_i32 path_flags)
{
    return (path_flags >> 4) & 0xF;
}


void path_reservoir_insert_is_delta_event(inout PATH_RESERVOIR reservoir, daxa_b32 is_delta, daxa_b32 before_rc_vertex)
{
    reservoir.path_flags &= (before_rc_vertex ? ~(0x100) : ~(0x200));
    if (is_delta) reservoir.path_flags |= 1 << (before_rc_vertex ? 20 : 21);
}

void path_reservoir_insert_is_transmission_event(inout PATH_RESERVOIR reservoir, daxa_b32 is_transmission, daxa_b32 before_rc_vertex)
{
    reservoir.path_flags &= (before_rc_vertex ? ~(0x400) : ~(0x800));
    if (is_transmission) reservoir.path_flags |= 1 << (before_rc_vertex ? 22 : 23);
}


void path_reservoir_insert_last_vertex_nee(inout PATH_RESERVOIR reservoir, daxa_b32 last_vertex_nee)
{
    reservoir.path_flags &= ~0x10000;
    reservoir.path_flags |= (int(last_vertex_nee) & 1) << 16;
}

daxa_b32 path_reservoir_last_vertex_NEE(daxa_u32 path_flags)
{
    return daxa_b32((path_flags >> 16) & 1);
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

void path_init_from_hit_info(inout PATH_RESERVOIR reservoir, INSTANCE_HIT hit)
{
    reservoir.rc_vertex_hit = hit;
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

daxa_f32 path_F_to_scalar(daxa_f32vec3 color)
{
  return dot(color, daxa_f32vec3(0.299, 0.587, 0.114)); // luminance
}

// Credits: falcor
/** Returns a relative luminance of an input linear RGB color in the ITU-R BT.709 color space
    \param RGBColor linear HDR RGB color in the ITU-R BT.709 color space
*/
daxa_f32 path_luminance(daxa_f32vec3 rgb)
{
    return dot(rgb, daxa_f32vec3(0.2126f, 0.7152f, 0.0722f));
}


daxa_b32 path_reservoir_update(inout PATH_RESERVOIR reservoir, daxa_f32vec3 in_F, daxa_f32 p, inout daxa_u32 seed)
{
  reservoir.M += 1.0;

  daxa_f32 w = path_F_to_scalar(in_F) / p;

  if (isnan(w) || w == 0.f) return false;
  
  reservoir.weight += w;

  if (rnd(seed) * reservoir.weight <= w)
  {
    reservoir.F = in_F;
    return true;
  }

  return false;
}

daxa_b32 path_reservoir_merge(inout PATH_RESERVOIR reservoir, daxa_f32vec3 in_F, daxa_f32 in_jacobian, PATH_RESERVOIR in_reservoir,  inout daxa_u32 seed, daxa_f32 mis_weight, daxa_b32 force_add)
{
    daxa_f32 w = path_F_to_scalar(in_F) * in_jacobian * in_reservoir.M * in_reservoir.weight * mis_weight;

    reservoir.M += in_reservoir.M;

    if (isnan(w) || w == 0.f)
        return false;

    reservoir.weight += w;

    // Accept?
    if (force_add || urnd(seed) * reservoir.weight <= w)
    {
        reservoir.path_flags = in_reservoir.path_flags;
        reservoir.rc_random_seed = in_reservoir.rc_random_seed;
        reservoir.init_random_seed = in_reservoir.init_random_seed;
        reservoir.cached_jacobian = in_reservoir.cached_jacobian;
        reservoir.light_pdf = in_reservoir.light_pdf;
        reservoir.rc_vertex_wi[0] = in_reservoir.rc_vertex_wi[0];
        reservoir.rc_vertex_hit = in_reservoir.rc_vertex_hit;
        reservoir.rc_vertex_irradiance[0] = in_reservoir.rc_vertex_irradiance[0];
        reservoir.F = in_F;
        return true;
    }

    return false;
}

daxa_b32 path_reservoir_merge_with_resampling_MIS(inout PATH_RESERVOIR reservoir, daxa_f32vec3 in_F, daxa_f32 in_jacobian, PATH_RESERVOIR in_reservoir, inout daxa_u32 seed, daxa_f32 mis_weight, daxa_b32 force_add)
{
    daxa_f32 w = path_F_to_scalar(in_F) * in_jacobian * in_reservoir.weight * mis_weight;

    reservoir.M += in_reservoir.M;

    if (isnan(w) || w == 0.f)
        return false;

    reservoir.weight += w;

    // Accept?
    if (force_add || urnd(seed) * reservoir.weight <= w)
    {
        reservoir.path_flags = in_reservoir.path_flags;
        reservoir.rc_random_seed = in_reservoir.rc_random_seed;
        reservoir.init_random_seed = in_reservoir.init_random_seed;
        reservoir.cached_jacobian = in_reservoir.cached_jacobian;
        reservoir.light_pdf = in_reservoir.light_pdf;
        reservoir.rc_vertex_wi[0] = in_reservoir.rc_vertex_wi[0];
        reservoir.rc_vertex_hit = in_reservoir.rc_vertex_hit;
        reservoir.rc_vertex_irradiance[0] = in_reservoir.rc_vertex_irradiance[0];
        reservoir.F = in_F;
        return true;
    }

    return false;
}

void path_reservoir_finalize_RIS(inout PATH_RESERVOIR reservoir) 
{
    daxa_f32 p_hat = path_F_to_scalar(reservoir.F);
    if (p_hat == 0.f || reservoir.M == 0.f) reservoir.weight = 0.f;
    else reservoir.weight = reservoir.weight / (p_hat * reservoir.M);
}


void path_reservoir_finalize_GRIS(inout PATH_RESERVOIR reservoir) 
{
    daxa_f32 p_hat = path_F_to_scalar(reservoir.F);
    if (p_hat == 0.f) reservoir.weight = 0.f;
    else reservoir.weight = reservoir.weight / p_hat;
}