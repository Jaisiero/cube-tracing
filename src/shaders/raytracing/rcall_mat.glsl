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
    // vec2 half_extent = vec2(VOXEL_EXTENT) * 0.5;
    vec3 sgn = sign(hit_call.nrm);
    if (sgn.x != 0.0)
    {
        // -z and +z faces
        uv = vec2(hit_call.hit.z, hit_call.hit.y);
        // uv += half_extent;
    }
    else if (sgn.y != 0.0)
    {
        // -y and +y faces
        uv = vec2(hit_call.hit.x, hit_call.hit.z);
        // uv += half_extent;
    }
    else if (sgn.z != 0.0)
    {
        // -x and +x faces
        uv = vec2(hit_call.hit.x, hit_call.hit.y);
        // uv += half_extent;
    }

    // uv = uv / (VOXEL_EXTENT);

    vec4 texel = texture(daxa_sampler2D(hit_call.texture_id, hit_call.sampler_id), uv);
    hit_call.hit_value = texel.xyz;

    // hit_call.hit_value = vec3(0.0);
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