#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>

#include "shared.inl"
#include "defines.glsl"
#include "prng.glsl"

#if SER_ON == 1
#extension GL_NV_shader_invocation_reorder : enable
layout(location = 0) hitObjectAttributeNV vec3 hitValue;
#endif

#if RESTIR_PREPASS_ON == 1

void main()
{
    const ivec2 index = ivec2(gl_LaunchIDEXT.xy);
    daxa_u32 max_depth = deref(p.status_buffer).max_depth;
    daxa_u32 frame_number = deref(p.status_buffer).frame_number;

    // Camera setup
    daxa_f32mat4x4 inv_view = deref(p.camera_buffer).inv_view;
    daxa_f32mat4x4 inv_proj = deref(p.camera_buffer).inv_proj;
    // daxa_f32 LOD_distance = deref(p.camera_buffer).LOD_distance;

    const daxa_f32vec2 pixel_center = vec2(index) + vec2(0.5);
    const daxa_f32vec2 inv_UV = pixel_center / vec2(gl_LaunchSizeEXT.xy);
    daxa_f32vec2 d = inv_UV * 2.0 - 1.0;
    
    // // DEBUGGING
    // // deref(p.hit_distance_buffer).hit_distances[index.x + index.y * p.size.x].distance = -1.0f;
    
    // // Initialize the random number
    // uint seed = tea(gl_LaunchIDEXT.y * gl_LaunchSizeEXT.x + gl_LaunchIDEXT.x, frame_number * SAMPLES_PER_PIXEL);

    // // Depth of field setup
    // daxa_f32 defocus_angle = deref(p.camera_buffer).defocus_angle;
    // daxa_f32 focus_dist = deref(p.camera_buffer).focus_dist;

    // daxa_f32 defocus_radius = focus_dist * tan(radians(defocus_angle / 2));
    // daxa_f32vec2 defocus_disk = vec2(d.x * defocus_radius, 
    //     d.y * defocus_radius);

    
    // Ray setup
    Ray ray;

    daxa_f32vec4 origin = inv_view * vec4(0,0,0,1);
    // ray.origin = (defocus_angle <= 0) ? origin.xyz : defocus_disk_sample(origin.xyz, defocus_disk, seed);
    ray.origin = origin.xyz;

	vec4 target = inv_proj * vec4(d.x, d.y, 1, 1) ;
	vec4 direction = inv_view * vec4(normalize(target.xyz), 0) ;

    ray.direction = direction.xyz;

    daxa_u32 ray_flags = gl_RayFlagsNoneEXT;
    daxa_f32 t_min = 0.0001;
    daxa_f32 t_max = 10000.0;
    daxa_u32 cull_mask = 0xFF;

    vec3 hit_value = vec3(0);

    traceRayEXT(
        daxa_accelerationStructureEXT(p.tlas),
        ray_flags,         // rayFlags
        cull_mask,         // cullMask
        0,                 // sbtRecordOffset
        0,                 // sbtRecordStride
        0,                 // missIndex
        ray.origin.xyz,    // ray origin
        t_min,             // ray min range
        ray.direction.xyz, // ray direction
        t_max,             // ray max range
        0                  // payload (location = 0)
    );

    hit_value += prd.hit_value;
}

#else

#define ACCUMULATOR_ON 0

void main()
{
    const ivec2 index = ivec2(gl_LaunchIDEXT.xy);
    daxa_u32 max_depth = deref(p.status_buffer).max_depth;
    daxa_u32 frame_number = deref(p.status_buffer).frame_number;

    // Camera setup
    daxa_f32mat4x4 inv_view = deref(p.camera_buffer).inv_view;
    daxa_f32mat4x4 inv_proj = deref(p.camera_buffer).inv_proj;
    // daxa_f32 LOD_distance = deref(p.camera_buffer).LOD_distance;

    const daxa_f32vec2 pixel_center = vec2(index) + vec2(0.5);
    const daxa_f32vec2 inv_UV = pixel_center / vec2(gl_LaunchSizeEXT.xy);
    daxa_f32vec2 d = inv_UV * 2.0 - 1.0;
    
    // DEBUGGING
    // deref(p.hit_distance_buffer).hit_distances[index.x + index.y * p.size.x].distance = -1.0f;
    
    // Initialize the random number
    uint seed = tea(gl_LaunchIDEXT.y * gl_LaunchSizeEXT.x + gl_LaunchIDEXT.x, frame_number * SAMPLES_PER_PIXEL);

    // Depth of field setup
    daxa_f32 defocus_angle = deref(p.camera_buffer).defocus_angle;
    daxa_f32 focus_dist = deref(p.camera_buffer).focus_dist;

    daxa_f32 defocus_radius = focus_dist * tan(radians(defocus_angle / 2));
    daxa_f32vec2 defocus_disk = vec2(d.x * defocus_radius, 
        d.y * defocus_radius);

    
    // Ray setup
    Ray ray;

    daxa_f32vec4 origin = inv_view * vec4(0,0,0,1);
    ray.origin = (defocus_angle <= 0) ? origin.xyz : defocus_disk_sample(origin.xyz, defocus_disk, seed);

	vec4 target = inv_proj * vec4(d.x, d.y, 1, 1) ;
	vec4 direction = inv_view * vec4(normalize(target.xyz), 0) ;

    ray.direction = direction.xyz;

    prd.seed = seed;
    prd.depth = max_depth;
    prd.hit_value = vec3(1.0);

    daxa_u32 ray_flags = gl_RayFlagsNoneEXT;
    daxa_f32 t_min = 0.0001;
    daxa_f32 t_max = 10000.0;
    daxa_u32 cull_mask = 0xFF;

    vec3 hit_value = vec3(0);

    for(int smpl = 0; smpl < SAMPLES_PER_PIXEL; smpl++)
    { 
        traceRayEXT(
            daxa_accelerationStructureEXT(p.tlas),
            ray_flags,      // rayFlags
            cull_mask,          // cullMask
            0,             // sbtRecordOffset
            0,             // sbtRecordStride
            0,             // missIndex
            ray.origin.xyz,    // ray origin
            t_min,          // ray min range
            ray.direction.xyz, // ray direction
            t_max,          // ray max range
            0              // payload (location = 0)
        );

        hit_value += prd.hit_value;
    }
    hit_value /= SAMPLES_PER_PIXEL;

    
    clamp(hit_value, 0.0, 0.99999999);

    vec4 final_pixel;
#if ACCUMULATOR_ON == 1
    daxa_u32 num_accumulated_frames = deref(p.status_buffer).num_accumulated_frames;
    if(num_accumulated_frames > 0) {
        vec4 previous_frame_pixel = imageLoad(daxa_image2D(p.swapchain), index);
        
        vec4 current_frame_pixel = vec4(hit_value, 1.0f);

        daxa_f32 weight = 1.0f / (num_accumulated_frames + 1.0f);
        final_pixel = mix(previous_frame_pixel, current_frame_pixel, weight);
    } else {
        final_pixel = vec4(hit_value, 1.0f);
    }
#else 
    final_pixel = vec4(hit_value, 1.0f);
#endif

    // 

    // NOTE: We are not using gamma correction because we suspect that swapchain is already in sRGB    
    // imageStore(daxa_image2D(p.swapchain), index, fromLinear(vec4(out_color,1)));
    // imageStore(daxa_image2D(p.swapchain), index, linear_to_ gamma(vec4(out_color,1)));
    imageStore(daxa_image2D(p.swapchain), index, final_pixel);

}

#endif // RESTIR_PREPASS_ON