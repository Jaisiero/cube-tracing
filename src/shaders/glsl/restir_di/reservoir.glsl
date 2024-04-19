#pragma once
#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>
#include "defines.glsl"
#include "primitives.glsl"
#include "prng.glsl"

#include "direct_light_info.glsl"
#include "light.glsl"

#if SER == 1
#extension GL_NV_shader_invocation_reorder : enable
#endif


void initialise_reservoir(inout RESERVOIR reservoir) {
  reservoir.W_y = 0.0;
  reservoir.seed = 0;
  reservoir.W_sum = 0.0;
  reservoir.M = 0.0;
  reservoir.Y = -1;
  reservoir.l_type = GEOMETRY_LIGHT_NONE;
  reservoir.F = daxa_f32vec3(0.0);
}

daxa_b32 is_weight_invalid(daxa_f32 w) {
  return w < 0.0 || isnan(w) || isinf(w);
}

daxa_b32 update_reservoir(inout RESERVOIR reservoir, daxa_u32 X, daxa_u32 l_type,
                          daxa_u32 random_seed, daxa_f32vec3 F, daxa_f32 w,
                          daxa_f32 c, inout daxa_u32 seed) {

  if (is_weight_invalid(w))
    return false;

  reservoir.M += c;
  reservoir.W_sum += w;

  if (rnd(seed) < (w / reservoir.W_sum)) {
    reservoir.Y = X;
    reservoir.l_type = l_type;
    reservoir.seed = random_seed;
    reservoir.F = F;
    return true;
  }

  return false;
}


// Performs normalization of the reservoir after streaming. Equation (6) from the ReSTIR paper.
void reservoir_finalize_resampling(
    inout RESERVOIR reservoir,
    float normalizationNumerator,
    float normalizationDenominator)
{
    float denominator = luminance(reservoir.F) * normalizationDenominator;

    reservoir.W_sum = (denominator == 0.0) ? 0.0 : (reservoir.W_sum * normalizationNumerator) / denominator;
}

daxa_u32 get_reservoir_light_index(in RESERVOIR reservoir) {
  return reservoir.Y;
}

daxa_u32 get_reservoir_seed(in RESERVOIR reservoir) { return reservoir.seed; }

daxa_u32 get_reservoir_type(in RESERVOIR reservoir) { return reservoir.l_type; }

daxa_b32 is_reservoir_valid(in RESERVOIR reservoir) {
  return reservoir.M > 0.0 && reservoir.Y != -1 && reservoir.l_type != GEOMETRY_LIGHT_NONE;
}

daxa_b32 reservoir_check_visibility(inout RESERVOIR reservoir, Ray ray,
                                    HIT_INFO_INPUT hit, MATERIAL mat,
                                    daxa_b32 previous_frame) {
  if (is_reservoir_valid(reservoir)) {

    daxa_f32vec3 l_pos;
    daxa_f32vec3 l_nor;
    daxa_f32vec3 Le = vec3(0.0);
    daxa_f32 G;
    daxa_f32 l_pdf = 1.0;

    LIGHT light = light_get_by_type(get_reservoir_type(reservoir),
                                    get_reservoir_light_index(reservoir));

    daxa_u32 seed = reservoir.seed;
    return sample_lights(hit, light, l_pdf, l_pos, l_nor, Le, seed, G,
                         previous_frame, false, true);
  }

  return false;
}

daxa_f32vec3 reservoir_get_radiance(RESERVOIR reservoir, Ray ray,
                                    HIT_INFO_INPUT hit, MATERIAL mat, daxa_b32 previous_frame) {     
  if (is_reservoir_valid(reservoir)) {
    LIGHT light = light_get_by_type(get_reservoir_type(reservoir), get_reservoir_light_index(reservoir));

    daxa_f32 pdf = 1.0;
    daxa_f32 current_pdf = 1.0;
    daxa_f32 G;
    return calculate_sampled_light(ray, hit, mat, 1, light, pdf, current_pdf, G,
                                   reservoir.seed, previous_frame, false, false,
                                   true);
  }

  return daxa_f32vec3(0.0);
}

void reservoir_visibility_pass(inout RESERVOIR reservoir, Ray ray,
                               HIT_INFO_INPUT hit, MATERIAL mat, daxa_b32 previous_frame) {

  daxa_b32 visibility = reservoir_check_visibility(reservoir, ray, hit, mat, previous_frame);

  // TODO: Check visibility here
  reservoir.W_y =
      visibility
          ? (reservoir.W_sum / (luminance(reservoir.F)))
          : 0.0;

  reservoir.F *= visibility ? 1.0 : 0.0;
}