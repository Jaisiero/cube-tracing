#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#extension GL_EXT_ray_query : enable
#include <daxa/daxa.inl>
#include "motion_vectors.glsl"

#include "shared.inl"

layout(local_size_x = 8, local_size_y = 8) in;
void main()
{
    const daxa_i32vec2 index = ivec2(gl_GlobalInvocationID.xy);
    if (index.x >= p.size.x || index.y >= p.size.y)
    {
        return;
    }
    daxa_u32vec2 launch_size = gl_NumWorkGroups.xy * 8;

    // Camera setup
    daxa_f32mat4x4 inv_view = transpose(deref(p.camera_buffer).inv_view);
    daxa_f32mat4x4 inv_proj = transpose(deref(p.camera_buffer).inv_proj);
    
    daxa_f32mat4x4 prev_inv_view = transpose(deref(p.camera_buffer).prev_inv_view);
    daxa_f32mat4x4 prev_inv_proj = transpose(deref(p.camera_buffer).prev_inv_proj);

    // Find the UV coordinate of the current pixel
    daxa_f32vec2 uv = (daxa_f32vec2(index) + 0.5) / daxa_f32vec2(launch_size);

    // Find the world position of the current pixel
    daxa_f32vec4 prev_pos = prev_inv_proj * daxa_f32vec4(uv * 2.0 - 1.0, 1.0, 1.0);
    // Find the world position of the current pixel
    daxa_f32vec4 pos = inv_proj * daxa_f32vec4(uv * 2.0 - 1.0, 1.0, 1.0);

    if(prev_pos.w == 0.0 || pos.w == 0.0)
    {
        velocity_buffer_set_velocity(index, p.size, VELOCITY(daxa_f32vec2(0.0, 0.0)));
        return;
    }

    prev_pos /= prev_pos.w;
    prev_pos = prev_inv_view * prev_pos;
    prev_pos /= prev_pos.w;

    pos /= pos.w;
    pos = inv_view * pos;

    // Calculate the motion vector
    daxa_f32vec2 motion_vector = pos.xy - prev_pos.xy;

    // Store the motion vector
    // deref(p.velocity_buffer).velocities[index.y * p.size.x + index.x] = -motion_vector;
}