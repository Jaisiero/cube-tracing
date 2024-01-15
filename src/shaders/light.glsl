#pragma once
#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>
#include "defines.glsl"
#include "prng.glsl"
#include "primitives.glsl"

daxa_f32 get_cos_theta(daxa_f32vec3 n, daxa_f32vec3 w_i) {
    return max(dot(n, w_i), 0.0);
}

daxa_b32 is_light_visible(Ray ray, LIGHT light, _HIT_INFO hit) 
{

    vec3 L = vec3(0.0, 0.0, 0.0);
    daxa_f32 distance = 0.0;
    // Point light
    if(light.type == 0)
    {
        vec3 lDir      = light.position - hit.world_hit;
        distance  = length(lDir);
        L              = normalize(lDir);
    }
    else  // Directional light
    {
        L = normalize(light.position);
    }

    vec3 color = vec3(0.0, 0.0, 0.0);

    if(dot(hit.world_nrm, L) > 0) {
        daxa_f32 t_min   = 0.0001;
        daxa_f32 t_max   = distance;
        vec3  ray_origin = hit.world_hit;
        vec3  ray_dir = L;
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

daxa_f32vec3 evaluate_material(MATERIAL mat) {
    // TODO: just diffuse for now
    daxa_f32vec3 color = get_diffuse_BRDF(mat);

    return color;
}

daxa_b32 sample_lights(daxa_f32vec3 P, daxa_f32vec3 n,
                       LIGHT l, inout daxa_f32 pdf,
                       out daxa_f32vec3 P_out, out daxa_f32vec3 n_out,
                       out daxa_f32vec3 Le_out, 
                       const in daxa_b32 visibility)
{
    daxa_f32vec3 l_pos , l_nor;

    // TODO: Discard self-intersection?
    // // Fast discard
    // if(l.instance_index == gl_InstanceCustomIndexEXT && l.primitive_index == gl_PrimitiveID) {
    //     Le_out = vec3(0.0);
    //     return false;
    // }

    if (l.type == GEOMETRY_LIGHT_SPEHERE)
    {
        // float r = l.size.x;
        // // Choose a normal on the side of the sphere visible to P.
        // l_nor = random_hemisphere(P - l.pos);
        // l_pos = l.pos + l_nor * r;
        // float area_half_sphere = 2.0 * PI * r * r;
        // pdf /= area_half_sphere;
    }
    else if (l.type == GEOMETRY_LIGHT_QUAD)
    {
        daxa_f32 voxel_extent = VOXEL_EXTENT;

        daxa_u32 current_primitive_index = current_primitive_index_from_instance_and_primitive_id(l.instance_index, l.primitive_index);

        // Get aabb from primitive
        Aabb aabb = deref(p.aabb_buffer).aabbs[current_primitive_index];

        // Get model matrix from instance
        daxa_f32mat4x4 model = get_geometry_transform_from_instance_id(l.instance_index);

        Ray ray;
        // TODO: check this
        ray.origin = P + n * AVOID_VOXEL_COLLAIDE;
        ray.direction = l.position - P;

        daxa_f32mat4x4 inv_model = inverse(model);

        ray.origin = (inv_model * vec4(ray.origin, 1)).xyz;
        ray.direction = (inv_model * vec4(ray.direction, 0)).xyz;

        float tHit = -1;

        tHit = hitAabb(aabb, ray);

        // Get center of aabb
        daxa_f32vec3 center = (aabb.minimum + aabb.maximum) * 0.5;

        // Transform center to world space
        center = (model * vec4(center, 1)).xyz;

        daxa_f32vec3 world_pos = ray.origin + ray.direction * tHit;

        // Computing the normal at hit position
        daxa_f32vec3 world_nrm = normalize(world_pos - center);
        {
            daxa_f32vec3 abs_n = abs(world_nrm);
            daxa_f32 max_c = max(max(abs_n.x, abs_n.y), abs_n.z);
            world_nrm = (max_c == abs_n.x) ? vec3(sign(world_nrm.x), 0, 0) : (max_c == abs_n.y) ? vec3(0, sign(world_nrm.y), 0)
                                                                                            : vec3(0, 0, sign(world_nrm.z));
        }
        l_nor = world_nrm;

        // TODO: config
        daxa_f32vec2 size = daxa_f32vec2(voxel_extent, voxel_extent);

        // l_pos = world_pos; //+ random_quad(l_nor, size, prd.seed);
        l_pos = world_pos + random_quad(l_nor, size, prd.seed);
        daxa_f32 area = size.x * size.y * 6.0;
        pdf /= area;
    } 
    else if (l.type == GEOMETRY_LIGHT_POINT)
    {
        l_pos = l.position;
        l_nor = normalize(P - l_pos);
    }


    daxa_b32 vis = daxa_b32(dot(P - l_pos, l_nor) > 0.0); // Light front side
    vis = vis && daxa_b32(dot(P - l_pos, n) < 0.0);         // Behind the surface at P
                                            // Shadow ray



    Ray shadow_ray = Ray(P, l_pos - P);

    if(visibility) {
        vis = vis && is_light_visible(shadow_ray, l, _HIT_INFO(P, n));
    }

    P_out = l_pos;
    n_out = l_nor;
    Le_out = vis ? l.emissive : vec3(0.0);
    return vis;
}

daxa_f32vec3 calculate_sampled_light(Ray ray, _HIT_INFO hit, LIGHT light, MATERIAL mat, daxa_u32 light_count, out daxa_f32 pdf, const in daxa_b32 use_pdf, const in daxa_b32 use_visibility) {
    // 2. Get light direction
    daxa_f32vec3 light_direction = normalize(light.position - hit.world_hit);
    daxa_f32vec3 surface_normal = hit.world_nrm;

    daxa_f32vec3 l_pos , l_nor , Le;

    pdf = 1.0 / daxa_f32(light_count);

    if(sample_lights(hit.world_hit, hit.world_nrm, light, pdf, l_pos, l_nor, Le, use_visibility) == false) {
        return vec3(0.0);
    }

    daxa_f32vec3 brdf = evaluate_material(mat);
    daxa_f32 cos_theta = get_cos_theta(surface_normal, light_direction);
    daxa_f32 G = geom_fact_sa(hit.world_hit, l_pos, l_nor);

    daxa_f32vec3 light_contribution = vec3(0.0);
    
    if(use_pdf) {
        light_contribution = brdf * Le * G * cos_theta / pdf;
    } else {
        light_contribution = brdf * Le * G * cos_theta;
    
    }

    return light_contribution;
}