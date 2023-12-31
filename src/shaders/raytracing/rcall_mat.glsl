#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>

#include "shared.inl"
#include "perlin.glsl"

DAXA_DECL_PUSH_CONSTANT(PushConstant, p)

layout(location = 3) callableDataInEXT HIT_MAT_PAY_LOAD hit_call;

#if defined(MATERIAL_TEXTURE)
void main()
{
    vec2 uv = vec2(0.0);
    vec4 texel = texture(daxa_sampler2D(hit_call.texture_id, hit_call.sampler_id), uv);
    hit_call.hit_value = texel.xyz;
}
#elif defined(PERLIN_TEXTURE)

void main()
{
    vec3 s = PERLIN_FACTOR * VOXEL_EXTENT * abs(hit_call.hit);
    float turbulence = get_perlin_turbulence(s, 4, 2.0, 0.5, hit_call.texture_id, hit_call.sampler_id);
    hit_call.hit_value = vec3(0.5 * (1 + sin(s.z + 10 * turbulence)));
}

#else // No texture

void main(){
    
}

#endif // TEXTURES