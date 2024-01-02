#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>

#include "shared.inl"
#include "prng.glsl"
#include "random.glsl"

DAXA_DECL_PUSH_CONSTANT(PushConstant, p)

layout(location = 0) rayPayloadEXT HIT_PAY_LOAD prd;

const uint NBSAMPLES = 1;

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
    uint seed = tea(gl_LaunchIDEXT.y * gl_LaunchSizeEXT.x + gl_LaunchIDEXT.x, frame_number * NBSAMPLES);
    prd.seed = seed;

    // Random number generator setup
    LCG lcg;
    daxa_u32 seedX = gl_LaunchIDEXT.x;
    daxa_u32 seedY = gl_LaunchIDEXT.y * gl_LaunchSizeEXT.x;
    initLCG(lcg, frame_number, seedX, seedY);
    // prd.seed = lcg.state;
    lcg.state = seed;
    

    // Depth of field setup
    daxa_f32 defocus_angle = deref(p.camera_buffer).defocus_angle;
    daxa_f32 focus_dist = deref(p.camera_buffer).focus_dist;

    daxa_f32 defocus_radius = focus_dist * tan(radians(defocus_angle / 2));
    daxa_f32vec2 defocus_disk = vec2(d.x * defocus_radius, 
        d.y * defocus_radius);

    
    // Ray setup
    Ray ray;

    daxa_f32vec4 origin = inv_view * vec4(0,0,0,1);
    ray.origin = (defocus_angle <= 0) ? origin.xyz : defocus_disk_sample(origin.xyz, defocus_disk, lcg);

	vec4 target = inv_proj * vec4(d.x, d.y, 1, 1) ;
	vec4 direction = inv_view * vec4(normalize(target.xyz), 0) ;

    ray.direction = direction.xyz;

    prd.depth = 0;
    prd.hit_value = vec3(0);
    prd.attenuation = vec3(1.f, 1.f, 1.f);
    prd.done = 1;
    prd.ray_origin = origin.xyz;
    prd.ray_dir = direction.xyz;

    daxa_u32 ray_flags = gl_RayFlagsNoneEXT;
    daxa_f32 t_min = 0.0001;
    daxa_f32 t_max = 10000.0;
    daxa_u32 cull_mask = 0xFF;

    vec3 hit_value = vec3(0);

    for(int smpl = 0; smpl < NBSAMPLES; smpl++)
    { 
        for(;;)
        {
            prd.emission = vec3(0);
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

            hit_value += prd.hit_value * prd.attenuation + prd.emission;

            prd.depth++;
            if(prd.done == 1 || prd.depth >= max_depth)
            break;

            ray.origin.xyz    = prd.ray_origin;
            ray.direction.xyz = prd.ray_dir;
            prd.done      = 1; // Will stop if a reflective material isn't hit
        }
    }
    hit_value = hit_value / NBSAMPLES;

    
    clamp(hit_value, 0.0, 0.99999999);

    imageStore(daxa_image2D(p.swapchain), index, daxa_f32vec4(hit_value, 1.0));
}