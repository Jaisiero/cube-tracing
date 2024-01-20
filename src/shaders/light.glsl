#pragma once
#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>
#include "defines.glsl"
#include "prng.glsl"
#include "primitives.glsl"
#include "bounce.glsl"
#include "mat.glsl"

daxa_f32 get_cos_theta(daxa_f32vec3 n, daxa_f32vec3 w_i) {
    return max(dot(n, w_i), 0.0);
}

daxa_b32 is_light_visible(Ray ray, LIGHT light, HIT_INFO_INPUT hit) 
{

    daxa_f32vec3 L = vec3(0.0, 0.0, 0.0);
    daxa_f32 distance = 0.0;
    // Point light
    if(light.type == 0)
    {
        daxa_f32vec3 lDir      = light.position - hit.world_hit;
        distance  = length(lDir);
        L              = normalize(lDir);
    }
    else  // Directional light
    {
        L = normalize(light.position);
    }

    daxa_f32vec3 color = vec3(0.0, 0.0, 0.0);

    if(dot(hit.world_nrm, L) > 0) {
        daxa_f32 t_min   = 0.0001;
        daxa_f32 t_max   = distance;
        daxa_f32vec3  ray_origin = hit.world_hit;
        daxa_f32vec3  ray_dir = L;
        uint cull_mask = 0xff;
        uint  flags  = gl_RayFlagsTerminateOnFirstHitEXT | gl_RayFlagsOpaqueEXT | gl_RayFlagsSkipClosestHitShaderEXT;
        is_shadowed = true;

        traceRayEXT(
            daxa_accelerationStructureEXT(p.tlas),
            flags,  // rayFlags
            cull_mask,   // cullMask
            0,      // sbtRecordOffset
            0,      // sbtRecordStride
            1,      // missIndex
            ray_origin, // ray origin
            t_min,   // ray min range
            ray_dir, // ray direction
            t_max,   // ray max range
            1       // payload (location = 1)
        );
    }

    return !is_shadowed;
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
    // TODO: just diffuse for now
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


daxa_f32 sample_material_pdf(MATERIAL mat, daxa_f32vec3 n, daxa_f32vec3 wo, daxa_f32vec3 wi, daxa_f32 pdf) {
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


daxa_b32 sample_material(MATERIAL mat, inout HIT_INFO_INPUT hit, daxa_f32vec3 wo, inout daxa_f32vec3 wi, out daxa_f32 pdf, daxa_u32 object_count)
{
    pdf = 1.0 / daxa_f32(object_count);

    // TODO: just diffuse for now
    pdf *= (0.5 * INV_DAXA_PI);
    wi = random_cosine_direction(hit.seed) + hit.world_nrm;

    return true;
}

daxa_f32 sample_lights_pdf(inout HIT_INFO_INPUT hit, INTERSECT i, daxa_f32 pdf)
{
    daxa_f32 p = pdf;

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

    // TODO: Discard self-intersection?
    // // Fast discard
    // if(l.instance_index == gl_InstanceCustomIndexEXT && l.primitive_index == gl_PrimitiveID) {
    //     Le_out = vec3(0.0);
    //     return false;
    // }
    daxa_b32 vis = false;

    // if (l.type == GEOMETRY_LIGHT_SPEHERE)
    // {
    //     // daxa_f32 r = l.size.x;
    //     // // Choose a normal on the side of the sphere visible to P.
    //     // l_nor = random_hemisphere(P - l.pos);
    //     // l_pos = l.pos + l_nor * r;
    //     // daxa_f32 area_half_sphere = 2.0 * PI * r * r;
    //     // pdf /= area_half_sphere;
    // }
    // else
     if (l.type == GEOMETRY_LIGHT_CUBE)
    {
        // TODO: config
        daxa_f32 voxel_extent = VOXEL_EXTENT;
        daxa_f32vec2 size = daxa_f32vec2(voxel_extent, voxel_extent);

        Ray ray;
        ray.origin = P + n * AVOID_VOXEL_COLLAIDE;
        ray.direction = l.position - P;

        daxa_f32 t_hit = -1.0;

        vis = is_hit_from_ray(ray, l.instance_index, l.primitive_index, t_hit, l_pos, l_nor, true, false);

        l_pos = l_pos + random_quad(l_nor, size, hit.seed);
        if(calc_pdf) {
            daxa_f32 area = size.x * size.y * 6.0;
            pdf /= area;
        }
    } 
    else if (l.type == GEOMETRY_LIGHT_POINT)
    {
        l_pos = l.position;
        l_nor = normalize(P - l_pos);
    }


    vis = daxa_b32(dot(P - l_pos, l_nor) > 0.0); // Light front side
    vis = vis && daxa_b32(dot(P - l_pos, n) < 0.0);         // Behind the surface at P
                                            // Shadow ray



    Ray shadow_ray = Ray(P, l_pos - P);

    if(visibility) {
        vis = vis && is_light_visible(shadow_ray, l, hit);
    }

    P_out = l_pos;
    n_out = l_nor;
    Le_out = daxa_f32(vis) * l.emissive;
    return vis;
}

daxa_f32vec3 calculate_sampled_light(Ray ray, inout HIT_INFO_INPUT hit, LIGHT light, MATERIAL mat, daxa_u32 light_count, daxa_f32 pdf, out daxa_f32 pdf_out, const in daxa_b32 calc_pdf, const in daxa_b32 use_pdf, const in daxa_b32 use_visibility) {
    // 2. Get light direction
    daxa_f32vec3 light_direction = normalize(light.position - hit.world_hit);
    daxa_f32vec3 surface_normal = hit.world_nrm;
    daxa_f32vec3 wi = ray.direction;

    daxa_f32vec3 l_pos , l_nor , Le;

    pdf_out = pdf;

    // if(sample_lights(hit, light, pdf_out, l_pos, l_nor, Le, calc_pdf, use_visibility) == false) {
    //     return vec3(0.0);
    // }
    sample_lights(hit, light, pdf_out, l_pos, l_nor, Le, calc_pdf, use_visibility);

    daxa_f32vec3 brdf = evaluate_material(mat, surface_normal, ray.direction, wi);
    daxa_f32 cos_theta = get_cos_theta(surface_normal, light_direction);
    daxa_f32 G = geom_fact_sa(hit.world_hit, l_pos, l_nor);

    daxa_f32vec3 result = vec3(0.0);
    
    if(use_pdf) {
        result = brdf * Le * G * cos_theta / pdf_out;
    } else {
        result = brdf * Le * G * cos_theta;
    
    }

    return result;
}

daxa_f32vec3 direct_mis(Ray ray, inout HIT_INFO_INPUT hit, daxa_u32 light_count, LIGHT light, daxa_u32 object_count, MATERIAL mat, out daxa_f32vec3 m_wi,  out daxa_f32 pdf, const in daxa_b32 use_pdf, const in daxa_b32 use_visibility) {
    daxa_f32vec3 result = vec3(0.0);
    daxa_f32vec3 Le, l_pos, l_nor;
    daxa_f32 l_pdf, m_pdf;

    pdf = 0.0;

    l_pdf = 1.0 / daxa_f32(light_count);
    m_pdf = 1.0 / daxa_f32(object_count);

    daxa_f32vec3 P = hit.world_hit;
    daxa_f32vec3 n = hit.world_nrm;
    daxa_f32vec3 wo = ray.direction;

    // Light sampling
    if(sample_lights(hit, light, l_pdf, l_pos, l_nor, Le, true, use_visibility)) {
        daxa_f32vec3 l_wi = normalize(l_pos - P);
        daxa_f32 G = geom_fact_sa(P, l_pos, l_nor);
        daxa_f32 m_pdf = sample_material_pdf(mat, n, wo, l_wi, m_pdf);
        daxa_f32 mis_weight = balance_heuristic(l_pdf, m_pdf * G);
        daxa_f32 cos_theta = get_cos_theta(n, l_wi);
        daxa_f32vec3 brdf = evaluate_material(mat, n, wo, l_wi);
        if(use_pdf) {
            result += brdf * mis_weight * G * cos_theta * Le / l_pdf;
        } else {
            result += brdf * mis_weight * G * cos_theta * Le;
        }
        pdf += l_pdf;
    }

    daxa_f32 m_pdf_2;
    daxa_f32 l_pdf_2 = 1.0 / daxa_f32(light_count);

    if(use_visibility) {
        // Material sampling
        if (sample_material(mat, hit, wo, m_wi, m_pdf_2, object_count))
        {
            if (hit.depth > 0)
            {
                INTERSECT i = intersect(Ray(P, m_wi), hit);
                if (i.is_hit && i.mat.emission != vec3(0.0))
                {
                    daxa_f32 G = geom_fact_sa(P, i.world_hit, i.world_nrm);
                    daxa_f32 light_pdf = sample_lights_pdf(hit, i, l_pdf_2);
                    daxa_f32 mis_weight = balance_heuristic(m_pdf_2 * G, light_pdf);
                    daxa_f32vec3 brdf = evaluate_material(i.mat, n, wo, m_wi);
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
                    pdf += m_pdf_2;
                }
            }
        }
    }

    return result;
}