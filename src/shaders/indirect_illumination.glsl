// indirect_illumination.glsl
#ifndef INDIRECT_ILLUMINATION_GLSL
#define INDIRECT_ILLUMINATION_GLSL
#include <daxa/daxa.inl>
#include "shared.inl"
#include "primitives.glsl"
#include "light.glsl"
#extension GL_EXT_ray_query : enable

void indirect_illumination(INTERSECT i, daxa_u32 seed, daxa_u32 max_depth, daxa_u32 light_count, daxa_u32 object_count, inout daxa_f32vec3 hit_value) {
    // prd.throughput = vec3(1.0);
    prd.seed = seed;
    prd.depth = max_depth;
    prd.world_hit = i.world_hit;
    prd.distance = i.distance;
    prd.world_nrm = i.world_nrm;
    prd.ray_scatter_dir = i.scatter_dir;
    prd.instance_hit = i.instance_hit;

    daxa_f32vec3 ray_origin = i.world_hit;
    daxa_f32vec3 ray_direction = i.scatter_dir;

    daxa_u32 ray_flags = gl_RayFlagsNoneEXT;
    daxa_f32 t_min = DELTA_RAY;
    daxa_f32 t_max = MAX_DISTANCE - DELTA_RAY;
    daxa_u32 cull_mask = 0xFF;

    for (;;)
    {

#if SER == 1

        HIT_INFO_INPUT hit = HIT_INFO_INPUT(
            i.world_hit,
            i.world_nrm,
            i.instance_hit,
            i.material_idx,
            seed,
            max_depth);

        if(i.is_hit) {
            Ray ray = Ray(ray_origin, ray_direction);
            
            daxa_u32 light_index = min(urnd_interval(prd.seed, 0, light_count), light_count - 1);

            LIGHT light = get_light_from_light_index(light_index);

            daxa_f32 pdf_out = 1.0;

            daxa_f32vec3 radiance = direct_mis(ray, hit, light_count, light, object_count, i.mat, i, pdf_out, true, true);

            prd.hit_value *= radiance;
            prd.hit_value += i.mat.emission;
        }
        else
        {
            prd.done = true;
            prd.hit_value *= calculate_sky_color(
                deref(p.status_buffer).time,
                deref(p.status_buffer).is_afternoon,
                ray_direction);
        }

#else
        traceRayEXT(daxa_accelerationStructureEXT(p.tlas),
                    ray_flags,     // rayFlags
                    cull_mask,     // cullMask
                    1,             // sbtRecordOffset
                    0,             // sbtRecordStride
                    0,             // missIndex
                    ray_origin,    // ray origin
                    t_min,         // ray min range
                    ray_direction, // ray direction
                    t_max,         // ray max range
                    0              // payload (location = 0)
        );
#endif // SER

        prd.depth--;
        if (prd.done == true || prd.depth == 0)
            break;

        ray_origin = prd.world_hit;
        ray_direction = prd.ray_scatter_dir;
        prd.done = true; // Will stop if a reflective material isn't hit
    }
    hit_value *= prd.hit_value;

}

#endif // INDIRECT_ILLUMINATION_GLSL