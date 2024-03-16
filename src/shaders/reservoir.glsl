#pragma once
#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include "defines.glsl"
#include "primitives.glsl"
#include "prng.glsl"
#include <daxa/daxa.inl>

#include "direct_light_info.glsl"
#include "light.glsl"
#include "motion_vectors.glsl"

#if SER == 1
#extension GL_NV_shader_invocation_reorder : enable
#endif

void initialise_reservoir(inout RESERVOIR reservoir) {
  reservoir.W_y = 0.0;
  reservoir.seed = 0;
  reservoir.W_sum = 0.0;
  reservoir.M = 0.0;
  reservoir.Y = MAX_LIGHTS;
  reservoir.F = daxa_f32vec3(0.0);
}

daxa_b32 is_weight_invalid(daxa_f32 w) {
  return w < 0.0 || isnan(w) || isinf(w);
}

daxa_b32 update_reservoir(inout RESERVOIR reservoir, daxa_u32 X,
                          daxa_u32 random_seed, daxa_f32vec3 F, daxa_f32 w,
                          daxa_f32 c, inout daxa_u32 seed) {
  reservoir.M += c;

  if (isnan(w) || w == 0.f)
    return false;

  reservoir.W_sum += w;

  if (rnd(seed) < (w / reservoir.W_sum)) {
    reservoir.Y = X;
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
    float denominator = length(reservoir.F) * normalizationDenominator;

    reservoir.W_sum = (denominator == 0.0) ? 0.0 : (reservoir.W_sum * normalizationNumerator) / denominator;
}

daxa_u32 get_reservoir_light_index(in RESERVOIR reservoir) {
  return reservoir.Y;
}

daxa_u32 get_reservoir_seed(in RESERVOIR reservoir) { return reservoir.seed; }

daxa_b32 is_reservoir_valid(in RESERVOIR reservoir) {
  return reservoir.M > 0.0;
}

daxa_b32 reservoir_check_visibility(inout RESERVOIR reservoir, Ray ray,
                                    HIT_INFO_INPUT hit, MATERIAL mat,
                                    daxa_u32 light_count) {
  if (is_reservoir_valid(reservoir)) {

    daxa_f32vec3 l_pos;
    daxa_f32vec3 l_nor;
    daxa_f32vec3 Le = vec3(0.0);
    daxa_f32 G;
    daxa_f32 l_pdf = 1.0 / light_count;

    LIGHT light =
        get_light_from_light_index(get_reservoir_light_index(reservoir));
    daxa_u32 seed = reservoir.seed;
    return sample_lights(hit, light, l_pdf, l_pos, l_nor, Le, seed, G, false,
                         true);
  }

  return false;
}


daxa_f32vec3 reservoir_get_radiance(RESERVOIR reservoir, Ray ray,
                                    HIT_INFO_INPUT hit, MATERIAL mat,
                                    daxa_u32 light_count) {
  daxa_f32vec3 F = vec3(0.0);
                                      
  if (is_reservoir_valid(reservoir)) {
    LIGHT light = get_light_from_light_index(get_reservoir_light_index(reservoir));

    daxa_f32 pdf = 1.0 / light_count;
    daxa_f32 current_pdf = 1.0;
    daxa_f32vec3 F =
        calculate_sampled_light(ray, hit, mat, light_count, light, pdf,
                                current_pdf, reservoir.seed, false, false, true);
  }

  return F;
}

void reservoir_visibility_pass(inout RESERVOIR reservoir, Ray ray,
                               HIT_INFO_INPUT hit, MATERIAL mat,
                               daxa_u32 light_count) {
  // TODO: Check visibility here
  reservoir.W_y =
      reservoir_check_visibility(reservoir, ray, hit, mat, light_count)
          ? (reservoir.W_sum / (reservoir.M * luminance(reservoir.F)))
          : 0.0;

  reservoir.W_sum = reservoir.W_y > 0.f ? reservoir.W_sum : 0.0;
}

void calculate_reservoir_aggregation(inout RESERVOIR reservoir,
                                     RESERVOIR aggregation_reservoir,
                                     inout daxa_u32 seed) {

  if (is_reservoir_valid(aggregation_reservoir)) {

    // add sample from previous frame
    update_reservoir(
        reservoir, get_reservoir_light_index(aggregation_reservoir),
        get_reservoir_seed(aggregation_reservoir), aggregation_reservoir.F,
        luminance(aggregation_reservoir.F) * aggregation_reservoir.W_y *
            aggregation_reservoir.M,
        aggregation_reservoir.M, seed);

    reservoir.W_y = (reservoir.W_sum / (reservoir.M * luminance(reservoir.F)));
  }
}

RESERVOIR RIS(daxa_u32 light_count, daxa_u32 object_count, daxa_f32 confidence,
              Ray ray, inout HIT_INFO_INPUT hit, MATERIAL mat, daxa_f32 pdf,
              inout daxa_f32 p_hat, inout daxa_u32 seed, out INTERSECT i) {
  RESERVOIR reservoir;
  initialise_reservoir(reservoir);

  confidence = clamp(confidence, 0.0, 1.0);

  daxa_u32 num_of_samples =
      max(daxa_u32(min(MAX_RIS_SAMPLE_COUNT * (1.0 - confidence), light_count)),
          MIN_RIS_SAMPLE_COUNT);

  for (daxa_u32 l = 0; l < num_of_samples; l++) {
    daxa_u32 light_index =
        min(urnd_interval(seed, 0, light_count), light_count - 1);

    LIGHT light = get_light_from_light_index(light_index);

    daxa_f32 current_pdf = 1.0;
    daxa_u32 current_seed = seed;
    daxa_f32vec3 F =
        calculate_sampled_light(ray, hit, mat, light_count, light, pdf,
                                current_pdf, seed, true, false, false);

    daxa_f32 w = luminance(F) / current_pdf;
    update_reservoir(reservoir, light_index, current_seed, F, w, 1.0f, seed);
  }

  reservoir_visibility_pass(reservoir, ray, hit, mat, light_count);

  return reservoir;
}

RESERVOIR FIRST_GATHER(daxa_u32 light_count, daxa_u32 object_count,
                       daxa_u32 screen_pos, daxa_f32 confidence_index, Ray ray,
                       inout HIT_INFO_INPUT hit, MATERIAL mat,
                       inout daxa_f32 p_hat, inout daxa_u32 seed, INTERSECT i) {
  // PDF for lights
  daxa_f32 pdf = 1.0 / light_count;

  RESERVOIR reservoir = RIS(light_count, object_count, confidence_index, ray,
                            hit, mat, pdf, p_hat, seed, i);

  return reservoir;
}

RESERVOIR GATHER_TEMPORAL_RESERVOIR(daxa_u32vec2 predicted_coord,
                                    daxa_u32vec2 rt_size, HIT_INFO_INPUT hit) {
  RESERVOIR reservoir_previous;
  initialise_reservoir(reservoir_previous);

  daxa_u32 prev_predicted_index =
      predicted_coord.x + predicted_coord.y * rt_size.x;

  if(prev_predicted_index >= rt_size.x * rt_size.y) {
    return reservoir_previous;
  }

  // Temporal reuse
  {
    DIRECT_ILLUMINATION_INFO di_info_previous =
        get_di_from_previous_frame(prev_predicted_index);

    // Normal from previous frame
    daxa_f32vec3 normal_previous = di_info_previous.normal.xyz;

    // Depth from previous frame
    daxa_f32 depth_previous = di_info_previous.distance;

    // some simple rejection based on normals' divergence, can be improved
    daxa_b32 valid_history = dot(normal_previous, hit.world_nrm) >= 0.99 &&
                             //  di_info_previous.mat_index == hit.mat_idx; //&&
                             di_info_previous.instance_hit.instance_id ==
                                 hit.instance_hit.instance_id &&
                             di_info_previous.instance_hit.primitive_id ==
                                 hit.instance_hit.primitive_id;

    if (valid_history) {
      // Reservoir from previous frame
      reservoir_previous =
          get_reservoir_from_previous_frame_by_index(prev_predicted_index);
    }
  }

  return reservoir_previous;
}

// void TEMPORAL_REUSE(inout RESERVOIR reservoir, RESERVOIR reservoir_previous,
//                     daxa_u32vec2 predicted_coord, daxa_u32vec2 rt_size, Ray ray,
//                     inout HIT_INFO_INPUT hit, MATERIAL mat,
//                     daxa_u32 light_count, inout daxa_u32 seed) {

//   const daxa_f32 prevM = reservoir_previous.M;
//   const daxa_f32 newM = reservoir.M + prevM;

//   if (reservoir.W_sum > 0.f) {
//     float targetLumAtPrev = 0.0f;

//     if (luminance(reservoir.F) > 1e-6) {

//       daxa_u32 prev_predicted_index =
//         predicted_coord.x + predicted_coord.y * rt_size.x;

//       // compute target at current pixel with previous reservoir's sample
//       DIRECT_ILLUMINATION_INFO di_info_previous =
//           get_di_from_previous_frame(prev_predicted_index);

//       HIT_INFO_INPUT prev_hit = HIT_INFO_INPUT(di_info_previous.position,
//                                                 di_info_previous.normal,
//                                                 di_info_previous.distance,
//                                                 daxa_f32vec3(0.0),
//                                                 di_info_previous.instance_hit,
//                                                 di_info_previous.mat_index);

//       prev_hit.world_hit = compute_ray_origin(prev_hit.world_hit, prev_hit.world_nrm);
//       prev_hit.world_hit = compute_ray_origin(prev_hit.world_hit, prev_hit.world_nrm);
      
//       MATERIAL prev_mat = get_material_from_material_index(di_info_previous.mat_index);

//       Ray prev_ray = Ray(di_info_previous.ray_origin, normalize(prev_hit.world_hit - di_info_previous.ray_origin));

//       // calculate target at previous pixel with current reservoir's sample
//       targetLumAtPrev = luminance(reservoir_get_radiance(reservoir, prev_ray, prev_hit, prev_mat,
//                                                light_count));
//     }

//     const float p_curr = reservoir.M * luminance(reservoir.F);
//     const float m_curr = p_curr / max(p_curr + prevM * targetLumAtPrev, 1e-6);
//     reservoir.W_sum *= m_curr;
//   }

//   if (is_reservoir_valid(reservoir_previous)) {
//     daxa_f32vec3 currTarget = reservoir_get_radiance(reservoir_previous, ray, hit, mat,
//                                                      light_count);
//     const float targetLumAtCurr = luminance(currTarget);

//     // w_prev becomes zero; then only M needs to be updated, which is done at
//     // the end anyway
//     if (targetLumAtCurr > 1e-6) {
//       const float w_sum_prev = reservoir_previous.W_sum;
//       const float targetLumAtPrev = reservoir_previous.W_y > 0 ? w_sum_prev / reservoir_previous.W_y : 0;
//       // balance heuristic
//       const float p_prev = reservoir_previous.M * targetLumAtPrev;
//       const float m_prev = p_prev / max(p_prev + reservoir.M * targetLumAtCurr, 1e-6);
//       const float w_prev = m_prev * targetLumAtCurr * reservoir_previous.W_y;

//       update_reservoir(reservoir, get_reservoir_light_index(reservoir_previous),
//                        get_reservoir_seed(reservoir_previous), currTarget, w_prev,
//                        1.f, seed);
//     }
//   }

//   float targetLum = luminance(reservoir.F);
//   reservoir.W_y = targetLum > 0.0 ? reservoir.W_sum / targetLum : 0.0;
//   reservoir.M = newM;
// }

void TEMPORAL_REUSE(inout RESERVOIR reservoir, RESERVOIR reservoir_previous,
                    daxa_u32vec2 predicted_coord, daxa_u32vec2 rt_size, Ray ray,
                    inout HIT_INFO_INPUT hit, MATERIAL mat,
                    daxa_u32 light_count, inout daxa_u32 seed) {

  RESERVOIR temporal_reservoir;
  initialise_reservoir(temporal_reservoir);

  // add current reservoir sample
  calculate_reservoir_aggregation(temporal_reservoir, reservoir, seed);

  // NOTE: restrict influence from past samples.

  if(reservoir_previous.M > MAX_INFLUENCE_FROM_THE_PAST_THRESHOLD * reservoir.M) {
    reservoir_previous.M = MAX_INFLUENCE_FROM_THE_PAST_THRESHOLD * reservoir.M;
    reservoir_previous.W_sum = MAX_INFLUENCE_FROM_THE_PAST_THRESHOLD * reservoir.W_sum / temporal_reservoir.W_sum;
  }

  // Check visibility
  reservoir_visibility_pass(reservoir_previous, ray, hit, mat, light_count);

  // // add sample from previous frame
  calculate_reservoir_aggregation(temporal_reservoir, reservoir_previous, seed);

  // reservoir_finalize_resampling(temporal_reservoir, 1.0f, temporal_reservoir.M);

  reservoir = temporal_reservoir;
}

void SPATIAL_REUSE(inout RESERVOIR reservoir, daxa_f32 confidence,
                   daxa_u32vec2 predicted_coord, daxa_u32vec2 rt_size, Ray ray,
                   inout HIT_INFO_INPUT hit, daxa_u32 current_mat_index,
                   MATERIAL mat, daxa_u32 light_count, daxa_f32 pdf,
                   inout daxa_u32 seed, const daxa_f32 min_radius,
                   const daxa_f32 max_radius) {
  RESERVOIR spatial_reservoir;
  initialise_reservoir(spatial_reservoir);

  confidence = clamp(confidence, 0.0, 1.0);

  // add previous samples
  calculate_reservoir_aggregation(spatial_reservoir, reservoir, seed);

  RESERVOIR neighbor_reservoir;

  if (spatial_reservoir.W_y == 0) {
    confidence = 0.0;
  }

  // daxa_f32 spatial_influence_threshold = max(1.0,
  // (INFLUENCE_FROM_THE_PAST_THRESHOLD) / NUM_OF_NEIGHBORS);

  // Heuristically determine the radius of the spatial reuse based on distance
  // to the camera
  daxa_f32 spatial_heuristic_radius =
      mix(max_radius, min_radius,
          clamp(hit.distance / MAX_DISTANCE_TO_HIT, 0.0, 1.0));

  // Heuristically determine the number of neighbors based on the confidence
  // index
  daxa_u32 spatial_heuristic_num_of_neighbors = daxa_u32(mix(
      MIN_NUM_OF_NEIGHBORS, MAX_NUM_OF_NEIGHBORS, clamp(confidence, 0.0, 1.0)));

  for (daxa_u32 i = 0; i < spatial_heuristic_num_of_neighbors; i++) {
    // Random offset
    daxa_f32vec2 offset = 2.0 * daxa_f32vec2(rnd(seed), rnd(seed)) - 1;

    // Scale offset
    offset.x =
        predicted_coord.x + daxa_i32(offset.x * spatial_heuristic_radius);
    offset.y =
        predicted_coord.y + daxa_i32(offset.y * spatial_heuristic_radius);

    // Clamp offset
    offset.x = min(rt_size.x - 1, max(0, min(rt_size.x - 1, offset.x)));
    offset.y = min(rt_size.y - 1, max(0, min(rt_size.y - 1, offset.y)));

    if (offset.x == predicted_coord.x && offset.y == predicted_coord.y) {
      continue;
    }

    // Convert offset to u32
    daxa_u32vec2 offset_u32 = daxa_u32vec2(offset);

    // Convert offset to linear
    daxa_u32 offset_u32_linear = offset_u32.y * rt_size.x + offset_u32.x;

    DIRECT_ILLUMINATION_INFO neighbor_di_info =
        get_di_from_current_frame(offset_u32_linear);

    daxa_f32 neighbor_hit_dist = neighbor_di_info.distance;

    daxa_u32 neighbor_mat_index = neighbor_di_info.mat_index;

    // TODO: Adjust dist threshold dynamically
    if (neighbor_mat_index != current_mat_index ||
        (dot(hit.world_nrm, neighbor_di_info.normal.xyz) < 0.906) ||
        (abs(hit.distance - neighbor_hit_dist) > 0.1 * hit.distance)) {
      // skip this neighbour sample if not suitable
      continue;
    }

    neighbor_reservoir =
        get_reservoir_from_intermediate_frame_by_index(offset_u32_linear);

    reservoir_visibility_pass(neighbor_reservoir, ray, hit, mat, light_count);

    calculate_reservoir_aggregation(spatial_reservoir, neighbor_reservoir,
                                    seed);
  }

  reservoir = spatial_reservoir;
}