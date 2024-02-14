// path_tracer.glsl
#ifndef SHIFT_GLSL
#define SHIFT_GLSL
#define DAXA_RAY_TRACING 1
#include <daxa/daxa.inl>
#include "shared.inl"
#include "path_state.glsl"
#include "path_reservoir.glsl"
#include "light.glsl"


daxa_b32 is_jacobian_invalid(daxa_f32 jacobian) {
  return jacobian <= 0.f || isnan(jacobian) || isinf(jacobian);
}

const daxa_u32 BSDF_SPECULAR = 0xc;
const daxa_u32 BSDF_NON_SPECULAR = 0x3;

daxa_u32 get_allowed_bsdf_flags(daxa_b32 is_specular) {
  return is_specular ? BSDF_SPECULAR : BSDF_NON_SPECULAR;
}

// dst_pdf * dst_jacobian transforms pdf in dst space to src space
// src_pdf / dst_jacobian transforms pdf in src space to dst space
daxa_f32vec3 compute_shifted_integrand_reconnection(
    const SCENE_PARAMS params, inout daxa_f32 dst_jacobian,
    INTERSECT dst_primary_intersection, INTERSECT src_primary_intersection,
    inout PATH_RESERVOIR src_reservoir, const daxa_b32 eval_visibility,
    const daxa_b32 use_hybrid_shift, const daxa_b32 use_cached_jacobian) {
  daxa_f32vec3 dst_cached_jacobian;
  dst_jacobian = 0.f;

  // reconnection vertex number
  daxa_i32 rc_vertex_length =
      !use_hybrid_shift ? 1
                        : daxa_i32(path_reservoir_get_reconnection_length(
                              src_reservoir.path_flags));

  INSTANCE_HIT rc_vertex_hit = src_reservoir.rc_vertex_hit;
  daxa_f32vec3 rc_vertex_irradiance = src_reservoir.rc_vertex_irradiance[0];
  daxa_f32vec3 rc_vertex_wi = src_reservoir.rc_vertex_wi[0];
  daxa_b32 rc_vertex_hit_exists = instance_hit_exists(rc_vertex_hit);

  // number of vertices in the path
  daxa_u32 path_length =
      path_reservoir_get_path_length(src_reservoir.path_flags);
  // whether the last vertex is a NEE vertex
  daxa_b32 is_last_vertex_NEE =
      path_reservoir_last_vertex_NEE(src_reservoir.path_flags);

  // TODO: transmission events
  daxa_b32 is_transmission =
      path_reservoir_is_transmission_event(src_reservoir.path_flags, true);

  // TODO: re-visit this part when we have multi BSDF evaluation
  daxa_u32 allowed_sampled_types1 = get_allowed_bsdf_flags(
      path_reservoir_is_specular_bounce(src_reservoir.path_flags, true));

  // Step to avoid self-intersection
  src_primary_intersection.world_hit =
  compute_new_ray_origin(src_primary_intersection.world_hit,
  src_primary_intersection.world_nrm, !is_transmission);
  dst_primary_intersection.world_hit =
  compute_new_ray_origin(dst_primary_intersection.world_hit,
  dst_primary_intersection.world_nrm, !is_transmission);

  // If it was a miss, we need to evaluate the environment map light
  if (!rc_vertex_hit_exists) {
    daxa_f32vec3 dst_integrand = daxa_f32vec3(0.0f);
    // // TODO: re-visiting this part when we have environment map light
    // // are we having a infinite light as rcVertex?
    if (path_reservoir_get_light_type(src_reservoir.path_flags) ==
            GEOMETRY_LIGHT_ENV_MAP &&
        path_length + 1 == rc_vertex_length && !is_last_vertex_NEE) {
      daxa_f32vec3 wi = rc_vertex_wi;

      // Check if the environment map light is visible (sky light)
      daxa_b32 is_visible =
          is_segment_visible(dst_primary_intersection.world_hit, wi,
                             true); // test along a direction
      if (is_visible) {
        daxa_f32 src_pdf1 =
            use_cached_jacobian
                ? src_reservoir.cached_jacobian.x
                : sample_material_pdf(src_primary_intersection.mat,
                                      src_primary_intersection.world_nrm,
                                      src_primary_intersection.wo, wi);
        daxa_f32 dst_pdf1_all;
        // TODO: re - visit this part when we have multi BSDF evaluation
        //         daxa_f32 dst_pdf1 = evalPdfBSDF(dstPrimarySd, wi,
        //         dst_pdf1_all, allowed_sampled_types1);
        daxa_f32 dst_pdf1 = sample_material_pdf(
            dst_primary_intersection.mat, dst_primary_intersection.world_nrm,
            dst_primary_intersection.wo, wi);
        dst_pdf1_all = dst_pdf1;
        dst_cached_jacobian.x = dst_pdf1;
        // TODO: re - visit this part when we have multi BSDF evaluation
        //         daxa_f32vec3 dst_f1 = eval_bsdf_cosine(dstPrimarySd, wi,
        //         allowed_sampled_types1);
        daxa_f32vec3 dst_f1 = eval_bsdf_cosine(
            dst_primary_intersection.mat, dst_primary_intersection.world_nrm,
            dst_primary_intersection.wo, wi);
        daxa_f32 mis_weight =
            eval_mis(1, dst_pdf1_all, 1, src_reservoir.light_pdf,
                     2.f); //   dst_pdf1 / (dst_pdf1 + src_reservoir.light_pdf);
        dst_integrand = dst_f1 / dst_pdf1 * mis_weight * rc_vertex_irradiance;
        dst_jacobian = dst_pdf1 / src_pdf1;
      }
    }

    if (use_cached_jacobian)
      src_reservoir.cached_jacobian = dst_cached_jacobian;

    // fill in rcVertex0 information
    if (is_jacobian_invalid(dst_jacobian))
      dst_jacobian = 0.f;
    if (any(isnan(dst_integrand)) || any(isinf(dst_integrand)))
      return daxa_f32vec3(0.0f);

    return dst_integrand;
  }

  daxa_b32 is_rc_vertex_final = path_length == rc_vertex_length;
  daxa_b32 is_rc_vertex_escaped_vertex =
      path_length + 1 == rc_vertex_length && !is_last_vertex_NEE;
  daxa_b32 is_rc_vertex_NEE = is_rc_vertex_final && is_last_vertex_NEE;

  // TODO: delta events
  daxa_b32 is_delta1 =
      path_reservoir_is_delta_event(src_reservoir.path_flags, true);
  daxa_b32 is_delta2 =
      path_reservoir_is_delta_event(src_reservoir.path_flags, false);

  // delta bounce before/after rcVertex (if is_rc_vertex_NEE, deltaAfterRc won't
  // be set)
  if (is_delta1 || is_delta2)
    return daxa_f32vec3(0.0f);

  INTERSECT rc_vertex_intersection = load_intersection_data_vertex_position(
      rc_vertex_hit, dst_primary_intersection.world_hit, false, true);

  // need to evaluate source PDF of BSDF sampling
  daxa_f32vec3 dst_connection_v =
      -rc_vertex_intersection.wo; // direction point from dst primary hit point
                                  // to reconnection vertex
  daxa_f32vec3 src_connection_v = normalize(
      rc_vertex_intersection.world_hit -
      src_primary_intersection.world_hit); // direction point from src primary
                                           // hit point to reconnection vertex

  daxa_f32vec3 shifted_disp =
      rc_vertex_intersection.world_hit - dst_primary_intersection.world_hit;
  daxa_f32 shifted_dist2 = dot(shifted_disp, shifted_disp);
  daxa_f32 shifted_cosine =
      abs(dot(rc_vertex_intersection.world_nrm, -dst_connection_v));

  if (use_hybrid_shift) {
    daxa_b32 is_far_field = sqrt(shifted_dist2) >= params.near_field_distance;
    if (!is_far_field)
      return daxa_f32vec3(0.0f);
  }

  dst_cached_jacobian.z = shifted_cosine / shifted_dist2;
  daxa_f32 jacobian;
  if (use_cached_jacobian)
    jacobian = dst_cached_jacobian.z / src_reservoir.cached_jacobian.z;
  else {
    daxa_f32vec3 original_disp =
        rc_vertex_intersection.world_hit - src_primary_intersection.world_hit;
    daxa_f32 original_dist2 = dot(original_disp, original_disp);
    daxa_f32 original_cosine =
        abs(dot(rc_vertex_intersection.world_nrm, -src_connection_v));
    jacobian = dst_cached_jacobian.z * original_dist2 / original_cosine;
  }
  if (is_jacobian_invalid(jacobian))
    return daxa_f32vec3(0.0f);

  // // assuming BSDF sampling
  // assert(kUseBSDFSampling);

  // assuming bsdf sampling
  daxa_f32 dst_pdf1_all = 0.f;
  // TODO: re-visit this part when we implement multi BSDF evaluation
  // daxa_f32 dst_pdf1 = sample_material_all_pdf(dst_primary_intersection,
  // dst_connection_v, dst_pdf1_all, allowed_sampled_types1);
  daxa_f32 dst_pdf1 = sample_material_pdf(
      dst_primary_intersection.mat, dst_primary_intersection.world_nrm,
      dst_primary_intersection.wo, dst_connection_v);
  dst_pdf1_all = dst_pdf1;

  dst_cached_jacobian.x = dst_pdf1;
  // TODO: re-visit this part when we implement multi BSDF evaluation
  // daxa_f32 src_pdf1 = use_cached_jacobian ? src_reservoir.cached_jacobian.x :
  // evalPdfBSDF(src_primary_intersection, src_connection_v,
  // allowed_sampled_types1); //
  daxa_f32 src_pdf1 =
      use_cached_jacobian
          ? src_reservoir.cached_jacobian.x
          : sample_material_pdf(src_primary_intersection.mat,
                                src_primary_intersection.world_nrm,
                                src_primary_intersection.wo, src_connection_v);

  jacobian *= dst_pdf1 / src_pdf1;

  if (is_jacobian_invalid(jacobian))
    return daxa_f32vec3(0.0f);

  // TODO: re-visit this part when we implement multi BSDF evaluation
  // daxa_f32vec3 dst_f1 = eval_bsdf_cosine_all(dst_primary_intersection,
  // dst_connection_v, allowed_sampled_types1);
  daxa_f32vec3 dst_f1 = eval_bsdf_cosine(
      dst_primary_intersection.mat, dst_primary_intersection.world_nrm,
      dst_primary_intersection.wo, dst_connection_v);

  daxa_f32 dst_rc_vertex_scatter_pdf_all = 0.f;
  daxa_f32 dst_pdf2 = 1.f;
  daxa_f32 dst_rc_vertex_scatter_pdf = 1.f;
  daxa_f32 src_rc_vertex_scatter_pdf = 1.f;

  // TODO: re-visit this part when we have multi BSDF evaluation
  daxa_u32 allowed_sampled_type2 =
      is_rc_vertex_NEE
          ? -1
          : get_allowed_bsdf_flags(path_reservoir_is_specular_bounce(
                src_reservoir.path_flags, false));

  if (!is_rc_vertex_escaped_vertex) {
    // assuming bsdf sampling
    // TODO: re-visit this part when we implement multi BSDF evaluation
    // dst_rc_vertex_scatter_pdf = evalPdfBSDF(rc_vertex_intersection,
    // rc_vertex_wi, dst_rc_vertex_scatter_pdf_all, allowed_sampled_type2);
    dst_rc_vertex_scatter_pdf = sample_material_pdf(
        rc_vertex_intersection.mat, rc_vertex_intersection.world_nrm,
        rc_vertex_intersection.wo, rc_vertex_wi);
    dst_rc_vertex_scatter_pdf_all = dst_rc_vertex_scatter_pdf;

    dst_cached_jacobian.y = dst_rc_vertex_scatter_pdf;
    // TODO: re-visit this part when we implement multi BSDF evaluation
    // src_rc_vertex_scatter_pdf = use_cached_jacobian ?
    // src_reservoir.cached_jacobian.y :
    // sample_material_pdf_with_v(rc_vertex_intersection, -src_connection_v,
    // rc_vertex_wi, allowed_sampled_type2);
    src_rc_vertex_scatter_pdf =
        use_cached_jacobian
            ? src_reservoir.cached_jacobian.y
            : sample_material_pdf(rc_vertex_intersection.mat,
                                  rc_vertex_intersection.world_nrm,
                                  -src_connection_v, rc_vertex_wi);

    if (!is_rc_vertex_NEE)
      dst_pdf2 = dst_rc_vertex_scatter_pdf;
    else
      dst_pdf2 = src_reservoir.light_pdf;
  }

  daxa_f32vec3 dst_f2 = daxa_f32vec3(1.0f);

  if (!is_rc_vertex_escaped_vertex)
    // TODO: re-visit this part when we implement multi BSDF evaluation
    // dst_f2 = evalBSDFCosine(rc_vertex_intersection, rc_vertex_wi,
    // allowed_sampled_type2);
    dst_f2 = eval_bsdf_cosine(rc_vertex_intersection.mat,
                              rc_vertex_intersection.world_nrm,
                              rc_vertex_intersection.wo, rc_vertex_wi);

  // connection point behind surface
  if (all(equal(dst_f1, daxa_f32vec3(0.f))) ||
      all(equal(dst_f2, daxa_f32vec3(0.f))))
    return daxa_f32vec3(0.0f);

  //////
  daxa_f32vec3 dst_integrand_no_f1 = dst_f2 / dst_pdf2 * rc_vertex_irradiance;
  daxa_f32vec3 dst_integrand =
      dst_f1 / dst_pdf1 *
      dst_integrand_no_f1; // TODO: might need to reevaluate Le for changing
                           // emissive lights

  if (is_rc_vertex_escaped_vertex) {
    daxa_f32 mis_weight =
        eval_mis(1, dst_pdf1_all, 1, src_reservoir.light_pdf,
                 2.f); // dst_pdf1 / (src_reservoir.light_pdf + dst_pdf1);
    dst_integrand *= mis_weight;
  }

  // MIS weight
  if (is_rc_vertex_final) {
    if (path_reservoir_get_light_type(src_reservoir.path_flags) !=
        GEOMETRY_LIGHT_ANALITIC) // TODO: optimize way this check
    {
      daxa_f32 light_pdf = src_reservoir.light_pdf;
      daxa_f32 mis_weight = eval_mis(
          1, is_rc_vertex_NEE ? light_pdf : dst_rc_vertex_scatter_pdf_all, 1,
          is_rc_vertex_NEE ? dst_rc_vertex_scatter_pdf_all : light_pdf, 2.f);
      dst_integrand = dst_integrand * mis_weight;
      dst_integrand_no_f1 = dst_integrand_no_f1 * mis_weight;
      if (!is_rc_vertex_NEE)
        jacobian *= dst_rc_vertex_scatter_pdf / src_rc_vertex_scatter_pdf;
    }
  }

  // need to account for non-identity jacobian due to BSDF sampling
  if (!is_rc_vertex_final && !is_rc_vertex_escaped_vertex) {
    jacobian *= dst_rc_vertex_scatter_pdf / src_rc_vertex_scatter_pdf;
  }

  if (is_jacobian_invalid(jacobian))
    return daxa_f32vec3(0.0f);

  // Evaluate visibility: vertex 1 <-> vertex 2 (reconnection vertex).
  if (eval_visibility) {
    // Shadow ray
    Ray shadow_ray = Ray(dst_primary_intersection.world_hit,
                         normalize(rc_vertex_intersection.world_hit -
                                   dst_primary_intersection.world_hit));
    daxa_f32 distance = length(rc_vertex_intersection.world_hit -
                               dst_primary_intersection.world_hit);
    daxa_b32 is_visible = is_vertex_visible(
        shadow_ray, distance, rc_vertex_intersection.instance_hit, false);
    if (!is_visible)
      return daxa_f32vec3(0.0f);
  }

  if (any(isnan(dst_integrand)) || any(isinf(dst_integrand)))
    return daxa_f32vec3(0.0f);

  if (params.reject_based_on_jacobian) {
    if (jacobian > 0.f && (max(jacobian, 1 / jacobian) >
                           1 + params.jacobian_rejection_threshold)) {
      // discard based on jacobian (unbiased)
      jacobian = 0.f;
      dst_integrand = daxa_f32vec3(0.0f);
    }
  }

  dst_jacobian = jacobian;

  if (use_cached_jacobian)
    src_reservoir.cached_jacobian = dst_cached_jacobian;

  return dst_integrand;
}

daxa_f32vec3 compute_shifted_integrand_(
    const SCENE_PARAMS params, inout daxa_f32 dst_jacobian,
    const INSTANCE_HIT dst_primary_hit,
    const INTERSECT dst_primary_intersection,
    const INTERSECT src_primary_intersection,
    inout PATH_RESERVOIR src_reservoir, RECONNECTION_DATA rc_data,
    const daxa_b32 eval_visibility, const daxa_b32 use_prev,
    const daxa_b32 temporal_update_for_dynamic_scene) {
  dst_jacobian = 0.f;

  if (src_reservoir.weight == 0.f)
    return daxa_f32vec3(0.0f);

  if (params.shift_mapping == SHIFT_MAPPING_RECONNECTION) {

    if (temporal_update_for_dynamic_scene &&
        params.temporal_update_for_dynamic_scene) {
      path_tracer_trace_temporal_update(dst_primary_intersection,
                                        src_reservoir);
    }

    return compute_shifted_integrand_reconnection(
        params, dst_jacobian, dst_primary_intersection,
        src_primary_intersection, src_reservoir, eval_visibility, false,
        use_prev);
  }
  // else if (ShiftMapping(kShiftStrategy) == ShiftMapping::RandomReplay)
  // {
  //     return computeShiftedIntegrandRandomReplay(params, use_prev,
  //     dst_jacobian, dstPrimaryHitPacked, dstPrimarySd, srcPrimarySd,
  //     src_reservoir);
  // }
  // else if (ShiftMapping(kShiftStrategy) == ShiftMapping::Hybrid)
  // {
  //     return computeShiftedIntegrandHybrid(params, use_prev,
  //     temporal_update_for_dynamic_scene, dst_jacobian, dstPrimaryHitPacked,
  //     dstPrimarySd, srcPrimarySd, src_reservoir, rc_data, eval_visibility);
  // }

  return daxa_f32vec3(0.0f);
}

daxa_f32vec3 compute_shifted_integrand(
    const SCENE_PARAMS params, inout daxa_f32 dst_jacobian,
    const INSTANCE_HIT dst_primary_hit,
    const INTERSECT dst_primary_intersection,
    const INTERSECT src_primary_intersection,
    inout PATH_RESERVOIR src_reservoir, RECONNECTION_DATA rc_data,
    daxa_b32 eval_visibility, daxa_b32 use_prev,
    daxa_b32 temporal_update_for_dynamic_scene) {
  PATH_RESERVOIR temp_path_reservoir = src_reservoir;
  daxa_f32vec3 res = compute_shifted_integrand_(
      params, dst_jacobian, dst_primary_hit, dst_primary_intersection,
      src_primary_intersection, src_reservoir, rc_data, eval_visibility,
      use_prev, temporal_update_for_dynamic_scene);
  return res;
}

daxa_b32 shift_and_merge_reservoir(
    const SCENE_PARAMS params, const daxa_b32 temporal_update_for_dynamic_scene,
    inout daxa_f32 dst_jacobian, const INSTANCE_HIT dst_primary_hit,
    const INTERSECT dst_primary_intersection,
    inout PATH_RESERVOIR dst_reservoir,
    const INTERSECT src_primary_intersection,
    const PATH_RESERVOIR src_reservoir, RECONNECTION_DATA rc_data,
    daxa_b32 eval_visibility, inout daxa_u32 seed, daxa_b32 is_spatial_reuse,
    daxa_f32 mis_weight, daxa_b32 force_merge) {
  PATH_RESERVOIR temp_path_reservoir = src_reservoir;
  daxa_f32vec3 dst_integrand = compute_shifted_integrand_(
      params, dst_jacobian, dst_primary_hit, dst_primary_intersection,
      src_primary_intersection, temp_path_reservoir, rc_data, eval_visibility,
      false, temporal_update_for_dynamic_scene);

  daxa_b32 selected =
      path_reservoir_merge(dst_reservoir, dst_integrand, dst_jacobian,
                           temp_path_reservoir, seed, mis_weight, force_merge);

  if (force_merge) {
    if (!selected)
      dst_reservoir.F = daxa_f32vec3(0.0f);
    dst_reservoir.M = src_reservoir.M;
    dst_reservoir.weight = src_reservoir.weight;
  }

  return selected;
}

daxa_b32 merge_reservoir_with_resampling_MIS(
    const SCENE_PARAMS params, daxa_f32vec3 dst_integrand,
    daxa_f32 dst_jacobian, inout PATH_RESERVOIR dest_reservoir,
    PATH_RESERVOIR temp_dst_reservoir, PATH_RESERVOIR src_reservoir,
    inout daxa_u32 seed, daxa_b32 is_spatial_reuse, daxa_f32 mis_weight) {
  return path_reservoir_merge_with_resampling_MIS(
      dest_reservoir, dst_integrand, dst_jacobian, temp_dst_reservoir, seed,
      mis_weight, false);
}

#endif // SHIFT_GLSL