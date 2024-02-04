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
    prd.ray_scatter_dir = i.scatter_dir;
    prd.instance_hit = i.instance_hit;
    // prd.done = true;

    PATH_STATE path;
    generate_path(path, index, rt_size, i.instance_hit, Ray(i.world_hit, i.scatter_dir), seed);


    // TODO: Do something with path here for primary hit

    for (;;)
    {

        HIT_INFO_INPUT hit = HIT_INFO_INPUT(
            i.world_hit,
            i.world_nrm,
            i.distance,
            i.scatter_dir,
            i.instance_hit,
            i.material_idx,
            seed,
            max_depth);
        Ray ray = Ray(i.world_hit, i.scatter_dir);

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
        if (prd.done == true || prd.depth == 0)
            break;
            
        prd.done = true; // Will stop if a reflective material isn't hit
    }
    throughput += prd.hit_value;

}

#endif // INDIRECT_ILLUMINATION_GLSL