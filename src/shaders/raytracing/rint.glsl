#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>

#include "defines.glsl"
#include "primitives.glsl"

void main()
{
    Ray ray;
    ray.origin = gl_WorldRayOriginEXT;
    ray.direction = gl_WorldRayDirectionEXT;

    daxa_f32 t_hit = -1.0;

    daxa_f32vec3 pos;
    daxa_f32vec3 nor;
    daxa_f32mat4x4 model;
    daxa_f32mat4x4 inv_model;

    INSTANCE_HIT instance_hit = INSTANCE_HIT(gl_InstanceCustomIndexEXT, gl_PrimitiveID);

    t_hit = is_hit_from_ray(ray, instance_hit, t_hit, pos, nor, model, inv_model, true, false) ? t_hit : -1.0;
        

    // Report hit point
    if (t_hit > 0)
        reportIntersectionEXT(t_hit, 0); // 0 is the hit kind (hit group index)
}