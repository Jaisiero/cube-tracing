#pragma once
#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>
#include "defines.glsl"
#include "prng.glsl"
#include "primitives.glsl"
#include "bounce.glsl"
#include "mat.glsl"

daxa_f32vec3 safe(daxa_f32vec3 point, daxa_f32vec3 normal) {
    // Ajustar el punto ligeramente en la dirección opuesta a la normal
    return point - normal * DELTA_RAY;
}


LIGHT get_light_from_light_index(daxa_u32 light_index) {
    LIGHT_BUFFER instance_buffer = LIGHT_BUFFER(deref(p.world_buffer).light_address);
    return instance_buffer.lights[light_index];
}

daxa_f32 get_cos_theta(daxa_f32vec3 n, daxa_f32vec3 w_i) {
    return max(dot(n, w_i), 0.0);
}

daxa_b32 is_light_visible(Ray ray, LIGHT light,  daxa_f32 distance) 
{
    // NOTE: CHANGE RAY TRACE FOR RAY QUERY GAVE ME A 15% PERFORMANCE BOOST!!??

    daxa_f32 t_min = DELTA_RAY;
    daxa_f32 t_max = distance - DELTA_RAY;
    daxa_u32 cull_mask = 0xff;
    daxa_u32 ray_flags = gl_RayFlagsTerminateOnFirstHitEXT | gl_RayFlagsOpaqueEXT;

    INSTANCE_HIT instance_hit = INSTANCE_HIT(MAX_INSTANCES - 1, MAX_PRIMITIVES - 1);
    daxa_f32vec3 int_hit = daxa_f32vec3(0.0);
    daxa_f32vec3 int_nor = daxa_f32vec3(0.0);
    daxa_b32 is_hit = false;
    daxa_f32 hit_distance = 0.0;
    daxa_f32mat4x4 model;
    daxa_f32mat4x4 inv_model;
    daxa_u32 material_idx = 0;
    MATERIAL intersected_mat;


    rayQueryEXT ray_query;

    rayQueryInitializeEXT(ray_query,
                          daxa_accelerationStructureEXT(p.tlas),
                          ray_flags,
                          cull_mask, 
                          ray.origin, t_min, 
                          ray.direction, t_max);

    while (rayQueryProceedEXT(ray_query))
    {
        daxa_u32 type = rayQueryGetIntersectionTypeEXT(ray_query, false);
        if (type ==
            gl_RayQueryCandidateIntersectionAABBEXT)
        {
            // get instance id
            daxa_u32 instance_id = rayQueryGetIntersectionInstanceCustomIndexEXT(ray_query, false);

            // Get primitive id
            daxa_u32 primitive_id = rayQueryGetIntersectionPrimitiveIndexEXT(ray_query, false);

            instance_hit = INSTANCE_HIT(instance_id, primitive_id);

            daxa_f32vec3 half_extent = daxa_f32vec3(HALF_VOXEL_EXTENT);

            if(is_hit_from_ray(ray, instance_hit, half_extent, hit_distance, int_hit, int_nor, model, inv_model, false, false)) {
                rayQueryGenerateIntersectionEXT(ray_query, hit_distance);

                daxa_u32 type_commited = rayQueryGetIntersectionTypeEXT(ray_query, true);

                if (type_commited ==
                    gl_RayQueryCommittedIntersectionGeneratedEXT)
                {
                    is_hit = true;
            //         material_idx = get_material_index_from_instance_and_primitive_id(instance_hit);
            //         intersected_mat = get_material_from_material_index(material_idx);
        
            //         daxa_f32vec4 int_hit_4 = model * vec4(int_hit, 1);
            //         int_hit = int_hit_4.xyz / int_hit_4.w;
            //         int_nor = (transpose(inv_model) * vec4(int_nor, 0)).xyz;
            //         break;
                }
            }
        }
    }

    rayQueryTerminateEXT(ray_query);

    return !is_hit;
}


daxa_f32 geom_fact_sa(daxa_f32vec3 P, daxa_f32vec3 P_surf, daxa_f32vec3 n_surf)
{
    daxa_f32vec3 dir = normalize(P_surf - P);
    daxa_f32 dist2 = distance(P, P_surf);
    return abs(-dot(n_surf, dir)) / (dist2 * dist2);
}

daxa_f32 balance_heuristic(daxa_f32 pdf , daxa_f32 pdf_other) {
    return pdf / (pdf + pdf_other);
}

daxa_f32vec3 evaluate_material(MATERIAL mat, daxa_f32vec3 n, daxa_f32vec3 wo, daxa_f32vec3 wi) {
    daxa_f32vec3 color = vec3(0.0);
    switch (mat.type & MATERIAL_TYPE_MASK)
    {
        case MATERIAL_TYPE_METAL: {
            color = get_metal_BRDF(mat, n, wi, wo);
        }
        break;
        case MATERIAL_TYPE_DIELECTRIC: {
            color = get_dialectric_BRDF(mat, n, wi, wo);
        }
        break;
        case MATERIAL_TYPE_CONSTANT_MEDIUM: {
            color = get_constant_medium_BRDF(mat, n, wi, wo);
        }
        break;
        default: {
            color = get_diffuse_BRDF(mat, n, wi, wo);
        }
        break;
    }

    return color;
}


daxa_f32vec3 evaluate_emissive(INTERSECT i, daxa_f32vec3 wi) {
    // Calculate how many light comes from the light source
    daxa_f32vec3 Le = i.mat.emission;

    return Le;
}


daxa_f32 sample_material_pdf(MATERIAL mat, daxa_f32vec3 n, daxa_f32vec3 wo, daxa_f32vec3 wi) {

    daxa_f32 pdf = 1.0;
    // TODO: just diffuse for now
    switch (mat.type & MATERIAL_TYPE_MASK)
    {
        case MATERIAL_TYPE_METAL: {
            pdf *= (INV_DAXA_PI);
        }
        break;
        case MATERIAL_TYPE_DIELECTRIC: {
            pdf *= (INV_DAXA_PI);
        }
        break;
        case MATERIAL_TYPE_CONSTANT_MEDIUM: {
            pdf *= 1.0;
        }
        break;
        default: {
            pdf *= (INV_DAXA_PI);
        }
        break;
    }

    return pdf;
}


daxa_b32 sample_material(Ray ray, MATERIAL mat, inout HIT_INFO_INPUT hit, daxa_f32vec3 wo, inout daxa_f32vec3 wi, out daxa_f32 pdf, daxa_u32 object_count)
{
    pdf = 1.0 / daxa_f32(object_count);

    call_scatter.hit = hit.world_hit;
    call_scatter.nrm = hit.world_nrm;
    call_scatter.ray_dir = ray.direction;
    call_scatter.seed = hit.seed;
    call_scatter.scatter_dir = vec3(0.0);
    call_scatter.done = false;
    call_scatter.mat_idx = hit.mat_idx;
    call_scatter.instance_hit = hit.instance_hit;

    daxa_u32 mat_type = mat.type & MATERIAL_TYPE_MASK;

    switch (mat_type)
    {
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
    hit = HIT_INFO_INPUT(call_scatter.hit, call_scatter.nrm, call_scatter.scatter_dir, call_scatter.instance_hit, call_scatter.mat_idx, hit.depth, call_scatter.seed);

    return !call_scatter.done;
}

daxa_f32 sample_lights_pdf(inout HIT_INFO_INPUT hit, INTERSECT i, daxa_u32 light_count)
{
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

daxa_b32 sample_lights(inout HIT_INFO_INPUT hit,
                       LIGHT l, inout daxa_f32 pdf,
                       out daxa_f32vec3 P_out, out daxa_f32vec3 n_out,
                       out daxa_f32vec3 Le_out, 
                       const in daxa_b32 calc_pdf,
                       const in daxa_b32 visibility)
{
    daxa_f32vec3 l_pos , l_nor;

    daxa_f32vec3 P = hit.world_hit;
    daxa_f32vec3 n = hit.world_nrm;
    daxa_f32 distance = -1.0;

    // // TODO: Check this
    // // Fast discard
    if(l.instance_info.instance_id == hit.instance_hit.instance_id && l.instance_info.primitive_id == hit.instance_hit.primitive_id) {
        Le_out = vec3(0.0);
        return false;
    }
    daxa_b32 vis = true;

    // // if (l.type == GEOMETRY_LIGHT_SPEHERE)
    // // {
    // //     // daxa_f32 r = l.size.x;
    // //     // // Choose a normal on the side of the sphere visible to P.
    // //     // l_nor = random_hemisphere(P - l.pos);
    // //     // l_pos = l.pos + l_nor * r;
    // //     // daxa_f32 area_half_sphere = 2.0 * PI * r * r;
    // //     // pdf /= area_half_sphere;
    // // }
    // // else
    if (l.type == GEOMETRY_LIGHT_CUBE)
    {

        daxa_f32mat4x4 model;
        daxa_f32mat4x4 inv_model;

        // TODO: pass this as a parameter
        daxa_f32vec3 half_extent = daxa_f32vec3(HALF_VOXEL_EXTENT);

        vis = is_hit_from_origin(P, l.instance_info,
            half_extent, distance, 
            l_pos, l_nor, 
            model, inv_model, true, false);

        // TODO: config voxel extent by parameter
        daxa_f32 voxel_extent = VOXEL_EXTENT;
        daxa_f32vec2 size = daxa_f32vec2(voxel_extent, voxel_extent);
        l_pos = l_pos + random_quad(l_nor, size, hit.seed);

        daxa_f32vec4 l_pos_4 = model * vec4(l_pos, 1);
        l_pos = l_pos_4.xyz / l_pos_4.w;
        l_nor = (transpose(inv_model) * vec4(l_nor, 0)).xyz;
        // l_pos += l_nor * voxel_extent;
        distance = length(P - l_pos) - length(half_extent);

        if(calc_pdf) {
            daxa_f32 area = size.x * size.y * 6.0;
            pdf /= area;
        }
    } 
    else if (l.type == GEOMETRY_LIGHT_POINT)
    {
        l_pos = l.position;
        l_nor = normalize(P - l_pos);
        distance = length(P - l_pos);
    }

    daxa_f32vec3 l_wi = normalize(P - l_pos);
    daxa_f32vec3 l_wo = -l_wi;


    vis = vis && daxa_b32(dot(l_wi, l_nor) > 0.0); // Light front side
    vis = vis && daxa_b32(dot(l_wi, n) < 0.0); // Behind the surface at P
    // Shadow ray
    Ray shadow_ray = Ray(P, l_wo);

    if(visibility && vis) {
        vis = vis && is_light_visible(shadow_ray, l, distance);
    }

    P_out = l_pos;
    n_out = l_nor;
    Le_out = daxa_f32(vis) * l.emissive; 
    return vis;
}

daxa_f32vec3 calculate_sampled_light(Ray ray, inout HIT_INFO_INPUT hit, MATERIAL mat, daxa_u32 light_count, LIGHT light, daxa_f32 pdf, out daxa_f32 pdf_out, const in daxa_b32 calc_pdf, const in daxa_b32 use_pdf, const in daxa_b32 use_visibility) {
    // 2. Get light direction
    daxa_f32vec3 light_direction = normalize(light.position - hit.world_hit);
    daxa_f32vec3 surface_normal = normalize(hit.world_nrm);
    daxa_f32vec3 wi = normalize(ray.direction);
    daxa_f32vec3 wo = -wi;

    daxa_f32vec3 l_pos , l_nor , Le;

    pdf_out = pdf;
    
    sample_lights(hit, light, pdf_out, l_pos, l_nor, Le, calc_pdf, use_visibility);

    daxa_f32vec3 brdf = evaluate_material(mat, surface_normal, wi, wo);
    // daxa_f32 cos_theta = get_cos_theta(surface_normal, light_direction);
    daxa_f32 cos_theta = 1.0;
    // daxa_f32 G = geom_fact_sa(hit.world_hit, l_pos, l_nor);

    daxa_f32 G = 1.0;

    daxa_f32vec3 result = vec3(0.0);
    
    if(use_pdf) {
        result = brdf * Le * G * cos_theta / pdf_out;
    } else {
        result = brdf * Le * G * cos_theta;
    
    }

    return result;
}

daxa_f32vec3 direct_mis(Ray ray, inout HIT_INFO_INPUT hit, daxa_u32 light_count, LIGHT light, daxa_u32 object_count, MATERIAL mat, out INTERSECT i,  out daxa_f32 pdf_out, const in daxa_b32 use_pdf, const in daxa_b32 use_visibility) {
    daxa_f32vec3 result = vec3(0.0);
    daxa_f32vec3 Le, l_pos, l_nor;
    daxa_f32 l_pdf, m_pdf;

    pdf_out = 0.0;

    l_pdf = 1.0 / daxa_f32(light_count);
    m_pdf = 1.0;

    daxa_f32vec3 P = hit.world_hit;
    daxa_f32vec3 n = hit.world_nrm;
    daxa_f32vec3 wo = ray.direction;

    // Light sampling
    if(sample_lights(hit, light, l_pdf, l_pos, l_nor, Le, use_pdf, use_visibility)) {
        daxa_f32vec3 l_wi = normalize(l_pos - P);
        daxa_f32 G = geom_fact_sa(P, l_pos, l_nor);
        daxa_f32 m_pdf = sample_material_pdf(mat, n, wo, l_wi);
        daxa_f32 mis_weight = balance_heuristic(l_pdf, m_pdf * G);
        daxa_f32 cos_theta = get_cos_theta(n, l_wi);
        daxa_f32vec3 brdf = evaluate_material(mat, n, wo, l_wi);
        if(use_pdf) {
            result += brdf * mis_weight * G * cos_theta * Le / l_pdf;
        } else {
            result += brdf * mis_weight * G * cos_theta * Le;
        }
        pdf_out += l_pdf;
    }

    daxa_f32vec3 m_wi = vec3(0.0);

    daxa_f32 m_pdf_2 = 1.0;
    daxa_f32 l_pdf_2 = 1.0 / daxa_f32(light_count);

    if(use_visibility) {
        // Material sampling
        if (sample_material(ray, mat, hit, wo, m_wi, m_pdf_2, light_count))
        {
            i = intersect(Ray(P, m_wi), hit);
            if (i.is_hit && i.mat.emission != vec3(0.0))
            {
                daxa_f32 G = geom_fact_sa(P, i.world_hit, i.world_nrm);
                daxa_f32 light_pdf = sample_lights_pdf(hit, i, light_count);
                daxa_f32 mis_weight = balance_heuristic(m_pdf_2 * G, light_pdf);
                daxa_f32vec3 brdf = evaluate_material(mat, n, wo, m_wi);
                daxa_f32vec3 Le = evaluate_emissive(i, m_wi);
                daxa_f32 cos_theta = get_cos_theta(m_wi, n);
                if (use_pdf)
                {
                    result += brdf * cos_theta * mis_weight * Le / m_pdf_2;
                }
                else
                {
                    result += brdf * cos_theta * mis_weight * Le;
                }
                pdf_out += m_pdf_2;
            }
        }
    }

    return result;
}