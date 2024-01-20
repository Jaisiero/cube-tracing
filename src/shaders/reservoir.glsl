#pragma once
#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>
#include "defines.glsl"

#include "shared.inl"
#include "prng.glsl"
#include "light.glsl"
#include "primitives.glsl"
#include "motion_vectors.glsl"

void initialise_reservoir(inout RESERVOIR reservoir)
{
    reservoir.W_y = 0.0;
    reservoir.W_sum = 0.0;
    reservoir.M = 0.0;
    reservoir.Y = 0;
}

daxa_b32 update_reservoir(inout RESERVOIR reservoir, daxa_u32 X, daxa_f32 w, daxa_f32 c, inout daxa_u32 seed)
{
    reservoir.W_sum += w;
    reservoir.M += c;

    if ( rnd(seed) < (w / reservoir.W_sum)  )
    {
        reservoir.Y = X;
        return true;
    }

    return false;
}

daxa_u32 get_reservoir_light_index(in RESERVOIR reservoir)
{
    return reservoir.Y;
}

daxa_b32 is_reservoir_valid(in RESERVOIR reservoir)
{
    return reservoir.M > 0.0;
}


daxa_f32 calculate_phat(Ray ray, inout HIT_INFO_INPUT hit, MATERIAL mat, daxa_u32 light_count, LIGHT light, daxa_f32 pdf, out daxa_f32 pdf_out, const in daxa_b32 calc_pdf, const in daxa_b32 use_pdf, const in daxa_b32 use_visibility) {
    return length(calculate_sampled_light(ray, hit, light, mat, light_count, pdf, pdf_out, calc_pdf, use_pdf, use_visibility));
}


    // Use the reservoir to calculate the final radiance.
void calculate_reservoir_radiance(inout RESERVOIR reservoir, Ray ray, inout HIT_INFO_INPUT hit, MATERIAL mat, daxa_u32 light_count, inout daxa_f32 p_hat){

    if (is_reservoir_valid(reservoir))
    {
        LIGHT light = deref(p.light_buffer).lights[get_reservoir_light_index(reservoir)];

        daxa_f32 pdf = 1.0;
        daxa_f32 pdf_out = 1.0;
        // calculate the radiance of this light
        p_hat = calculate_phat(ray, hit, mat, light_count, light, pdf, pdf_out, false, false, true);

        // calculate the weight of this light
        reservoir.W_y = p_hat > 0.0 ? (reservoir.W_sum / reservoir.M) / p_hat : 0.0;
    }
}


void calculate_reservoir_weight(inout RESERVOIR reservoir, Ray ray, inout HIT_INFO_INPUT hit, MATERIAL mat, daxa_u32 light_count, inout daxa_f32 p_hat){

    if (is_reservoir_valid(reservoir))
    {
        LIGHT light = deref(p.light_buffer).lights[get_reservoir_light_index(reservoir)];

        daxa_f32 pdf = 1.0;
        daxa_f32 pdf_out = 1.0;
        // calculate the radiance of this light
        p_hat = calculate_phat(ray, hit, mat, light_count, light, pdf, pdf_out, false, false, false);

        // calculate weight of the selected lights
        reservoir.W_y = p_hat > 0.0 ? (reservoir.W_sum / reservoir.M) / p_hat : 0.0;
    }
}


void calculate_reservoir_weight_aggregation(inout RESERVOIR reservoir, RESERVOIR aggregation_reservoir, Ray ray, inout HIT_INFO_INPUT hit, MATERIAL mat, daxa_u32 light_count, inout daxa_f32 p_hat){

    if (is_reservoir_valid(aggregation_reservoir))
    {
        LIGHT light = deref(p.light_buffer).lights[get_reservoir_light_index(aggregation_reservoir)];

        daxa_f32 pdf = 1.0;
        daxa_f32 pdf_out = 1.0;
        // calculate the radiance of this light
        p_hat = calculate_phat(ray, hit, mat, light_count, light, pdf, pdf_out, false, false, false);

        //add sample from previous frame
        update_reservoir(reservoir, get_reservoir_light_index(aggregation_reservoir), p_hat * aggregation_reservoir.W_y * aggregation_reservoir.M, aggregation_reservoir.M, prd.seed);
    }
}


RESERVOIR RIS(daxa_u32 light_count, Ray ray, inout HIT_INFO_INPUT hit, MATERIAL mat, daxa_f32 pdf, inout daxa_f32 p_hat){
    RESERVOIR reservoir;
    initialise_reservoir(reservoir);

    for(daxa_u32 l = 0; l < M; l++) {
        daxa_u32 light_index = min(urnd_interval(prd.seed, 0, light_count), light_count - 1);

        LIGHT light = deref(p.light_buffer).lights[light_index];
        
        daxa_f32 current_pdf = 1.0;
        p_hat = calculate_phat(ray, hit, mat, light_count, light, pdf, current_pdf, true, false, true);
        daxa_f32 w = p_hat / current_pdf;
        update_reservoir(reservoir, light_index, w, 1.0f, prd.seed);
    }

    calculate_reservoir_radiance(reservoir, ray, hit, mat, light_count, p_hat);
    
    return reservoir;
}



daxa_f32vec3 reservoir_direct_illumination(RESERVOIR reservoir, daxa_u32 light_count, daxa_u32 object_count, Ray ray, inout HIT_INFO_INPUT hit, daxa_u32 screen_pos, daxa_u32 current_mat_index, MATERIAL mat, daxa_f32mat4x4 instance_model) {
    
    daxa_f32 pdf = 1.0 / light_count;
    daxa_f32 pdf_out = 1.0;
    daxa_f32 p_hat = calculate_phat(ray, hit, mat, light_count, deref(p.light_buffer).lights[get_reservoir_light_index(reservoir)], pdf, pdf_out, false, false, false);

    // Previous frame screen coord
    daxa_u32vec2 predicted_coord = get_previous_frame_pixel_coord(gl_LaunchIDEXT.xy, hit.world_hit, gl_LaunchSizeEXT.xy, hit.instance_id,  instance_model);


#if RESERVOIR_TEMPORAL_ON == 1

    daxa_u32 prev_predicted_index = predicted_coord.x + predicted_coord.y * gl_LaunchSizeEXT.x;

    // Max screen pos
    daxa_u32 max_screen_pos = gl_LaunchSizeEXT.x * gl_LaunchSizeEXT.y - 1;

    // Clamp screen pos for 
    prev_predicted_index = min(max_screen_pos, prev_predicted_index);
    
    // Temporal reuse
    {

        RESERVOIR temporal_reservoir;
        initialise_reservoir(temporal_reservoir);

        DIRECT_ILLUMINATION_INFO di_info_previous = deref(p.previous_di_buffer).DI_info[prev_predicted_index];

        // Normal from previous frame
        daxa_f32vec3 normal_previous = di_info_previous.normal.xyz;

        // Depth from previous frame
        daxa_f32 depth_previous = di_info_previous.normal.w;

        //some simple rejection based on normals' divergence, can be improved
        bool valid_history = dot(normal_previous, hit.world_nrm) >= 0.99 && di_info_previous.instance_id == hit.instance_id && di_info_previous.primitive_id == hit.primitive_id;

        if (valid_history)
        {
            //add current reservoir sample
            update_reservoir(temporal_reservoir, get_reservoir_light_index(reservoir), p_hat * reservoir.W_y * reservoir.M, reservoir.M, prd.seed);

            // Reservoir from previous frame
            RESERVOIR reservoir_previous = deref(p.previous_reservoir_buffer).reservoirs[prev_predicted_index];

            // NOTE: restrict influence from past samples.
            reservoir_previous.M = min(INFLUENCE_FROM_THE_PAST_THRESHOLD * reservoir.M, reservoir_previous.M);

            //add sample from previous frame
            calculate_reservoir_weight_aggregation(temporal_reservoir, reservoir_previous, ray, hit, mat, light_count, p_hat);

            //calculate the weight of this light
            calculate_reservoir_weight(temporal_reservoir, ray, hit, mat, light_count, p_hat);

            reservoir = temporal_reservoir;
        }
    }
#endif // RESERVOIR_TEMPORAL_ON == 1

#if RESERVOIR_SPATIAL_ON == 1
    // daxa_u32 material_type = (mat.type & MATERIAL_TYPE_MASK);
    // Spacial reuse
    {
        RESERVOIR spatial_reservoir;
        initialise_reservoir(spatial_reservoir);

        //add previous samples
        calculate_reservoir_weight_aggregation(spatial_reservoir, reservoir, ray, hit, mat, light_count, p_hat);

        RESERVOIR neighbor_reservoir;

        daxa_f32 spatial_influence_threshold = max(1.0, (INFLUENCE_FROM_THE_PAST_THRESHOLD) / NUM_OF_NEIGHBORS);

        for (daxa_u32 i = 0; i < NUM_OF_NEIGHBORS; i++)
        {
            // Random offset
            daxa_f32vec2 offset = 2.0 * daxa_f32vec2(rnd(prd.seed), rnd(prd.seed)) - 1;

            // Scale offset
            offset.x = predicted_coord.x + int(offset.x * NEIGHBORS_RADIUS);
            offset.y = predicted_coord.y + int(offset.y * NEIGHBORS_RADIUS);

            // Clamp offset
            offset.x = min(gl_LaunchSizeEXT.x - 1, max(0, min(gl_LaunchSizeEXT.x - 1, offset.x)));
            offset.y = min(gl_LaunchSizeEXT.y - 1, max(0, min(gl_LaunchSizeEXT.y - 1, offset.y)));

            // Convert offset to u32
            daxa_u32vec2 offset_u32 = daxa_u32vec2(offset);

            // Convert offset to linear
            daxa_u32 offset_u32_linear = offset_u32.y * gl_LaunchSizeEXT.x + offset_u32.x;

            // TODO: Should depth buffer be used?
            // daxa_f32 neighbor_depth_linear = linearise_depth(deref(p.depth_buffer).depth[daxa_f32vec2(offset)].x);

            DIRECT_ILLUMINATION_INFO di_info_previous = deref(p.previous_di_buffer).DI_info[offset_u32_linear];

            daxa_f32 neighbor_hit_dist = di_info_previous.normal.w;

            daxa_u32 current_primitive_index = get_current_primitive_index_from_instance_and_primitive_id(di_info_previous.instance_id, di_info_previous.primitive_id);

            daxa_u32 neighbor_mat_index = get_material_index_from_primitive_index(current_primitive_index);

            // TODO: Adjust dist threshold dynamically
            if (
                // (neighbor_depth_linear > 1.1f * depth_linear || neighbor_depth_linear < 0.9f * depth_linear)   ||
                // abs(neighbor_hit_dist - gl_HitTEXT) > VOXEL_EXTENT ||
                neighbor_mat_index != current_mat_index ||
                dot(hit.world_nrm, di_info_previous.normal.xyz) < 0.906)
            {
                // skip this neighbour sample if not suitable
                continue;
            }

            neighbor_reservoir = deref(p.previous_reservoir_buffer).reservoirs[offset_u32_linear];
            // TODO: restrict influence from neighbor samples?
            neighbor_reservoir.M = min(spatial_influence_threshold, neighbor_reservoir.M);

            calculate_reservoir_weight_aggregation(spatial_reservoir, neighbor_reservoir, ray, hit, mat, light_count, p_hat);
        }

        calculate_reservoir_weight(spatial_reservoir, ray, hit, mat, light_count, p_hat);

        reservoir = spatial_reservoir;
    }
#endif // RESERVOIR_SPATIAL_ON == 1

    // Get the light from the reservoir
    LIGHT light = deref(p.light_buffer).lights[get_reservoir_light_index(reservoir)];
    
    // Add light radiance
    daxa_f32vec3 hit_value = calculate_sampled_light(ray, hit, light, mat, light_count, pdf, pdf_out, false, false, false) * reservoir.W_y;

    // Store the reservoir
    deref(p.reservoir_buffer).reservoirs[screen_pos] = reservoir;

    return hit_value;
}