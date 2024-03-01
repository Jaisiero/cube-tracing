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

    daxa_f32mat4x3 model4x3 = gl_ObjectToWorldEXT;

    // Get model matrix
    daxa_f32mat4x4 model = mat4(
        model4x3[0][0], model4x3[0][1], model4x3[0][2], 0,
        model4x3[0][1], model4x3[1][1], model4x3[1][2], 0,
        model4x3[2][0], model4x3[2][1], model4x3[2][2], 0,
        model4x3[3][0], model4x3[3][1], model4x3[3][2], 1.0);
        
    daxa_f32mat4x4 inv_model = inverse(model);

    daxa_f32 t_hit = -1.0;

    daxa_f32vec3 pos;
    daxa_f32vec3 nor;

    OBJECT_INFO instance_hit = OBJECT_INFO(gl_InstanceCustomIndexEXT, gl_PrimitiveID);

    // TODO: pass this as a parameter
    daxa_f32vec3 half_extent = daxa_f32vec3(HALF_VOXEL_EXTENT);

    t_hit = is_hit_from_ray_providing_model(ray, instance_hit, half_extent, t_hit, pos, nor, model, inv_model, true, true) ? t_hit : -1.0;

    // Report hit point
    if (t_hit > 0)
        reportIntersectionEXT(t_hit, 0); // 0 is the hit kind (hit group index)
}