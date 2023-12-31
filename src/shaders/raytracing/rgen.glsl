#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>

#include "shared.inl"
#include "prng.glsl"

DAXA_DECL_PUSH_CONSTANT(PushConstant, p)

layout(location = 0) rayPayloadEXT HitPayLoad prd;

const uint NBSAMPLES = 1;

void main()
{
    const ivec2 index = ivec2(gl_LaunchIDEXT.xy);

    // // Color output
    // vec3 out_color = vec3(0.0, 0.0, 0.0);

    // Ray setup
    Ray ray;

    // Camera setup
    daxa_f32mat4x4 inv_view = deref(p.camera_buffer).inv_view;
    daxa_f32mat4x4 inv_proj = deref(p.camera_buffer).inv_proj;
    // daxa_f32 LOD_distance = deref(p.camera_buffer).LOD_distance;

    const daxa_f32vec2 pixel_center = vec2(index) + vec2(0.5);
    const daxa_f32vec2 inv_UV = pixel_center / vec2(gl_LaunchSizeEXT.xy);
    daxa_f32vec2 d = inv_UV * 2.0 - 1.0;
    
    // DEBUGGING
    // deref(p.hit_distance_buffer).hit_distances[index.x + index.y * p.size.x].distance = -1.0f;

    LCG lcg;
    daxa_u32 frame_number = deref(p.status_buffer).frame_number;
    daxa_u32 light_count = deref(p.status_buffer).light_count;
    daxa_u32 seedX = index.x;
    daxa_u32 seedY = index.y;

    initLCG(lcg, frame_number, seedX, seedY);

    daxa_f32 defocus_angle = deref(p.camera_buffer).defocus_angle;
    daxa_f32 focus_dist = deref(p.camera_buffer).focus_dist;

    daxa_f32 defocus_radius = focus_dist * tan(radians(defocus_angle / 2));
    daxa_f32vec2 defocus_disk = vec2(d.x * defocus_radius, 
        d.y * defocus_radius);

    daxa_f32vec4 origin = inv_view * vec4(0,0,0,1);
    ray.origin = (defocus_angle <= 0) ? origin.xyz : defocus_disk_sample(origin.xyz, defocus_disk, lcg);

	vec4 target = inv_proj * vec4(d.x, d.y, 1, 1) ;
	vec4 direction = inv_view * vec4(normalize(target.xyz), 0) ;

    ray.direction = direction.xyz;

    daxa_u32 ray_flags = gl_RayFlagsNoneEXT;
    daxa_f32 tMin = 0.0001;
    daxa_f32 tMax = 10000.0;

    traceRayEXT(
        daxa_accelerationStructureEXT(p.tlas),
        ray_flags,      // rayFlags
        0xFF,          // cullMask
        0,             // sbtRecordOffset
        0,             // sbtRecordStride
        0,             // missIndex
        origin.xyz,    // ray origin
        tMin,          // ray min range
        direction.xyz, // ray direction
        tMax,          // ray max range
        0              // payload (location = 0)
    );

    imageStore(daxa_image2D(p.swapchain), index, daxa_f32vec4(prd.hit_value, 1.0));
}