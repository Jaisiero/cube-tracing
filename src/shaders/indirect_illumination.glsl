// indirect_illumination.glsl
#ifndef INDIRECT_ILLUMINATION_GLSL
#define INDIRECT_ILLUMINATION_GLSL
#include <daxa/daxa.inl>
#include "shared.inl"
#include "path_state.glsl"
#include "path_tracer.glsl"



daxa_f32vec3 trace_hybrid_shift_rays(const SCENE_PARAMS params, const daxa_b32 use_preview, const INSTANCE_HIT primary_hit, const INTERSECT i, const PATH_RESERVOIR reservoir, out INSTANCE_HIT dst_rc_prev_vertex_hit, out daxa_f32vec3 dst_rc_prev_vertex_wo) {
    if(reservoir.weight == 0.0) return daxa_f32vec3(0.0);
    // TODO: calculate previus ray origin and direction?
    daxa_f32vec3 origin = i.world_hit + ((-i.wo) * i.distance);
    Ray ray = Ray(origin, i.wo);
    return trace_random_replay_path_hybrid_simple(params, primary_hit, i, ray, reservoir.path_flags, reservoir.init_random_seed, dst_rc_prev_vertex_hit, dst_rc_prev_vertex_wo);
}




void temporal_path_retrace(const SCENE_PARAMS params, PATH_RESERVOIR central_reservoir, out PATH_RESERVOIR temporal_reservoir, const daxa_i32vec2 index, const daxa_u32vec2 rt_size, daxa_u32 seed, const INSTANCE_HIT current_primary_hit, const INTERSECT current_intersection, daxa_u32 light_count, daxa_u32 object_count, inout daxa_f32vec3 throughput) {

    // Current index
    daxa_u32 current_index = index.y * rt_size.x + index.x;

    // Compute offset into per-sample buffers. All samples are stored consecutively at this offset.
    VELOCITY velocity = velocity_buffer_get_velocity(index, rt_size);

    // X from current pixel position
    daxa_f32vec2 Xi = daxa_f32vec2(index.xy) + 0.5;

    // X from previous pixel position
    daxa_f32vec2 Xi_1 = Xi + velocity.velocity;

    // Predicted coordinate
    daxa_u32vec2 predicted_coord = daxa_u32vec2(Xi_1);
    daxa_u32 prev_predicted_index = predicted_coord.y * rt_size.x + predicted_coord.x;

    // Get temporal reprojection primary hit
    DIRECT_ILLUMINATION_INFO di_info_previous = get_di_from_previous_frame(prev_predicted_index);

    INSTANCE_HIT temporal_first_hit = di_info_previous.instance_hit;

    MATERIAL previus_material = get_material_from_material_index(di_info_previous.mat_index);

    INTERSECT previous_intersection = INTERSECT(
        true,
        di_info_previous.distance,
        di_info_previous.position,
        di_info_previous.normal,
        daxa_f32vec3(0.0),
        di_info_previous.scatter_dir,
        di_info_previous.instance_hit,
        di_info_previous.mat_index,
        previus_material);

    // Get temporal reservoir
    temporal_reservoir = get_temporal_path_reservoir_by_index(prev_predicted_index);

    INSTANCE_HIT dst_rc_prev_vertex_hit;
    INSTANCE_HIT dst_rc_prev_vertex_hit2;
    daxa_f32vec3 dst_rc_prev_vertex_wo;
    daxa_f32vec3 dst_rc_prev_vertex_wo2;
    daxa_f32vec3 tp;
    daxa_f32vec3 tp2;

    // write to memory
    if (path_reservoir_get_reconnection_length(central_reservoir.path_flags) > 1)
    {
        tp = trace_hybrid_shift_rays(params, true, temporal_first_hit, previous_intersection, central_reservoir, dst_rc_prev_vertex_hit, dst_rc_prev_vertex_wo);
        set_reconnection_data_from_current_frame(current_index, 0, RECONNECTION_DATA(dst_rc_prev_vertex_hit, dst_rc_prev_vertex_wo, tp));
    }
    if (path_reservoir_get_reconnection_length(temporal_reservoir.path_flags) > 1)
    {
        tp2 = trace_hybrid_shift_rays(params, false, current_primary_hit, current_intersection, temporal_reservoir, dst_rc_prev_vertex_hit2, dst_rc_prev_vertex_wo2);
        set_reconnection_data_from_current_frame(current_index, 1, RECONNECTION_DATA(dst_rc_prev_vertex_hit2, dst_rc_prev_vertex_wo2, tp2));
    }

    // Set the current reservoir for next frame
    set_temporal_path_reservoir_by_index(current_index, central_reservoir);

    // Set the central reservoir for next pass
    set_output_path_reservoir_by_index(current_index, central_reservoir);
}





void indirect_illumination_restir_path_tracing(const daxa_i32vec2 index, const daxa_u32vec2 rt_size, Ray ray, INTERSECT i, daxa_u32 seed, daxa_u32 max_depth, daxa_u32 light_count, daxa_u32 object_count, inout daxa_f32vec3 throughput) {
    // TODO: check max_depth
    max_depth = max(1, max_depth);
    SCENE_PARAMS params = SCENE_PARAMS(light_count, object_count, max_depth);
    PATH_RESERVOIR central_reservoir;
    trace_restir_path_tracing(params, central_reservoir, index, rt_size, ray, i, seed, throughput);
    PATH_RESERVOIR temporal_reservoir;
    temporal_path_retrace(params, central_reservoir, temporal_reservoir, index, rt_size, seed, i.instance_hit, i, light_count, object_count, throughput);
}






void indirect_illumination_path_tracing(const daxa_i32vec2 index, const daxa_u32vec2 rt_size, Ray ray, MATERIAL mat, INTERSECT i, daxa_u32 seed, daxa_u32 max_depth, daxa_u32 light_count, daxa_u32 object_count, inout daxa_f32vec3 throughput) {
    
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

    generate_scatter_ray(i, seed);

    for (;;)
    {

        HIT_INFO_INPUT hit = HIT_INFO_INPUT(
            i.world_hit,
            i.world_nrm,
            i.distance,
            i.wo,
            i.instance_hit,
            i.material_idx,
            seed,
            max_depth);
        Ray scattered_ray = Ray(i.world_hit, i.wo);

        if(i.is_hit) {
            
            daxa_u32 light_index = min(urnd_interval(prd.seed, 0, light_count), light_count - 1);

            LIGHT light = get_light_from_light_index(light_index);

            daxa_f32 pdf_out = 1.0;

            daxa_f32vec3 radiance = direct_mis(scattered_ray, hit, light_count, light, object_count, i.mat, i, pdf_out, true, true);

            prd.hit_value *= radiance;
            prd.hit_value += i.mat.emission;
            prd.done = false;
        }
        else
        {
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
    throughput = prd.hit_value;

}





void indirect_illumination(const daxa_i32vec2 index, const daxa_u32vec2 rt_size, Ray ray, MATERIAL mat, INTERSECT i, daxa_u32 seed, daxa_u32 max_depth, daxa_u32 light_count, daxa_u32 object_count, inout daxa_f32vec3 throughput) {
#if RESTIR_PT_ON == 1
    indirect_illumination_restir_path_tracing(index, rt_size, ray, i, seed, max_depth, light_count, object_count, throughput);
#else
    indirect_illumination_path_tracing(index, rt_size, ray, mat, i, seed, max_depth, light_count, object_count, throughput);
#endif
}
#endif // INDIRECT_ILLUMINATION_GLSL