#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>

#include "shared.inl"

DAXA_DECL_PUSH_CONSTANT(PushConstant, p)

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
    ray.origin = gl_ObjectRayOriginEXT;
    ray.direction = gl_ObjectRayDirectionEXT;

    mat4 inv_model = mat4(
        gl_ObjectToWorld3x4EXT[0][0], gl_ObjectToWorld3x4EXT[0][1], gl_ObjectToWorld3x4EXT[0][2], gl_ObjectToWorld3x4EXT[0][3],
        gl_ObjectToWorld3x4EXT[0][1], gl_ObjectToWorld3x4EXT[1][1], gl_ObjectToWorld3x4EXT[1][2], gl_ObjectToWorld3x4EXT[1][3],
        gl_ObjectToWorld3x4EXT[2][0], gl_ObjectToWorld3x4EXT[2][1], gl_ObjectToWorld3x4EXT[2][2], gl_ObjectToWorld3x4EXT[2][3],
        0, 0, 0, 1.0);

    ray.origin = (inv_model * vec4(ray.origin, 1)).xyz;
    ray.direction = (inv_model * vec4(ray.direction, 0)).xyz;

    float tHit = -1;

    // Get first primitive index from instance id
    uint primitive_index = deref(p.instance_buffer).instances[gl_InstanceCustomIndexEXT].first_primitive_index;
    // Get actual primitive index from offset and primitive id
    uint actual_primitive_index = primitive_index + gl_PrimitiveID;

    Aabb aabb = deref(p.aabb_buffer).aabbs[actual_primitive_index];

    tHit = hitAabb(aabb, ray);

    // Report hit point
    if (tHit > 0)
        reportIntersectionEXT(tHit, 0); // 0 is the hit kind (hit group index)
}