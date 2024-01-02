#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>

#include "shared.inl"
#include "prng.glsl"

DAXA_DECL_PUSH_CONSTANT(PushConstant, p)

layout(location = 4) callableDataInEXT HIT_SCATTER_PAY_LOAD call_scatter;

#if defined(METAL)
void main()
{
    LCG lcg;
    InitLCGSetConstants(lcg);
    lcg.state = call_scatter.seed;

    MATERIAL mat = deref(p.materials_buffer).materials[call_scatter.mat_idx];

    daxa_f32vec3 reflected = reflection(call_scatter.ray_dir, call_scatter.nrm);
    call_scatter.scatter_dir = reflected + min(mat.roughness, 1.0) * random_cosine_direction(lcg);
    call_scatter.done = (dot(call_scatter.scatter_dir, call_scatter.nrm) > 0.0f) ? 0 : 1;
    
    call_scatter.seed = lcg.state;
}
#elif defined(DIELECTRIC)

void main()
{
    LCG lcg;
    InitLCGSetConstants(lcg);
    lcg.state = call_scatter.seed;
    
    MATERIAL mat = deref(p.materials_buffer).materials[call_scatter.mat_idx];

    daxa_f32 etai_over_etat = mat.ior;
    if (dot(call_scatter.ray_dir, call_scatter.nrm) > 0.0f) {
        call_scatter.nrm = -call_scatter.nrm;
        etai_over_etat = 1.0f / etai_over_etat;
    }

    daxa_f32 cos_theta = min(dot(-call_scatter.ray_dir, call_scatter.nrm), 1.0);
    daxa_f32 sin_theta = sqrt(1.0 - cos_theta*cos_theta);

    daxa_b32 cannot_refract = etai_over_etat * sin_theta > 1.0;

    if (cannot_refract || reflectance(cos_theta, etai_over_etat) > randomInRangeLCG(lcg, 0.0f, 1.0f))
        call_scatter.scatter_dir = reflection(call_scatter.ray_dir, call_scatter.nrm);
    else
        call_scatter.scatter_dir = refraction(call_scatter.ray_dir, call_scatter.nrm, etai_over_etat);
        
    call_scatter.seed = lcg.state;
}

#elif defined(CONSTANT_MEDIUM)

void main()
{
    LCG lcg;
    InitLCGSetConstants(lcg);
    lcg.state = call_scatter.seed;

    call_scatter.scatter_dir = random_unit_vector(lcg);
    // Catch degenerate scatter direction
    if (normal_near_zero(call_scatter.scatter_dir))
        call_scatter.scatter_dir = call_scatter.nrm;
        
    call_scatter.seed = lcg.state;
}

#else // Labertian

void main()
{
    LCG lcg;
    InitLCGSetConstants(lcg);
    lcg.state = call_scatter.seed;
    
    call_scatter.scatter_dir = call_scatter.nrm + random_cosine_direction(lcg);
    // Catch degenerate scatter direction
    if (normal_near_zero(call_scatter.scatter_dir))
        call_scatter.scatter_dir = call_scatter.nrm;

    call_scatter.seed = lcg.state;
}

#endif // TEXTURES