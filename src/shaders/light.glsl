#pragma once
#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>
#include "defines.glsl"
#include "prng.glsl"
#include "primitives.glsl"
#include "bounce.glsl"
#include "defines.glsl"
#include "mat.glsl"

LIGHT get_light_from_light_index(daxa_u32 light_index) {
  LIGHT_BUFFER light_buffer =
      LIGHT_BUFFER(deref(p.world_buffer).light_address);
  return light_buffer.lights[light_index];
}

LIGHT_CONFIG get_light_config_from_light_index() {
  LIGHT_CONFIG_BUFFER light_config_buffer =
      LIGHT_CONFIG_BUFFER(deref(p.status_buffer).light_config_address);
  return light_config_buffer.light_config;
}

daxa_f32 env_map_sampler_eval_pdf(daxa_f32vec3 dir) { return INV_DAXA_4PI; }

daxa_f32vec3 env_map_sampler_eval(daxa_f32vec3 dir) {
  return calculate_sky_color(deref(p.status_buffer).time,
                             deref(p.status_buffer).is_afternoon, dir);
}

daxa_b32 is_vertex_visible(Ray ray, daxa_f32 distance, OBJECT_INFO instance_target, daxa_b32 check_instance, const daxa_b32 previous_frame) {
  // NOTE: CHANGE RAY TRACE FOR RAY QUERY GAVE ME A 15% PERFORMANCE BOOST!!??

  daxa_f32 t_min = 0.0;
  daxa_f32 t_max = distance;
  daxa_u32 cull_mask = 0xff;
  daxa_u32 ray_flags = gl_RayFlagsTerminateOnFirstHitEXT | gl_RayFlagsOpaqueEXT;

  OBJECT_INFO instance_hit = OBJECT_INFO(MAX_INSTANCES, MAX_PRIMITIVES);
  daxa_f32vec3 int_hit = daxa_f32vec3(0.0);
  daxa_f32vec3 int_nor = daxa_f32vec3(0.0);
  daxa_b32 is_hit = false;
  daxa_f32 hit_distance = 0.0;
  daxa_f32mat4x4 model;
  daxa_f32mat4x4 inv_model;
  daxa_u32 material_idx = 0;
  MATERIAL intersected_mat;

  rayQueryEXT ray_query;

  rayQueryInitializeEXT(ray_query, daxa_accelerationStructureEXT(p.tlas),
                        ray_flags, cull_mask, ray.origin, t_min, ray.direction,
                        t_max);

  while (rayQueryProceedEXT(ray_query)) {
    daxa_u32 type = rayQueryGetIntersectionTypeEXT(ray_query, false);
    if (type == gl_RayQueryCandidateIntersectionAABBEXT) {
      // get instance id
      daxa_u32 instance_id =
          rayQueryGetIntersectionInstanceCustomIndexEXT(ray_query, false);

      // Get primitive id
      daxa_u32 primitive_id =
          rayQueryGetIntersectionPrimitiveIndexEXT(ray_query, false);

      instance_hit = OBJECT_INFO(instance_id, primitive_id);

      daxa_f32vec3 half_extent = daxa_f32vec3(HALF_VOXEL_EXTENT);

      if (is_hit_from_ray(ray, instance_hit, half_extent, hit_distance, int_hit,
                          int_nor, model, inv_model, previous_frame, false, true)) {
        rayQueryGenerateIntersectionEXT(ray_query, hit_distance);

        daxa_u32 type_commited =
            rayQueryGetIntersectionTypeEXT(ray_query, true);

        if (type_commited == gl_RayQueryCommittedIntersectionGeneratedEXT) {
          if(check_instance && instance_target.instance_id == instance_hit.instance_id && instance_target.primitive_id == instance_hit.primitive_id) {
            is_hit = false;
            break;
          }
          is_hit = true;
        }
      }
    }
  }

  rayQueryTerminateEXT(ray_query);

  return !is_hit;
}


daxa_b32 is_segment_visible(daxa_f32vec3 source_vertex, daxa_f32vec3 target_vertex, daxa_b32 is_dir, const daxa_b32 previous_frame) {
  
  Ray ray;
  daxa_f32 distance;
  if(is_dir) {
    ray = Ray(source_vertex, target_vertex);
    distance = MAX_DISTANCE;
  } else {
    ray = Ray(source_vertex, target_vertex - source_vertex);
    distance = length(target_vertex - source_vertex);
  }

  return is_vertex_visible(ray, distance, OBJECT_INFO(MAX_INSTANCES, MAX_PRIMITIVES), false, previous_frame);
}

daxa_f32 geom_fact_sa(daxa_f32vec3 P, daxa_f32vec3 P_surf, daxa_f32vec3 n_surf) {
    daxa_f32vec3 dir = normalize(P_surf - P);
    daxa_f32 dist2 = dot(P_surf - P, P_surf - P);
    return abs(dot(n_surf, dir)) / dist2;
}

daxa_f32 balance_heuristic(daxa_f32 pdf, daxa_f32 pdf_other) {
  return pdf / (pdf + pdf_other);
}

daxa_f32 power_heuristic(daxa_f32 pdf, daxa_f32 pdf_other) {
  daxa_f32 f = pdf * pdf;
  daxa_f32 g = pdf_other * pdf_other;
  return f / (f + g);
}

daxa_f32 power_exp_heuristic(daxa_f32 pdf, daxa_f32 pdf_other, daxa_f32 exp) {
  daxa_f32 f = pow(pdf, exp);
  daxa_f32 g = pow(pdf_other, exp);
  return f / (f + g);
}

daxa_f32 eval_mis(daxa_f32 nf, daxa_f32 f_pdf, daxa_f32 ng, daxa_f32 g_pdf,
                  daxa_f32 exp) {
#if USE_POWER_HEURISTIC == 1
  return power_heuristic(f_pdf, g_pdf);
#elif USE_POWER_EXP_HEURISTIC == 1
  return power_exp_heuristic(f_pdf, g_pdf, exp);
#else
  return balance_heuristic(f_pdf, g_pdf);
#endif
}

daxa_f32vec3 evaluate_emissive(INTERSECT i, daxa_f32vec3 wi) {
  // Calculate how many light comes from the light source
  daxa_f32vec3 Le = i.mat.emission;

  return Le;
}

daxa_f32 sample_material_pdf(MATERIAL mat, daxa_f32vec3 n, daxa_f32vec3 wo,
                             daxa_f32vec3 wi) {

  daxa_f32vec3 wo_l = to_local(n, wo);
  daxa_f32vec3 wi_l = to_local(n, wi);

  // TODO: just diffuse for now
  switch (mat.type & MATERIAL_TYPE_MASK) {
  case MATERIAL_TYPE_METAL: {
    return (DAXA_2PI);
  } break;
  case MATERIAL_TYPE_DIELECTRIC: {
    return (DAXA_2PI);
  } break;
  case MATERIAL_TYPE_CONSTANT_MEDIUM: {
    return DAXA_4PI;
  } break;
  default: {
#if COSINE_HEMISPHERE_SAMPLING == 1
    if (min(wo_l.z, wi_l.z) < MIN_COS_THETA) return 0.f;
    return  INV_DAXA_PI * wi_l.z;
#else
    return INV_DAXA_2PI;
#endif

  } break;
  }

  return 0.0;
}

daxa_b32 sample_material(Ray ray, MATERIAL mat, inout HIT_INFO_INPUT hit,
                         daxa_f32vec3 wo, inout daxa_f32vec3 wi,
                         out daxa_f32 pdf, daxa_u32 object_count, inout daxa_u32 seed) {

  call_scatter.hit = hit.world_hit;
  call_scatter.nrm = hit.world_nrm;
  call_scatter.ray_dir = ray.direction;
  call_scatter.seed = seed;
  call_scatter.scatter_dir = vec3(0.0);
  call_scatter.done = false;
  call_scatter.mat_idx = hit.mat_idx;
  call_scatter.instance_hit = hit.instance_hit;

  daxa_u32 mat_type = mat.type & MATERIAL_TYPE_MASK;

  switch (mat_type) {
  case MATERIAL_TYPE_METAL:
    executeCallableEXT(3, 4);
    break;
  case MATERIAL_TYPE_DIELECTRIC:
    executeCallableEXT(4, 4);
    break;
  case MATERIAL_TYPE_CONSTANT_MEDIUM:
    executeCallableEXT(5, 4);
    break;
  case MATERIAL_TYPE_LAMBERTIAN:
  default:
    executeCallableEXT(2, 4);
    break;
  }
  wi = call_scatter.scatter_dir;
  seed = call_scatter.seed;

  pdf = sample_material_pdf(mat, call_scatter.nrm, wo, wi);

  hit = HIT_INFO_INPUT(call_scatter.hit, call_scatter.nrm, hit.distance, wi,
                       call_scatter.instance_hit, call_scatter.mat_idx);

  return !call_scatter.done;
}

daxa_f32 sample_lights_pdf(inout HIT_INFO_INPUT hit, INTERSECT i,
                           daxa_u32 light_count) {
  daxa_f32 p = 1.0 / daxa_f32(light_count);

  // if (object.type == GEOMETRY_LIGHT_SPEHERE)
  // {
  //     daxa_f32 r = object.size.x;
  //     daxa_f32 area_half_sphere = 2.0 * PI * r * r;
  //     p /= area_half_sphere;
  // }
  // else if (object.type == GEOMETRY_LIGHT_CUBE)
  // {
  daxa_f32 voxel_extent = VOXEL_EXTENT;
  // TODO: config
  daxa_f32vec2 size = daxa_f32vec2(voxel_extent, voxel_extent);

  daxa_f32 area_cube = size.x * size.y * 6.0;
  p /= area_cube;
  // }

  return p;
}

daxa_b32 sample_lights(inout HIT_INFO_INPUT hit, LIGHT l, inout daxa_f32 pdf,
                       out daxa_f32vec3 P_out, out daxa_f32vec3 n_out,
                       out daxa_f32vec3 Le_out, inout daxa_u32 seed,
                       out daxa_f32 G_out,
                       const in daxa_b32 calc_pdf, daxa_b32 visibility) {
  daxa_f32vec3 l_pos, l_nor;

  daxa_f32vec3 P = hit.world_hit;
  daxa_f32vec3 n = hit.world_nrm;
  daxa_f32 distance = -1.0;
  daxa_f32vec3 l_wi = daxa_f32vec3(0.0);

  // // TODO: Check this
  // // Fast discard
  if (l.instance_info.instance_id == hit.instance_hit.instance_id &&
      l.instance_info.primitive_id == hit.instance_hit.primitive_id) {
    Le_out = daxa_f32vec3(0.0);
    return false;
  }
  daxa_b32 vis = true;
  daxa_b32 check_instance = false;
  
  if (l.type == GEOMETRY_LIGHT_CUBE) {

    daxa_f32mat4x4 model;
    daxa_f32mat4x4 inv_model;

    // Size of the quad
    daxa_f32 half_extent = l.size * 0.5;
    daxa_f32vec2 quad_size = daxa_f32vec2(l.size, l.size);

#if KNOWN_LIGHT_POSITION == 1
    daxa_u32 i = 0;

    do {
      vis = true;

      l_nor = random_cube_normal(seed);

      // Getting the position of the light on the quad surface by stepping half
      // the extent of the voxel from the very center
      l_pos = l.position + l_nor * half_extent;
      // Get random position in the light on the quad surface
      l_pos = random_quad(l_nor, l_pos, quad_size * 0.5, seed);

      l_wi = normalize(P - l_pos);

      vis = vis && daxa_b32(dot(l_wi, l_nor) > 0.0); // Light front side
      vis = vis && daxa_b32(dot(l_wi, n) < 0.0);     // Behind the surface at P
    } while (!vis && i++ < 10);

#else
    vis = is_hit_from_origin(P, l.instance_info, half_extent, distance, l_pos,
                             l_nor, model, inv_model, true, false);
                             
    // l_pos = l_pos + random_quad(l_nor, size, seed);
#endif // 0

    l_pos = compute_ray_origin(l_pos, l_nor);
    l_pos = compute_ray_origin(l_pos, l_nor);
    // TODO: check this cause we should need to substrac the half extent
    distance = length(P - l_pos);

    if (calc_pdf) {
      daxa_f32 area = quad_size.x * quad_size.y * 6.0;
      pdf /= area;
    }
    check_instance = true;
    G_out = geom_fact_sa(P, l_pos, l_nor);
  } else if (l.type == GEOMETRY_LIGHT_POINT) {
    l_pos = l.position;
    l_nor = normalize(P - l_pos);
    distance = length(P - l_pos);
    check_instance = false;
    l_wi = l_nor;
    G_out = geom_fact_sa(P, l_pos, l_nor);
  } else if (l.type == GEOMETRY_LIGHT_ENV_MAP) {
    // TODO: check this
    daxa_f32vec3 l_dir = random_on_hemisphere(seed, n);
    l_pos = P + (l_dir * MAX_DISTANCE);
    l_nor = normalize(P - l_pos);
    distance = length(P - l_pos);
    check_instance = false;
    l_wi = l_nor;
    l.emissive *= env_map_sampler_eval(l_dir);
    if (calc_pdf) {
      pdf /= env_map_sampler_eval_pdf(l_dir);
    }
    G_out = 1.0;
  }
  
  daxa_f32vec3 l_v = -l_wi;
  // Shadow ray
  Ray shadow_ray = Ray(P, l_v);

  if (visibility && vis) {
    // TODO: check if we need to use the previous frame
    vis = vis && is_vertex_visible(shadow_ray, distance, l.instance_info, check_instance, false);
  }

  P_out = l_pos;
  n_out = l_nor;
  Le_out = vis ? l.emissive : daxa_f32vec3(0.0);
  return vis;
}

daxa_f32vec3 calculate_sampled_light(
    Ray ray, inout HIT_INFO_INPUT hit, MATERIAL mat, daxa_u32 light_count,
    LIGHT light, daxa_f32 pdf, out daxa_f32 pdf_out, inout daxa_u32 seed, const in daxa_b32 calc_pdf,
    const in daxa_b32 use_pdf, daxa_b32 use_visibility) {
  // 2. Get light direction
  daxa_f32vec3 surface_normal = normalize(hit.world_nrm);
  daxa_f32vec3 wo = -normalize(ray.direction);

  daxa_f32vec3 l_pos, l_nor, Le;

  pdf_out = pdf;

  daxa_f32vec3 result = vec3(0.0);

  daxa_f32 G;

  if (sample_lights(hit, light, pdf_out, l_pos, l_nor, Le, seed, G, calc_pdf,
                    use_visibility)) {
    daxa_f32vec3 wi = normalize(l_pos - hit.world_hit);
    daxa_f32vec3 brdf = evaluate_material(mat, surface_normal, wo, wi);
    // daxa_f32 G = geom_fact_sa(hit.world_hit, l_pos, l_nor);

    if (use_pdf) {
      result = brdf * Le * G / pdf_out;
    } else {
      result = brdf * Le * G;
    }
  }

  return result;
}

daxa_f32vec3 direct_mis(Ray ray, inout HIT_INFO_INPUT hit, daxa_u32 light_count,
                        LIGHT light, daxa_u32 object_count, MATERIAL mat,
                        out INTERSECT i, out daxa_f32 pdf_out,
                        inout daxa_u32 seed, out daxa_f32 path_pdf,
                        inout daxa_f32vec3 throughput,
                        const in daxa_b32 use_pdf,
                        const in daxa_b32 use_visibility) {
  daxa_f32vec3 result = vec3(0.0);
  daxa_f32vec3 Le, l_pos, l_nor;
  daxa_f32 l_pdf, m_pdf;

  pdf_out = 1.0;

  l_pdf = 1.0 / daxa_f32(light_count);
  m_pdf = 1.0;

  daxa_f32vec3 P = hit.world_hit;
  daxa_f32vec3 n = hit.world_nrm;
  daxa_f32vec3 wo = normalize(ray.origin - P);
  daxa_f32 G;

  // Light sampling
  if (sample_lights(hit, light, l_pdf, l_pos, l_nor, Le, seed, G, use_pdf,
                    use_visibility)) {
    daxa_f32vec3 l_wi = normalize(l_pos - P);
    // daxa_f32 G = geom_fact_sa(P, l_pos, l_nor);
    daxa_f32 m_pdf = sample_material_pdf(mat, n, wo, l_wi);
    daxa_f32 mis_weight = eval_mis(1, l_pdf, 1, m_pdf * G, 2.0);
    daxa_f32vec3 brdf = evaluate_material(mat, n, wo, l_wi);

    throughput *= brdf * G;

    if (use_pdf) {
      result += throughput * mis_weight * Le / l_pdf;
    } else {
      result += throughput * mis_weight * Le;
    }
    pdf_out *= l_pdf;
  }

  daxa_f32vec3 m_wi = vec3(0.0);

  daxa_f32 m_pdf_2 = 1.0;
  daxa_f32 l_pdf_2 = 1.0 / daxa_f32(light_count);

  if (use_visibility) {
    // Material sampling
    if (sample_material(ray, mat, hit, wo, m_wi, m_pdf_2, object_count, seed)) {
      // Get pdf for the material
      path_pdf = m_pdf_2;
      i = intersect(Ray(P, m_wi));
      if (i.is_hit && any(greaterThan(i.mat.emission,vec3(0.0)))) {
        daxa_f32 G = geom_fact_sa(P, i.world_hit, i.world_nrm);
        daxa_f32 light_pdf = sample_lights_pdf(hit, i, light_count);
        daxa_f32 mis_weight = eval_mis(1, m_pdf_2 * G, 1, light_pdf, 2.0);
        daxa_f32vec3 brdf = evaluate_material(mat, n, wo, m_wi);
        daxa_f32vec3 Le = evaluate_emissive(i, m_wi);
        throughput *= brdf;
        if (use_pdf) {
          result += throughput * mis_weight * Le / m_pdf_2;
        } else {
          result += throughput * mis_weight * Le;
        }
        pdf_out *= m_pdf_2;
      }
    }
  }

  return result;
}