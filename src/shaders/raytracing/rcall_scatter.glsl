#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>
#include "defines.glsl"
#include "prng.glsl"
#include "primitives.glsl"

#if defined(METAL)
void main()
{
    MATERIAL mat = get_material_from_material_index(call_scatter.mat_idx);

    daxa_f32vec3 reflected = reflection(call_scatter.ray_dir, call_scatter.nrm);
    call_scatter.scatter_dir = reflected + min(mat.roughness, 1.0) * random_cosine_direction(call_scatter.seed);
    call_scatter.done = (dot(call_scatter.scatter_dir, call_scatter.nrm) > 0.0f) ? false : true;
}
#elif defined(DIELECTRIC)

void main()
{
    MATERIAL mat = get_material_from_material_index(call_scatter.mat_idx);

    daxa_f32vec3 original_nrm = call_scatter.nrm;

    daxa_f32 etai_over_etat = mat.ior;
    if (dot(call_scatter.ray_dir, call_scatter.nrm) > 0.0f) {
        call_scatter.nrm = -call_scatter.nrm;
        etai_over_etat = 1.0f / etai_over_etat;
    }

    daxa_f32 cos_theta = min(dot(-call_scatter.ray_dir, call_scatter.nrm), 1.0);
    daxa_f32 sin_theta = sqrt(1.0 - cos_theta*cos_theta);

    daxa_b32 cannot_refract = etai_over_etat * sin_theta > 1.0;

    if (cannot_refract || reflectance(cos_theta, etai_over_etat) > rnd(call_scatter.seed)) {
        call_scatter.scatter_dir = reflection(call_scatter.ray_dir, call_scatter.nrm);
    } else {
        call_scatter.scatter_dir = refraction(call_scatter.ray_dir, call_scatter.nrm, etai_over_etat);
        
        Ray ray;
        // ray.origin = call_scatter.hit - call_scatter.nrm * AVOID_VOXEL_COLLAIDE * 4.0f;
        ray.origin = call_scatter.hit + call_scatter.nrm * 0.0001 * 4.0f;
        ray.direction = call_scatter.scatter_dir;

        mat4 model = get_geometry_transform_from_instance_id(call_scatter.instance_id);
        mat4 inv_model = inverse(model);
        daxa_f32vec3 hit = vec3(0.0f);
        daxa_f32vec3 nrm = vec3(0.0f);
        daxa_f32 t_max = 0.0f;
        
        if(is_hit_from_ray(ray, call_scatter.instance_id, call_scatter.primitive_id, t_max, hit, nrm, model, inv_model, true, false)) {
            daxa_f32vec4 pos_4 = model * vec4(hit, 1);
            call_scatter.hit = pos_4.xyz / pos_4.w;
            call_scatter.hit += nrm * AVOID_VOXEL_COLLAIDE;
            call_scatter.nrm = (transpose(inv_model) * vec4(nrm, 0)).xyz;
        } 
    }
}

#elif defined(CONSTANT_MEDIUM)

void main()
{
    call_scatter.scatter_dir = random_unit_vector(call_scatter.seed);
    // Catch degenerate scatter direction
    if (normal_near_zero(call_scatter.scatter_dir))
        call_scatter.scatter_dir = call_scatter.nrm;
}

#else // Labertian

void main()
{
    call_scatter.scatter_dir = call_scatter.nrm + random_cosine_direction(call_scatter.seed);
    // Catch degenerate scatter direction
    if (normal_near_zero(call_scatter.scatter_dir))
        call_scatter.scatter_dir = call_scatter.nrm;
}

#endif // TEXTURES