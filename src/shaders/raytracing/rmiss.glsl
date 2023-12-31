#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>

#include "shared.inl"
#include "mat.glsl"

DAXA_DECL_PUSH_CONSTANT(PushConstant, p)

#if defined(MISS_SHADOW)

layout(location = 1) rayPayloadInEXT bool isShadowed;

void main()
{
    isShadowed = false;
}

#else

layout(location = 0) rayPayloadInEXT HIT_PAY_LOAD prd;

void main()
{
    prd.hit_value *= calculate_sky_color(
                    deref(p.status_buffer).time, 
                    deref(p.status_buffer).is_afternoon,
                    gl_WorldRayDirectionEXT);
}

#endif // MISS_SHADOW