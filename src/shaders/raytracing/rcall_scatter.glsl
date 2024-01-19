#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>
#include "defines.glsl"
#include "prng.glsl"
#include "primitives.glsl"

#if defined(METAL)
void main()
{
    MATERIAL mat = deref(p.materials_buffer).materials[call_scatter.mat_idx];

    daxa_f32vec3 reflected = reflection(call_scatter.ray_dir, call_scatter.nrm);
    call_scatter.scatter_dir = reflected + min(mat.roughness, 1.0) * random_cosine_direction(call_scatter.seed);
    call_scatter.done = (dot(call_scatter.scatter_dir, call_scatter.nrm) > 0.0f) ? 0 : 1;
}
#elif defined(DIELECTRIC)

void main()
{
    MATERIAL mat = deref(p.materials_buffer).materials[call_scatter.mat_idx];

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

        daxa_u32 actual_primitive_index = get_current_primitive_index_from_instance_and_primitive_id(call_scatter.instance_id, call_scatter.primitive_id);
        
        Ray ray;
        ray.origin = call_scatter.hit + call_scatter.scatter_dir * AVOID_VOXEL_COLLAIDE;
        ray.direction = call_scatter.scatter_dir;

        mat4 model = get_geometry_transform_from_instance_id(call_scatter.instance_id);
        mat4 inv_model = inverse(model);

        ray.origin = (inv_model * vec4(ray.origin, 1)).xyz;
        ray.direction = (inv_model * vec4(ray.direction, 0)).xyz;

        Aabb aabb = deref(p.aabb_buffer).aabbs[actual_primitive_index];

        daxa_f32vec3 aabb_center = (aabb.minimum + aabb.maximum) * 0.5;

        // TODO: pass this as a parameter
        daxa_f32vec3 half_extent = vec3(VOXEL_EXTENT * 0.5);

        Box box = Box(aabb_center, half_extent, safeInverse(half_extent), mat3(model));

        daxa_f32 t_max = 0.0f;
        daxa_f32vec3 normal = vec3(0.0f);
        

        if(intersect_box(box, ray, t_max, normal, true, false, safeInverse(ray.direction))){
            call_scatter.hit = ray.origin + ray.direction * t_max + normal * AVOID_VOXEL_COLLAIDE;
            call_scatter.nrm = normal;
        } else {
            call_scatter.scatter_dir = reflection(call_scatter.ray_dir, call_scatter.nrm);
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