#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>

#include "defines.glsl"
#include "primitives.glsl"

// Ray-AABB intersection
float hitAabb(const Aabb aabb, const Ray r)
{
    vec3 invDir = 1.0 / r.direction;
    vec3 tbot = invDir * (aabb.minimum - r.origin);
    vec3 ttop = invDir * (aabb.maximum - r.origin);
    vec3 tmin = min(ttop, tbot);
    vec3 tmax = max(ttop, tbot);
    float t0 = max(tmin.x, max(tmin.y, tmin.z));
    float t1 = min(tmax.x, min(tmax.y, tmax.z));
    return t1 > max(t0, 0.0) ? t0 : -1.0;
}

void main()
{
    Ray ray;
    ray.origin = gl_WorldRayOriginEXT;
    ray.direction = gl_WorldRayDirectionEXT;

    daxa_f32 t_hit = -1.0;

    daxa_f32vec3 pos;
    daxa_f32vec3 nor;

    if(is_hit_from_ray(ray, gl_InstanceCustomIndexEXT, gl_PrimitiveID, t_hit, pos, nor, true, false) == false) {
        t_hit = -1.0;
    }

    // Report hit point
    if (t_hit > 0)
        reportIntersectionEXT(t_hit, 0); // 0 is the hit kind (hit group index)
}