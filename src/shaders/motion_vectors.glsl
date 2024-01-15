#pragma once
#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>
#include "defines.glsl"


// credits: Ray Tracing gems 2, cp. 25.2  https://link.springer.com/content/pdf/10.1007/978-1-4842-7185-8.pdf

// NOTE: P = Mv Mmvp as the viewport Mv times the model-view-projection transformation Mmvp per frame

/**
 * @brief calculate the motion vector for a given pixel from the previous frame
 * 
 * @param world_hit The world position of the hit
 * @param Pi_1 prev frame P
 * @param geometry_T difference between the current and the previous frame geometry transformation
 * @return daxa_f32vec2 
 */
daxa_f32vec2 calculate_previous_frame_screen_space(daxa_f32vec3 world_hit, daxa_f32mat4x4 Pi_1, daxa_f32mat4x4 geometry_T) {

    // Prepare world hit for transformation
    daxa_f32vec4 S = daxa_f32vec4(world_hit, 1.0);

    // Apply geometry transformation & previous frame P
    daxa_f32vec4 prev_S = Pi_1 * geometry_T * S;

    // Calculate the previous screen position [-1, 1] clip space
    daxa_f32vec2 Xi_1 = prev_S.xy / prev_S.w;

    // To screen space normalized NDC [0, 1]
    Xi_1 = 0.5 * Xi_1 + 0.5;

    return Xi_1;
}


daxa_u32vec2 get_previous_frame_pixel_coord(daxa_u32vec2 current_pixel_coord, daxa_f32vec3 world_hit, daxa_u32vec2 rt_size, daxa_u32 instance_id, daxa_f32mat4x4 instance_model) {
    // X from current pixel position
    daxa_f32vec2 Xi = daxa_f32vec2(current_pixel_coord.xy) + 0.5;

    // Get the previous model matrix
    daxa_f32mat4x4 previous_model = get_geometry_previous_transform_from_instance_id(instance_id);

    // Get the camera matrices
    daxa_f32mat4x4 prev_inv_view = deref(p.camera_buffer).prev_inv_view;
    daxa_f32mat4x4 prev_inv_proj = deref(p.camera_buffer).prev_inv_proj;

    daxa_f32mat4x4 inv_prev_Mmvp = inverse(prev_inv_proj) * inverse(prev_inv_view);

    // Get T from the difference between the current and previous model matrices
    daxa_f32mat4x4 geometry_T = previous_model * inverse(instance_model);

    // Get the screen position array index
    daxa_u32 screen_pos = current_pixel_coord.x + current_pixel_coord.y * rt_size.x;

    // Calculate the motion vector
    daxa_f32vec2 Xi_1 = calculate_previous_frame_screen_space(world_hit, inv_prev_Mmvp, geometry_T);

    daxa_f32vec2 motion_vector = Xi_1 - Xi;

    VELOCITY velocity = VELOCITY(motion_vector);
    deref(p.velocity_buffer).velocities[screen_pos] = velocity;

    // Return the previous uvec2 view position
    return daxa_u32vec2(Xi_1 * daxa_f32vec2(rt_size.xy));
}