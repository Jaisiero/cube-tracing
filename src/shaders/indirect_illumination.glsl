// indirect_illumination.glsl
#ifndef INDIRECT_ILLUMINATION_GLSL
#define INDIRECT_ILLUMINATION_GLSL
#include <daxa/daxa.inl>
#include "shared.inl"
#include "primitives.glsl"
#include "light.glsl"
#include "path_state.glsl"
#extension GL_EXT_ray_query : enable

void indirect_illumination(const daxa_i32vec2 index, const daxa_u32vec2 rt_size, INTERSECT i, daxa_u32 seed, daxa_u32 max_depth, daxa_u32 light_count, daxa_u32 object_count, inout daxa_f32vec3 throughput) {
    
    // prd.throughput = vec3(1.0);
    prd.seed = seed;
    prd.depth = max_depth;
    prd.world_hit = i.world_hit;
    prd.distance = i.distance;
    prd.world_nrm = i.world_nrm;
    prd.ray_scatter_dir = i.wi;
    prd.mat_index = i.material_idx;
    prd.instance_hit = i.instance_hit;
    // prd.done = true;

#if RESERVOIR_ON == 1
    call_scatter.hit = prd.world_hit;
    call_scatter.nrm = prd.world_nrm;
    call_scatter.ray_dir = i.wi;
    call_scatter.seed = prd.seed;
    call_scatter.scatter_dir = vec3(0.0);
    call_scatter.done = false;
    call_scatter.mat_idx = prd.mat_index;
    call_scatter.instance_hit = i.instance_hit;


    daxa_u32 mat_type = prd.mat_index & MATERIAL_TYPE_MASK;

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
    prd.seed = call_scatter.seed;
    prd.world_hit = call_scatter.hit;
    prd.world_nrm = call_scatter.nrm;
    prd.ray_scatter_dir = call_scatter.scatter_dir;
#endif // RESERVOIR_ON

    PATH_STATE path;
    generate_path(path, index, rt_size, i.instance_hit, Ray(i.world_hit, i.wi), seed);


    // TODO: Do something with path here for primary hit

    for (;;)
    {

        HIT_INFO_INPUT hit = HIT_INFO_INPUT(
            i.world_hit,
            i.world_nrm,
            i.distance,
            i.wi,
            i.instance_hit,
            i.material_idx,
            seed,
            max_depth);
        Ray ray = Ray(i.world_hit, i.wi);

        if(i.is_hit) {
            
            daxa_u32 light_index = min(urnd_interval(prd.seed, 0, light_count), light_count - 1);

            LIGHT light = get_light_from_light_index(light_index);

            daxa_f32 pdf_out = 1.0;

            // TODO: Handle hit path here for subsequent hits

            daxa_f32vec3 radiance = direct_mis(ray, hit, light_count, light, object_count, i.mat, i, pdf_out, true, true);

            prd.hit_value *= radiance;
            prd.hit_value += i.mat.emission;
            prd.done = false;
        }
        else
        {
            // TODO: Handle miss path here for subsequent hits

            prd.done = true;
            prd.hit_value *= calculate_sky_color(
                deref(p.status_buffer).time,
                deref(p.status_buffer).is_afternoon,
                ray.direction);
        }

        prd.depth--;
        daxa_b32 done = prd.done || prd.depth == 0;
// #if SER == 1
//     reorderThreadNV(daxa_u32(done), 1);
// #endif // SER
        if (done)
            break;
            
        prd.done = true; // Will stop if a reflective material isn't hit
    }
    throughput += prd.hit_value;

}

#endif // INDIRECT_ILLUMINATION_GLSL