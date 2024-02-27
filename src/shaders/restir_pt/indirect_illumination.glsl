// indirect_illumination.glsl
#ifndef INDIRECT_ILLUMINATION_GLSL
#define INDIRECT_ILLUMINATION_GLSL
#include <daxa/daxa.inl>
#include "shared.inl"
#include "path_state.glsl"
#include "path_tracer.glsl"
#include "shift.glsl"

daxa_f32vec3 trace_hybrid_shift_rays(const SCENE_PARAMS params,
                                     const daxa_b32 use_preview,
                                     const OBJECT_INFO primary_hit,
                                     const INTERSECT i,
                                     const PATH_RESERVOIR reservoir,
                                     out OBJECT_HIT dst_rc_prev_vertex_hit,
                                     out daxa_f32vec3 dst_rc_prev_vertex_wo) {
  if (reservoir.weight == 0.0)
    return daxa_f32vec3(0.0);
  // TODO: calculate previus ray origin and direction?
  daxa_f32vec3 origin = i.world_hit + ((-i.wo) * i.distance);
  Ray ray = Ray(origin, i.wo);
  return trace_random_replay_path_hybrid_simple(
      params, primary_hit, i, ray, reservoir.path_flags,
      reservoir.init_random_seed, dst_rc_prev_vertex_hit,
      dst_rc_prev_vertex_wo);
}

PATH_RESERVOIR temporal_path_get_reprojected(
    const daxa_i32vec2 index, const daxa_u32vec2 rt_size,
    out daxa_u32 current_index, out daxa_u32 prev_predicted_index) {
  current_index = index.y * rt_size.x + index.x;

  // Compute offset into per-sample buffers. All samples are stored
  // consecutively at this offset.
  VELOCITY velocity = velocity_buffer_get_velocity(index, rt_size);

  // X from current pixel position
  daxa_f32vec2 Xi = daxa_f32vec2(index.xy) + 0.5;

  // X from previous pixel position
  daxa_f32vec2 Xi_1 = Xi + velocity.velocity;

  // Predicted coordinate
  daxa_u32vec2 predicted_coord = daxa_u32vec2(Xi_1);
  prev_predicted_index = predicted_coord.x + predicted_coord.y * rt_size.x;

  // Max screen pos
  daxa_u32 max_screen_pos = rt_size.x * rt_size.y - 1;

  // Clamp screen pos for
  prev_predicted_index = min(max_screen_pos, prev_predicted_index);

  // Get temporal reservoir
  return get_temporal_path_reservoir_by_index(prev_predicted_index);
}

INTERSECT
temporal_path_get_reprojected_primary_hit(const daxa_u32 prev_predicted_index) {

  // Get temporal reprojection primary hit
  DIRECT_ILLUMINATION_INFO di_info_previous =
      get_di_from_previous_frame(prev_predicted_index);

  MATERIAL previus_material =
      get_material_from_material_index(di_info_previous.mat_index);

  daxa_b32 is_hit = di_info_previous.distance > 0.0;

  daxa_f32vec3 wo = di_info_previous.ray_origin - di_info_previous.position;

  // TODO: wi is half vector between wo and normal
  daxa_f32vec3 wi = daxa_f32vec3(0.0); // normalize(wo + di_info_previous.normal);
    // normalize(wo + di_info_previous.normal);

  return INTERSECT(is_hit, di_info_previous.distance, di_info_previous.position,
                   di_info_previous.normal, wo, wi,
                   di_info_previous.instance_hit, di_info_previous.mat_index,
                   previus_material);
}

void temporal_path_retrace(const SCENE_PARAMS params,
                           const PATH_RESERVOIR central_reservoir,
                           const PATH_RESERVOIR temporal_reservoir,
                           daxa_u32 current_index,
                           daxa_u32 prev_predicted_index,
                           const INTERSECT current_intersection,
                           const INTERSECT previous_intersection) {

  // TODO: This is for hybrid shift
  OBJECT_HIT dst_rc_prev_vertex_hit;
  OBJECT_HIT dst_rc_prev_vertex_hit2;
  daxa_f32vec3 dst_rc_prev_vertex_wo;
  daxa_f32vec3 dst_rc_prev_vertex_wo2;
  daxa_f32vec3 tp;
  daxa_f32vec3 tp2;

  // write to memory
  if (path_reservoir_get_reconnection_length(central_reservoir.path_flags) >
      1) {
    tp = trace_hybrid_shift_rays(
        params, true, previous_intersection.instance_hit, previous_intersection,
        central_reservoir, dst_rc_prev_vertex_hit, dst_rc_prev_vertex_wo);
    set_reconnection_data_from_current_frame(
        current_index, 0,
        RECONNECTION_DATA(dst_rc_prev_vertex_hit, dst_rc_prev_vertex_wo, tp));
  }
  if (path_reservoir_get_reconnection_length(temporal_reservoir.path_flags) >
      1) {
    tp2 = trace_hybrid_shift_rays(
        params, false, current_intersection.instance_hit, current_intersection,
        temporal_reservoir, dst_rc_prev_vertex_hit2, dst_rc_prev_vertex_wo2);
    set_reconnection_data_from_current_frame(
        current_index, 1,
        RECONNECTION_DATA(dst_rc_prev_vertex_hit2, dst_rc_prev_vertex_wo2,
                          tp2));
  }
}

void temporal_path_reuse(const SCENE_PARAMS params,
                         const PATH_RESERVOIR central_reservoir,
                         PATH_RESERVOIR temporal_reservoir,
                         const daxa_u32 current_index, inout daxa_u32 seed,
                         INTERSECT current_i, INTERSECT prev_i,
                         out daxa_f32vec3 indirect_color) {

  PATH_RESERVOIR destination_reservoir;
  path_reservoir_initialise(params, destination_reservoir);

  // Get current history length
  daxa_f32 current_M = central_reservoir.M;

  // Clamp the influence from the past
  temporal_reservoir.M = min(MAX_INFLUENCE_FROM_THE_PAST_THRESHOLD_PT * current_M,
                             temporal_reservoir.M);

  // for hybrid shift
  RECONNECTION_DATA dummy_rc_data;
  reconnection_data_initialise(dummy_rc_data);

  // Temporal and shift mapping parameters
  daxa_b32 do_temporal_update_for_dynamic_scene =
      params.temporal_update_for_dynamic_scene;
  daxa_b32 use_hybrid_shift = params.shift_mapping == SHIFT_MAPPING_HYBRID;

  // TALBOT RMIS
  {
    const daxa_i32 cur_sample_id = -1;
    const daxa_i32 prev_sample_id = 0;
    daxa_f32 dst_jacobian;

    for (daxa_i32 i = cur_sample_id; i <= prev_sample_id; ++i) {
      daxa_f32 p_sum = 0;
      daxa_f32 p_self = 0;

      PATH_RESERVOIR temp_dst_reservoir = destination_reservoir;

      daxa_b32 possible_to_be_selected = false;

      if (i == cur_sample_id) {
        temp_dst_reservoir = central_reservoir;
        dst_jacobian = 1.f;
        possible_to_be_selected = temp_dst_reservoir.weight > 0;
      } else {
        RECONNECTION_DATA rc_data = dummy_rc_data;
        // TODO: This is for hybrid shift
        if (use_hybrid_shift && path_reservoir_get_reconnection_length(
                                    temporal_reservoir.path_flags) > 1)
          rc_data = get_reconnection_data_from_current_frame(current_index, 1);

        // Merge with shift mapping for the current vertex
        possible_to_be_selected = shift_and_merge_reservoir(
            params, do_temporal_update_for_dynamic_scene, dst_jacobian,
            OBJECT_HIT(current_i.instance_hit, current_i.world_hit), current_i, temp_dst_reservoir, prev_i,
            temporal_reservoir, rc_data, true, seed, false, 1.f,
            true); // "true" means hypothetically selected as the sample
      }

      if (possible_to_be_selected) {
        for (daxa_i32 j = cur_sample_id; j <= prev_sample_id; ++j) {
          if (j == cur_sample_id) {
            daxa_f32 cur_p = path_F_to_scalar(temp_dst_reservoir.F) * current_M;
            p_sum += cur_p;
            if (i == cur_sample_id)
              p_self = cur_p;
          } else {
            if (i == j) {
              p_self = path_F_to_scalar(temporal_reservoir.F) / dst_jacobian *
                       temporal_reservoir.M;
              p_sum += p_self;
              continue;
            }

            daxa_f32 p_ = 0.f;
            daxa_f32 t_neighbor_jacobian;

            // TODO: This is for hybrid shift
            RECONNECTION_DATA rc_data = dummy_rc_data;
            if (use_hybrid_shift && path_reservoir_get_reconnection_length(
                                        temp_dst_reservoir.path_flags) > 1)
              rc_data =
                  get_reconnection_data_from_current_frame(current_index, 0);
                  
            // Calculate the integrand for the previous vertex
            daxa_f32vec3 t_neighbor_integrand = compute_shifted_integrand(
                params, t_neighbor_jacobian, OBJECT_HIT(prev_i.instance_hit, prev_i.world_hit), prev_i,
                current_i, temp_dst_reservoir, rc_data, true, true,
                false); // use_prev

            p_ = path_F_to_scalar(t_neighbor_integrand) * t_neighbor_jacobian;
            p_sum += p_ * temporal_reservoir.M;
          }
        }
      }

      // Calculate MIS weight
      daxa_f32 mis_weight = p_sum == 0.f ? 0.f : p_self / p_sum;
      // TODO: neighbor_reservoir is pointless cause it's not used inside the
      // function
      PATH_RESERVOIR neighbor_reservoir;
      if (i == cur_sample_id)
        neighbor_reservoir = temp_dst_reservoir;
      else
        neighbor_reservoir = temporal_reservoir;

      // Merge the reservoirs
      merge_reservoir_with_resampling_MIS(
          params, temp_dst_reservoir.F, dst_jacobian, destination_reservoir,
          temp_dst_reservoir, neighbor_reservoir, seed, false, mis_weight);
    }

    if (destination_reservoir.weight > 0) {
      path_reservoir_finalize_GRIS(destination_reservoir);
    }
  }

  if (destination_reservoir.weight < 0.f ||
      isinf(destination_reservoir.weight) ||
      isnan(destination_reservoir.weight))
    destination_reservoir.weight = 0.f;

  // Set the current reservoir for next frame
  set_temporal_path_reservoir_by_index(current_index, destination_reservoir);

  indirect_color = destination_reservoir.F * destination_reservoir.weight;
}

void indirect_illumination_restir_path_tracing(const SCENE_PARAMS params,
                                               const daxa_i32vec2 index,
                                               const daxa_u32vec2 rt_size,
                                               Ray ray, INTERSECT i,
                                               inout daxa_u32 seed,
                                               inout daxa_f32vec3 indirect_color) {

  PATH_RESERVOIR central_reservoir = trace_restir_path_tracing(
      params, index, rt_size, ray, i, seed, indirect_color);

#if RESTIR_PT_TEMPORAL_ON == 1
  daxa_u32 current_index;
  daxa_u32 prev_predicted_index;
  PATH_RESERVOIR temporal_reservoir = temporal_path_get_reprojected(
      index, rt_size, current_index, prev_predicted_index);

  INTERSECT prev_i =
      temporal_path_get_reprojected_primary_hit(prev_predicted_index);

  // Retrace the temporal path in case of hybrid shift
  // temporal_path_retrace(params, central_reservoir, temporal_reservoir,
  // current_index, prev_predicted_index, i, prev_i);

  // Temporal path reuse previous frame contribution
  temporal_path_reuse(params, central_reservoir, temporal_reservoir,
                      current_index, seed, i, prev_i, indirect_color);
#endif // RESTIR_PT_TEMPORAL_ON                      

  // Set the current reservoir for next frame
  // set_temporal_path_reservoir_by_index(current_index, central_reservoir);
}

void indirect_illumination_path_tracing(
    const daxa_i32vec2 index, const daxa_u32vec2 rt_size, Ray ray, MATERIAL mat,
    INTERSECT i, daxa_u32 seed, daxa_u32 max_depth, daxa_u32 light_count,
    daxa_u32 object_count, inout daxa_f32vec3 indirect_color) {

  // prd.indirect_color = vec3(1.0);
  prd.seed = seed;
  prd.depth = max_depth;
  prd.world_hit = i.world_hit;
  prd.distance = i.distance;
  prd.world_nrm = i.world_nrm;
  prd.ray_scatter_dir = i.wi;
  prd.mat_index = i.material_idx;
  prd.instance_hit = i.instance_hit;
  prd.hit_value = daxa_f32vec3(0.0);

  daxa_f32vec3 throughput = daxa_f32vec3(1.0);
  // prd.done = true;

  // generate_scatter_ray(i, seed);

  for (;;) {

    i.world_hit = compute_ray_origin(i.world_hit, i.world_nrm);

    HIT_INFO_INPUT hit =
        HIT_INFO_INPUT(i.world_hit, i.world_nrm, i.distance, i.wo,
                       i.instance_hit, i.material_idx, seed, max_depth);
    Ray scattered_ray = Ray(i.world_hit, -i.wo);

    if (i.is_hit) {

      daxa_u32 light_index =
          min(urnd_interval(prd.seed, 0, light_count), light_count - 1);

      LIGHT light = get_light_from_light_index(light_index);

      daxa_f32 pdf_out = 1.0;

      daxa_f32vec3 radiance =
          direct_mis(scattered_ray, hit, light_count, light, object_count,
                     i.mat, i, pdf_out, true, true);

      throughput *= radiance;
      prd.done = false;
    } else {
      prd.done = true;
      throughput *= calculate_sky_color(deref(p.status_buffer).time,
                                        deref(p.status_buffer).is_afternoon,
                                        scattered_ray.direction);
    }
    prd.hit_value += throughput;

    if(any(lessThanEqual(throughput, daxa_f32vec3(0.0))))
      prd.done = true;

    prd.depth--;
    daxa_b32 done = prd.done || prd.depth == 0;
#if SER == 1
    reorderThreadNV(daxa_u32(done), 1);
#endif // SER
    if (done)
      break;

    prd.done = true; // Will stop if a reflective material isn't hit
  }
  indirect_color = prd.hit_value;
}

void indirect_illumination(const SCENE_PARAMS params, const daxa_i32vec2 index,
                           const daxa_u32vec2 rt_size, Ray ray, MATERIAL mat,
                           const INTERSECT i, daxa_u32 seed,
                           inout daxa_f32vec3 indirect_color) {
#if RESTIR_PT_ON == 1
  indirect_illumination_restir_path_tracing(params, index, rt_size, ray, i,
                                            seed, indirect_color);
#else
  indirect_illumination_path_tracing(index, rt_size, ray, mat, i, seed,
                                     params.max_depth, params.light_count,
                                     params.object_count, indirect_color);
#endif
}

void indirect_illumination_spatial_reuse(const SCENE_PARAMS params,
                                         const daxa_i32vec2 index,
                                         const daxa_u32vec2 rt_size,
                                         const INTERSECT current_intersection,
                                         daxa_u32 seed,
                                         inout daxa_f32vec3 indirect_color) {

  // Get current pixel
  daxa_u32 current_index = index.y * rt_size.x + index.x;

  // Get current pixel path reservoir
  PATH_RESERVOIR central_reservoir = get_temporal_path_reservoir_by_index(current_index); 

  PATH_RESERVOIR destination_reservoir;
  path_reservoir_initialise(params, destination_reservoir);

  // for hybrid shift
  RECONNECTION_DATA dummy_rc_data;
  reconnection_data_initialise(dummy_rc_data);

  

}

#endif // INDIRECT_ILLUMINATION_GLSL