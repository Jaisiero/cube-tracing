#pragma once
#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>
#include "defines.glsl"
#include "reservoir.glsl"

struct PAIRWISE_MIS {
  RESERVOIR reservoir;
  daxa_f32 m_c; // canonical mis confidence weight
  daxa_f32 M_s; // streamed sample count
  daxa_u32 k;   // number of strategies
};

void pairwise_init(inout PAIRWISE_MIS mis, daxa_u32 num_strategies,
                   RESERVOIR reservoir) {
  initialise_reservoir(mis.reservoir);
  mis.m_c = 1.0f;
  mis.M_s = reservoir.M;
  mis.k = num_strategies;
}

daxa_f32 pairwise_compute_m_i(daxa_u32 number_of_strategies, RESERVOIR canonical_reservoir,
                              RESERVOIR input_reservoir, daxa_f32 target_lum) {

  const daxa_f32 p_i_y_i = luminance(input_reservoir.F); // p_i_y_i
  const daxa_f32 p_c_y_i = target_lum; // p_c_y_i

  daxa_f32 m_i = input_reservoir.M * p_i_y_i;                  // Ci * p_i_y_i
  daxa_f32 denominator = m_i + (canonical_reservoir.M / number_of_strategies) *
                                   p_c_y_i; // Ci * p_i_y_i + (Cc / k) * p_c_y_i
  m_i = denominator > 0.f
            ? m_i / denominator
            : 0.f; // Ci * p_i_y_i / (Ci * p_i_y_i + (Cc / k) * p_c_y_i)

  return m_i;
}

void pairwise_update_m_c(inout PAIRWISE_MIS mis, RESERVOIR canonical_reservoir,
                        RESERVOIR input_reservoir, daxa_f32vec3 input_target,
                        inout daxa_u32 seed) {
  const daxa_f32 p_i_y_c = luminance(input_target); // p_i_y_c
  const daxa_f32 p_c_y_c = luminance(canonical_reservoir.F); // p_c_y_c

  const daxa_f32 numerator = input_reservoir.M * p_i_y_c; // Cc * p_i_y_c
  const daxa_b32 denominator = (p_c_y_c + numerator) > 0.f;
  mis.m_c += denominator ? 1 - numerator / (numerator + (canonical_reservoir.M / mis.k) * p_c_y_c) : 1.f; // 1 - Cc * p_i_y_c / (Cc * p_i_y_c + (Cc / k) * p_c_y_c)
}



void pairwise_stream(inout PAIRWISE_MIS mis, RESERVOIR canonical_reservoir,
                     Ray canonical_ray, HIT_INFO_INPUT canonical_hit,
                     MATERIAL canonical_material, RESERVOIR input_reservoir,
                     Ray input_ray, HIT_INFO_INPUT input_hit,
                     MATERIAL input_material, inout daxa_u32 seed) {
  daxa_f32vec3 curr_target = daxa_f32vec3(0.0f);
  daxa_f32 m_i;

  // m_i
  if (is_reservoir_valid(input_reservoir)) {

    curr_target = reservoir_get_radiance(input_reservoir, canonical_ray,
                                         canonical_hit, canonical_material);

    const daxa_f32 target_lum = luminance(curr_target);
    m_i = pairwise_compute_m_i(mis.k, canonical_reservoir, input_reservoir,
                               target_lum);
  }

  daxa_f32vec3 input_target = daxa_f32vec3(0.0f);

  // m_c
  if (is_reservoir_valid(canonical_reservoir)) {
    input_target = reservoir_get_radiance(canonical_reservoir, input_ray,
                                         input_hit, input_material);
  }

  pairwise_update_m_c(mis, canonical_reservoir, input_reservoir, input_target, seed);

  if (is_reservoir_valid(input_reservoir)) {
    const daxa_f32 w_i = luminance(curr_target) * input_reservoir.W_y * m_i;

    update_reservoir(mis.reservoir,
                     get_reservoir_light_index(input_reservoir),
                     get_reservoir_type(input_reservoir),
                     get_reservoir_seed(input_reservoir),
                     curr_target, w_i, 1.0f, seed);
  }

  mis.M_s += input_reservoir.M;
}

void pairwise_end(inout PAIRWISE_MIS mis, RESERVOIR canonical_reservoir,
                  daxa_u32 seed) {

  const daxa_f32 w_c =
      luminance(canonical_reservoir.F) * canonical_reservoir.W_y * mis.m_c;

  update_reservoir(mis.reservoir,
                   get_reservoir_light_index(canonical_reservoir),
                   get_reservoir_type(canonical_reservoir),
                   get_reservoir_seed(canonical_reservoir),
                   canonical_reservoir.F, w_c, 1.f, seed);

  mis.reservoir.M = mis.M_s;
  const daxa_f32 target_lum = luminance(mis.reservoir.F);
  // defensive pairwise MIS
  mis.reservoir.W_y =
      target_lum > 0.f ? mis.reservoir.W_sum / (target_lum * (1 + mis.k)) : 0.f;
}