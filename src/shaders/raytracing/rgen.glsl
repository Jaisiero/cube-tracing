#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>

#include "shared.inl"
#include "defines.glsl"
#include "prng.glsl"

#if SER == 1
#extension GL_NV_shader_invocation_reorder : enable
layout(location = 0) hitObjectAttributeNV vec3 hitValue;
#else
#extension GL_EXT_ray_query : enable
#endif

Ray get_ray_from_current_pixel(daxa_i32vec2 index, daxa_f32vec2 rt_size, daxa_f32mat4x4 inv_view, daxa_f32mat4x4 inv_proj) {
    const daxa_f32vec2 pixel_center = vec2(index) + vec2(0.5);
    const daxa_f32vec2 inv_UV = pixel_center / vec2(rt_size);
    daxa_f32vec2 d = inv_UV * 2.0 - 1.0;
    
    // Ray setup
    Ray ray;

    daxa_f32vec4 origin = inv_view * vec4(0,0,0,1);
    ray.origin = origin.xyz;

    vec4 target = inv_proj * vec4(d.x, d.y, 1, 1) ;
    vec4 direction = inv_view * vec4(normalize(target.xyz), 0) ;

    ray.direction = direction.xyz;

    return ray;
}

#if RESTIR_PREPASS == 1

void main()
{
    const ivec2 index = ivec2(gl_LaunchIDEXT.xy);

    // Camera setup
    daxa_f32mat4x4 inv_view = deref(p.camera_buffer).inv_view;
    daxa_f32mat4x4 inv_proj = deref(p.camera_buffer).inv_proj;

    Ray ray = get_ray_from_current_pixel(index, vec2(gl_LaunchSizeEXT.xy), inv_view, inv_proj);
    
    daxa_u32 max_depth = deref(p.status_buffer).max_depth;
    daxa_u32 frame_number = deref(p.status_buffer).frame_number;

    prd.seed = tea(gl_LaunchIDEXT.y * gl_LaunchSizeEXT.x + gl_LaunchIDEXT.x, frame_number * SAMPLES_PER_PIXEL);
    prd.depth = max_depth;

    daxa_u32 ray_flags = gl_RayFlagsNoneEXT;
    daxa_f32 t_min = 0.0001;
    daxa_f32 t_max = 10000.0;
    daxa_u32 cull_mask = 0xFF;


#if SER == 1
    hitObjectNV hitObject;
    //Initialize to an empty hit object
    hitObjectRecordEmptyNV(hitObject);

    // Trace the ray
    hitObjectTraceRayNV(hitObject,
                        daxa_accelerationStructureEXT(p.tlas), // topLevelAccelerationStructure
                        rayFlags,      // rayFlags
                        cullMask,      // cullMask
                        0,             // sbtRecordOffset
                        0,             // sbtRecordStride
                        0,             // missIndex
                        origin.xyz,    // ray origin
                        tMin,          // ray min range
                        direction.xyz, // ray direction
                        tMax,          // ray max range
                        0              // payload (location = 0)
    );


    daxa_u32 instance_id = MAX_PRIMITIVES;
    
    if(hitObjectIsHitNV(hitObject))
    { 
        instance_id = hitObjectGetInstanceCustomIndexNV(hitObject);
    }

#else
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
#endif // SER
}



#elif FIRST_VISIBILITY_PASS == 1
void main() {

    

    RESERVOIR reservoir = RIS(light_count, ray, hit, mat, pdf, p_hat);

    // Store the reservoir
    deref(p.reservoir_buffer).reservoirs[screen_pos] = reservoir;


    DIRECT_ILLUMINATION_INFO di_info = DIRECT_ILLUMINATION_INFO(hit.world_hit, daxa_f32vec4(hit.world_nrm, t_hit), instance_id, primitive_id);

    // Store normal
    deref(p.di_buffer).DI_info[screen_pos] = di_info;

}

#elif TEMPORAL_REUSE_PASS == 1

void main() {

}

#elif SECOND_VISIBILITY_PASS == 1
void main() {

}

#elif SPATIAL_REUSE_PASS == 1
void main() {

}

#elif THRID_VISIBILITY_AND_SHADING_PASS == 1

void main()
{
}

#else

#define ACCUMULATOR 0

void main()
{
    
    const ivec2 index = ivec2(gl_LaunchIDEXT.xy);

    // Camera setup
    daxa_f32mat4x4 inv_view = deref(p.camera_buffer).inv_view;
    daxa_f32mat4x4 inv_proj = deref(p.camera_buffer).inv_proj;

    Ray ray = get_ray_from_current_pixel(index, vec2(gl_LaunchSizeEXT.xy), inv_view, inv_proj);
    
    daxa_u32 max_depth = deref(p.status_buffer).max_depth;
    daxa_u32 frame_number = deref(p.status_buffer).frame_number;

    prd.seed = tea(gl_LaunchIDEXT.y * gl_LaunchSizeEXT.x + gl_LaunchIDEXT.x, frame_number * SAMPLES_PER_PIXEL);
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
#if ACCUMULATOR == 1
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

// #else

// void main()
// {
// }

#endif // RESTIR_PREPASS