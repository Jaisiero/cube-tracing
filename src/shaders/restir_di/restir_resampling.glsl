#pragma once
#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>
#include "defines.glsl"
#include "primitives.glsl"
#include "prng.glsl"

#include "direct_light_info.glsl"
#include "light.glsl"
#include "motion_vectors.glsl"
#include "reservoir.glsl"
#include "pairwise_mis.glsl"

#if SER == 1
#extension GL_NV_shader_invocation_reorder : enable
#endif

RESERVOIR RIS(daxa_u32 active_features, LIGHT_CONFIG light_config, daxa_u32 object_count,
              daxa_f32 confidence, Ray ray, inout HIT_INFO_INPUT hit,
              MATERIAL mat, inout daxa_f32 p_hat, inout daxa_u32 seed,
              out INTERSECT i) {

  confidence = clamp(confidence, 0.0, 1.0);

  daxa_b32 point_light_active =
      (active_features & RIS_POINT_LIGHT_BIT) == RIS_POINT_LIGHT_BIT;
  daxa_b32 env_light_active =
      (active_features & RIS_ENV_LIGHT_BIT) == RIS_ENV_LIGHT_BIT;
  daxa_b32 cube_geometry_active =
      (active_features & RIS_CUBE_LIGHT_BIT) == RIS_CUBE_LIGHT_BIT;

  daxa_u32 point_light_count =
      point_light_active ? light_config.point_light_count : 0;

  daxa_u32 num_of_point_samples =
      max(daxa_u32(min(MAX_RIS_POINT_SAMPLE_COUNT * (1.0 - confidence),
                       point_light_count)),
          MIN_RIS_POINT_SAMPLE_COUNT);

  daxa_u32 env_light_count = env_light_active ? light_config.env_map_count : 0;

  daxa_u32 num_of_env_samples =
      max(daxa_u32(min(MAX_RIS_ENV_SAMPLE_COUNT * (1.0 - confidence),
                       env_light_count)),
          MIN_RIS_ENV_SAMPLE_COUNT);

  daxa_u32 cube_light_count =
      cube_geometry_active ? light_config.cube_light_count : 0;

  daxa_u32 num_of_cube_samples =
      max(daxa_u32(min(MAX_RIS_CUBE_SAMPLE_COUNT * (1.0 - confidence),
                       cube_light_count)),
          MIN_RIS_CUBE_SAMPLE_COUNT);

  daxa_u32 mis_samples =
      num_of_point_samples + num_of_env_samples + num_of_cube_samples;

  daxa_f32 mis_weight = 1.0 / mis_samples;

  RESERVOIR reservoir;
  initialise_reservoir(reservoir);
  // Point light sampling
  if(point_light_count > 0) {

    daxa_f32 pdf = 1.0 / point_light_count;

    for (daxa_u32 l = 0; l < num_of_point_samples; l++) {
      daxa_u32 light_index =
          min(urnd_interval(seed, 0, point_light_count), point_light_count - 1);

      LIGHT light = get_point_light_from_light_index(light_index);

      daxa_f32 current_pdf = 1.0;
      daxa_u32 current_seed = seed;
      daxa_f32vec3 F =
          calculate_sampled_light(ray, hit, mat, point_light_count, light, pdf,
                                  current_pdf, seed, true, false, false);

      daxa_f32 m_i = (1.0 / max(num_of_point_samples * current_pdf, 1e-6));

      daxa_f32 w_i = luminance(F) * m_i;
      update_reservoir(reservoir, light_index, GEOMETRY_LIGHT_POINT,
                       current_seed, F, w_i, 1.0f, seed);
    }

    // reservoir_finalize_resampling(reservoir, 1.0, mis_samples);
    // reservoir.M = 1;
  }

  RESERVOIR env_reservoir;
  initialise_reservoir(env_reservoir);
  // Env light sampling
  if(env_light_count > 0) {
    daxa_f32 pdf = 1.0 / env_light_count;

    for (daxa_u32 l = 0; l < num_of_env_samples; l++) {
      daxa_u32 light_index =
          min(urnd_interval(seed, 0, env_light_count), env_light_count - 1);

      LIGHT light = get_env_light_from_light_index(light_index);

      daxa_f32 current_pdf = 1.0;
      daxa_u32 current_seed = seed;
      daxa_f32vec3 F =
          calculate_sampled_light(ray, hit, mat, env_light_count, light, pdf,
                                  current_pdf, seed, true, false, false);

      daxa_f32 m_i = (1.0 / max(num_of_env_samples * current_pdf, 1e-6));

      daxa_f32 w_i = luminance(F) * m_i;
      update_reservoir(env_reservoir, light_index, GEOMETRY_LIGHT_ENV_MAP,
                       current_seed, F, w_i, 1.0f, seed);
    }
    // reservoir_finalize_resampling(env_reservoir, 1.0, mis_samples);
    // env_reservoir.M = 1;
    // reservoir_visibility_pass(env_reservoir, ray, hit, mat);

    update_reservoir(reservoir, get_reservoir_light_index(env_reservoir),
                    get_reservoir_type(env_reservoir),
                    get_reservoir_seed(env_reservoir), env_reservoir.F,
                    env_reservoir.W_sum, env_reservoir.M, seed);
  }

  RESERVOIR cube_reservoir;
  initialise_reservoir(cube_reservoir);
  // Env light sampling
  if(num_of_cube_samples > 0) {
    daxa_f32 pdf = 1.0 / cube_light_count;

    for (daxa_u32 l = 0; l < num_of_cube_samples; l++) {
      daxa_u32 light_index =
          min(urnd_interval(seed, 0, cube_light_count), cube_light_count - 1);

      LIGHT light = get_cube_light_from_light_index(light_index);

      daxa_f32 current_pdf = 1.0; // / cube_light_count;
      daxa_u32 current_seed = seed;
      daxa_f32vec3 F =
          calculate_sampled_light(ray, hit, mat, cube_light_count, light, pdf,
                                  current_pdf, seed, true, false, false);

      daxa_f32 m_i = (1.0 / max(num_of_cube_samples * current_pdf, 1e-6));

      daxa_f32 w_i = luminance(F) * m_i;
      update_reservoir(cube_reservoir, light_index, GEOMETRY_LIGHT_CUBE,
                       current_seed, F, w_i, 1.0f, seed);
    }
    // reservoir_finalize_resampling(cube_reservoir, 1.0, mis_samples);
    // cube_reservoir.M = 1;

    // reservoir_visibility_pass(cube_reservoir, ray, hit, mat);

    update_reservoir(reservoir, get_reservoir_light_index(cube_reservoir),
                    get_reservoir_type(cube_reservoir),
                    get_reservoir_seed(cube_reservoir), cube_reservoir.F,
                    cube_reservoir.W_sum, cube_reservoir.M, seed);
  }
  // reservoir_finalize_resampling(reservoir, 1.0, mis_samples);
  // reservoir.M = 1;

  // TODO: MIS weights for emissive geometry

  reservoir_visibility_pass(reservoir, ray, hit, mat);

  return reservoir;
}

RESERVOIR FIRST_GATHER(daxa_u32 active_features, LIGHT_CONFIG light_config, daxa_u32 object_count,
                       daxa_u32 screen_pos, daxa_f32 confidence_index, Ray ray,
                       inout HIT_INFO_INPUT hit, MATERIAL mat,
                       inout daxa_f32 p_hat, inout daxa_u32 seed, INTERSECT i) {               

  RESERVOIR reservoir = RIS(active_features, light_config, object_count, confidence_index, ray,
                            hit, mat, p_hat, seed, i);

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

  // // Temporal reuse
  // {
  //   DIRECT_ILLUMINATION_INFO di_info_previous =
  //       get_di_from_previous_frame(prev_predicted_index);

  //   // Normal from previous frame
  //   daxa_f32vec3 normal_previous = di_info_previous.normal.xyz;

  //   // Depth from previous frame
  //   daxa_f32 depth_previous = di_info_previous.distance;

  //   // some simple rejection based on normals' divergence, can be improved
  //   daxa_b32 valid_history = dot(normal_previous, hit.world_nrm) >= 0.99 &&
  //                            //  di_info_previous.mat_index == hit.mat_idx; //&&
  //                            di_info_previous.instance_hit.instance_id ==
  //                                hit.instance_hit.instance_id &&
  //                            di_info_previous.instance_hit.primitive_id ==
  //                                hit.instance_hit.primitive_id;

  //   if (valid_history) {
      // Reservoir from previous frame
      reservoir_previous =
          get_reservoir_from_previous_frame_by_index(prev_predicted_index);
  //   }
  // }

  return reservoir_previous;
}

void TEMPORAL_REUSE(inout RESERVOIR reservoir, RESERVOIR reservoir_previous,
                    daxa_u32vec2 predicted_coord, daxa_u32vec2 rt_size, Ray ray,
                    inout HIT_INFO_INPUT hit, MATERIAL mat,
                    daxa_u32 light_count, inout daxa_u32 seed) {

  reservoir_previous.M = min(reservoir_previous.M, MAX_INFLUENCE_FROM_THE_PAST_THRESHOLD * reservoir.M);

  const daxa_f32 prevM = reservoir_previous.M;
  const daxa_f32 newM = reservoir.M + prevM;

  if (reservoir.W_sum > 0.f) {
    float targetLumAtPrev = 0.0f;

    if (luminance(reservoir.F) > 1e-6) {

      daxa_u32 prev_predicted_index =
        predicted_coord.x + predicted_coord.y * rt_size.x;

      // compute target at current pixel with previous reservoir's sample
      DIRECT_ILLUMINATION_INFO di_info_previous =
          get_di_from_previous_frame(prev_predicted_index);

      HIT_INFO_INPUT prev_hit = HIT_INFO_INPUT(di_info_previous.position,
                                                di_info_previous.normal,
                                                di_info_previous.distance,
                                                daxa_f32vec3(0.0),
                                                di_info_previous.instance_hit,
                                                di_info_previous.mat_index);

      prev_hit.world_hit = compute_ray_origin(prev_hit.world_hit, prev_hit.world_nrm);
      prev_hit.world_hit = compute_ray_origin(prev_hit.world_hit, prev_hit.world_nrm);
      
      MATERIAL prev_mat = get_material_from_material_index(di_info_previous.mat_index);

      Ray prev_ray = Ray(di_info_previous.ray_origin, normalize(prev_hit.world_hit - di_info_previous.ray_origin));

      // // calculate target at previous pixel with current reservoir's sample
      targetLumAtPrev = luminance(reservoir_get_radiance(reservoir, prev_ray, prev_hit, prev_mat));
    }

    const float p_curr = reservoir.M * luminance(reservoir.F);
    const float m_curr = p_curr / max(p_curr + prevM * targetLumAtPrev, 1e-6);
    reservoir.W_sum *= m_curr;
  }

  if (get_reservoir_light_index(reservoir_previous) != -1) {
    daxa_f32vec3 currTarget = reservoir_get_radiance(reservoir_previous, ray, hit, mat); 
                                
    const float targetLumAtCurr = luminance(currTarget);

    // w_prev becomes zero; then only M needs to be updated, which is done at
    // the end anyway
    if (targetLumAtCurr > 0.f) {
      const float targetLumAtPrev = reservoir_previous.W_y > 0 ? reservoir_previous.W_sum / reservoir_previous.W_y : 0;
      // balance heuristic
      const float p_prev = reservoir_previous.M * targetLumAtPrev;
      const float m_prev = p_prev / max(p_prev + reservoir.M * targetLumAtCurr, 1e-6);
      const float w_prev = m_prev * targetLumAtCurr * reservoir_previous.W_y;

      update_reservoir(reservoir, get_reservoir_light_index(reservoir_previous),
                       get_reservoir_type(reservoir_previous),
                       get_reservoir_seed(reservoir_previous), currTarget,
                       w_prev, 1.f, seed);
    }
  }

  float targetLum = luminance(reservoir.F);
  reservoir.W_y = targetLum > 0.0 ? reservoir.W_sum / targetLum : 0.0;
  reservoir.M = newM;
}

void SPATIAL_REUSE(inout RESERVOIR reservoir, daxa_f32 confidence,
                   daxa_u32vec2 coord, daxa_u32vec2 rt_size, Ray ray,
                   inout HIT_INFO_INPUT hit, daxa_u32 current_mat_index,
                   MATERIAL mat, daxa_u32 light_count, daxa_f32 pdf,
                   inout daxa_u32 seed, const daxa_f32 min_radius,
                   const daxa_f32 max_radius) {//   confidence = clamp(confidence, 0.0, 1.0);

  if (reservoir.W_y == 0) {
    confidence = 0.0;
  }


  daxa_u32 reservoir_index[MAX_NUM_OF_NEIGHBORS];
  daxa_u32 num_of_neighbors = 0;

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
      MAX_NUM_OF_NEIGHBORS, MIN_NUM_OF_NEIGHBORS, clamp(confidence, 0.0, 1.0)));

  for (daxa_u32 i = 0; i < spatial_heuristic_num_of_neighbors; i++) {
    // Random offset
    daxa_f32vec2 offset = 2.0 * daxa_f32vec2(rnd(seed), rnd(seed)) - 1;

    // Scale offset
    offset.x =
        coord.x + daxa_i32(offset.x * spatial_heuristic_radius);
    offset.y =
        coord.y + daxa_i32(offset.y * spatial_heuristic_radius);

    // Clamp offset
    if(offset.x < 0 || offset.x >= rt_size.x || offset.y < 0 || offset.y >= rt_size.y) {
      continue;
    }

    if (offset.x == coord.x && offset.y == coord.y) {
      continue;
    }

    // Convert offset to u32
    daxa_u32vec2 offset_u32 = daxa_u32vec2(offset);

    // Convert offset to linear
    daxa_u32 offset_u32_linear = offset_u32.y * rt_size.x + offset_u32.x;

    DIRECT_ILLUMINATION_INFO neighbor_di_info =
        get_di_from_current_frame(offset_u32_linear);

    if(neighbor_di_info.distance <= 0.f) {
      continue;
    }

    // daxa_f32 neighbor_hit_dist = neighbor_di_info.distance;

    // daxa_u32 neighbor_mat_index = neighbor_di_info.mat_index;

    // TODO: Adjust dist threshold dynamically
    // if (neighbor_mat_index != current_mat_index ||
    //     (dot(hit.world_nrm, neighbor_di_info.normal.xyz) < 0.906) ||
    //     (abs(hit.distance - neighbor_hit_dist) > 0.1 * hit.distance)) {
    //   // skip this neighbour sample if not suitable
    //   continue;
    // }

    // neighbor_reservoir =
    //     get_reservoir_from_intermediate_frame_by_index(offset_u32_linear);

    // reservoir_visibility_pass(neighbor_reservoir, ray, hit, mat, light_count);

    reservoir_index[num_of_neighbors++] = offset_u32_linear;
  }

  if(num_of_neighbors == 0) {
    return;
  }

  daxa_u32 coord_index = coord.y * rt_size.x + coord.x;

  // DIRECT_ILLUMINATION_INFO central_di_info =
  //     get_di_from_current_frame(coord_index);

  PAIRWISE_MIS reservoir_mis;
  pairwise_init(reservoir_mis, num_of_neighbors, reservoir);

  for (daxa_u32 i = 0; i < num_of_neighbors; i++) {
    RESERVOIR neighbor_reservoir = get_reservoir_from_intermediate_frame_by_index(reservoir_index[i]);

    DIRECT_ILLUMINATION_INFO neighbor_di_info =
        get_di_from_current_frame(reservoir_index[i]);

    HIT_INFO_INPUT neighbor_hit = HIT_INFO_INPUT(
        neighbor_di_info.position, neighbor_di_info.normal,
        neighbor_di_info.distance, daxa_f32vec3(0.0),
        neighbor_di_info.instance_hit, neighbor_di_info.mat_index);

    neighbor_hit.world_hit =
        compute_ray_origin(neighbor_hit.world_hit, neighbor_hit.world_nrm);
    neighbor_hit.world_hit =
        compute_ray_origin(neighbor_hit.world_hit, neighbor_hit.world_nrm);

    Ray neighbor_ray =
        Ray(neighbor_di_info.ray_origin,
            normalize(neighbor_hit.world_hit - neighbor_di_info.ray_origin));

    MATERIAL neighbor_mat =
        get_material_from_material_index(neighbor_di_info.mat_index);

    pairwise_stream(reservoir_mis, reservoir, ray, hit, mat,
                        neighbor_reservoir, neighbor_ray, neighbor_hit,
                        neighbor_mat, seed);
  }

  pairwise_end(reservoir_mis, reservoir, seed);
  reservoir = reservoir_mis.reservoir;
}

// void SPATIAL_REUSE(inout RESERVOIR reservoir, daxa_f32 confidence,
//                    daxa_u32vec2 predicted_coord, daxa_u32vec2 rt_size, Ray ray,
//                    inout HIT_INFO_INPUT hit, daxa_u32 current_mat_index,
//                    MATERIAL mat, daxa_u32 light_count, daxa_f32 pdf,
//                    inout daxa_u32 seed, const daxa_f32 min_radius,
//                    const daxa_f32 max_radius) {
//   RESERVOIR spatial_reservoir;
//   initialise_reservoir(spatial_reservoir);

//   confidence = clamp(confidence, 0.0, 1.0);

//   // add previous samples
//   calculate_reservoir_aggregation(spatial_reservoir, reservoir, seed);

//   RESERVOIR neighbor_reservoir;

//   if (spatial_reservoir.W_y == 0) {
//     confidence = 0.0;
//   }

//   // daxa_f32 spatial_influence_threshold = max(1.0,
//   // (INFLUENCE_FROM_THE_PAST_THRESHOLD) / NUM_OF_NEIGHBORS);

//   // Heuristically determine the radius of the spatial reuse based on distance
//   // to the camera
//   daxa_f32 spatial_heuristic_radius =
//       mix(max_radius, min_radius,
//           clamp(hit.distance / MAX_DISTANCE_TO_HIT, 0.0, 1.0));

//   // Heuristically determine the number of neighbors based on the confidence
//   // index
//   daxa_u32 spatial_heuristic_num_of_neighbors = daxa_u32(mix(
//       MIN_NUM_OF_NEIGHBORS, MAX_NUM_OF_NEIGHBORS, clamp(confidence, 0.0, 1.0)));

//   for (daxa_u32 i = 0; i < spatial_heuristic_num_of_neighbors; i++) {
//     // Random offset
//     daxa_f32vec2 offset = 2.0 * daxa_f32vec2(rnd(seed), rnd(seed)) - 1;

//     // Scale offset
//     offset.x =
//         predicted_coord.x + daxa_i32(offset.x * spatial_heuristic_radius);
//     offset.y =
//         predicted_coord.y + daxa_i32(offset.y * spatial_heuristic_radius);

//     // Clamp offset
//     offset.x = min(rt_size.x - 1, max(0, min(rt_size.x - 1, offset.x)));
//     offset.y = min(rt_size.y - 1, max(0, min(rt_size.y - 1, offset.y)));

//     if (offset.x == predicted_coord.x && offset.y == predicted_coord.y) {
//       continue;
//     }

//     // Convert offset to u32
//     daxa_u32vec2 offset_u32 = daxa_u32vec2(offset);

//     // Convert offset to linear
//     daxa_u32 offset_u32_linear = offset_u32.y * rt_size.x + offset_u32.x;

//     DIRECT_ILLUMINATION_INFO neighbor_di_info =
//         get_di_from_current_frame(offset_u32_linear);

//     daxa_f32 neighbor_hit_dist = neighbor_di_info.distance;

//     daxa_u32 neighbor_mat_index = neighbor_di_info.mat_index;

//     // TODO: Adjust dist threshold dynamically
//     if (neighbor_mat_index != current_mat_index ||
//         (dot(hit.world_nrm, neighbor_di_info.normal.xyz) < 0.906) ||
//         (abs(hit.distance - neighbor_hit_dist) > 0.1 * hit.distance)) {
//       // skip this neighbour sample if not suitable
//       continue;
//     }

//     neighbor_reservoir =
//         get_reservoir_from_intermediate_frame_by_index(offset_u32_linear);

//     reservoir_visibility_pass(neighbor_reservoir, ray, hit, mat, light_count);

//     calculate_reservoir_aggregation(spatial_reservoir, neighbor_reservoir,
//                                     seed);
//   }

//   reservoir = spatial_reservoir;
// }