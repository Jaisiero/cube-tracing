// prgn.glsl
#ifndef PRNG_GLSL
#define PRNG_GLSL
#include <daxa/daxa.inl>
#include "shared.inl"
#include "Box.glsl"
#include "random.glsl"

struct LCG {
    daxa_u32 state;
    daxa_u32 a;
    daxa_u32 c;
    daxa_u32 m;
};

// Credits: https://raytracing.github.io/books/RayTracingInOneWeekend.html#metal/modelinglightscatterandreflectance
daxa_b32 normal_near_zero(daxa_f32vec3 v)
{
    const daxa_f32 s = 1e-8;
    return (abs(v.x) < s) && (abs(v.y) < s) && (abs(v.z) < s);
}

daxa_f32 length_square(daxa_f32vec3 v) {
    return v.x * v.x + v.y * v.y + v.z * v.z;
}

daxa_i32 randomIntLCG(inout daxa_u32 seed) {
    return daxa_i32(urnd(seed));
}

daxa_i32 randomIntInRangeLCG(inout daxa_u32 seed, daxa_i32 min, daxa_i32 max) {
    daxa_i32 random_value = randomIntLCG(seed);
    return min + random_value % (max - min);
}

daxa_u32 randomUIntLCG(inout daxa_u32 seed) {
    return urnd(seed);
}

daxa_u32 randomUIntInRangeLCG(inout daxa_u32 seed, daxa_u32 min, daxa_u32 max) {
    daxa_u32 random_value = randomUIntLCG(seed);
    return min + random_value % (max - min);
}

daxa_f32 randomLCG(inout daxa_u32 seed) {
    return rnd(seed);
}

daxa_f32 randomInRangeLCG(inout daxa_u32 seed, daxa_f32 min, daxa_f32 max) {
    daxa_f32 random_value = rnd(seed);
    return min + random_value * (max - min);
}

daxa_f32vec3 randomVec3LCG(inout daxa_u32 seed) {
    return daxa_f32vec3(rnd(seed), rnd(seed), rnd(seed));
}

daxa_f32vec3 randomVec3InRangeLCG(inout daxa_u32 seed, daxa_f32 min, daxa_f32 max) {
    return daxa_f32vec3(randomInRangeLCG(seed, min, max), randomInRangeLCG(seed, min, max), randomInRangeLCG(seed, min, max));
}



daxa_f32vec3 random_in_unit_sphere(inout daxa_u32 seed) {
    while (true) {
        daxa_f32vec3 p = randomVec3InRangeLCG(seed, -1.0f, 1.0f);
        if (length_square(p) >= 1.0f) continue;
        return p;
    }
}

daxa_f32vec3 random_unit_vector(inout daxa_u32 seed) {
    return normalize(random_in_unit_sphere(seed));
}

daxa_f32vec3 random_on_hemisphere(inout daxa_u32 seed, daxa_f32vec3 normal) {
    daxa_f32vec3 on_unit_sphere = random_unit_vector(seed);
    if (dot(on_unit_sphere, normal) > 0.0) // In the same hemisphere as the normal
        return on_unit_sphere;
    else
        return -on_unit_sphere;
}

daxa_f32vec3 random_cosine_direction(inout uint seed) {
    daxa_f32 r1 = randomLCG(seed);
    daxa_f32 r2 = randomLCG(seed);
    daxa_f32 z = sqrt(1.0f - r2);

    daxa_f32 phi = 2.0f * DAXA_PI * r1;
    daxa_f32 x = cos(phi) * sqrt(r2);
    daxa_f32 y = sin(phi) * sqrt(r2);

    return daxa_f32vec3(x, y, z);
}

daxa_f32vec3 random_in_unit_disk(inout daxa_u32 seed) {
    while (true) {
        daxa_f32vec3 p = daxa_f32vec3(randomInRangeLCG(seed, -1.0f, 1.0f), randomInRangeLCG(seed, -1.0f, 1.0f), 0);
        if (length_square(p) < 1)
            return p;
    }
}

daxa_f32vec3 random_quad(daxa_f32vec3 normal, daxa_f32vec2 size, inout daxa_u32 seed) {
    // Generate a random point on a quad with normal n and size s
    daxa_f32vec3 quad_point = daxa_f32vec3(0, 0, 0);
    daxa_f32vec3 u = daxa_f32vec3(0, 0, 0);
    daxa_f32vec3 v = daxa_f32vec3(0, 0, 0);

    // Check front facing and back facing quads

    if (normal.x == 0 && normal.y == 0) {
        u = daxa_f32vec3(1, 0, 0);
        v = daxa_f32vec3(0, sign(normal.z), 0);
    }
    else if (normal.x == 0 && normal.z == 0) {
        u = daxa_f32vec3(1, 0, 0);
        v = daxa_f32vec3(0, 0, sign(normal.y));
    }
    else {
        u = daxa_f32vec3(0, 1, 0);
        v = daxa_f32vec3(sign(normal.x), 0, 0);
    }
    quad_point = quad_point.x * u * size.x + quad_point.y * v * size.y;
    
    return quad_point;


}


daxa_f32vec3 defocus_disk_sample(daxa_f32vec3 origin, daxa_f32vec2 defocus_disk, inout daxa_u32 seed) {
    // Returns a random point in the camera defocus disk.
    daxa_f32vec3 p = random_in_unit_disk(seed);
    return origin + (p.x * defocus_disk.x) + (p.y * defocus_disk.y);
}



daxa_f32vec3 reflection(daxa_f32vec3 v, daxa_f32vec3 n) {
    return v - 2*dot(v,n)*n;
}


daxa_f32 reflectance(daxa_f32 cosine, daxa_f32 ref_idx) {
    daxa_f32 r0 = (1.0f - ref_idx) / (1.0f + ref_idx);
    r0 = r0 * r0;
    return r0 + (1.0f - r0) * pow((1.0f - cosine), 5.0f);
}

daxa_f32vec3 refraction(daxa_f32vec3 uv, daxa_f32vec3 n, daxa_f32 etai_over_etat) {
    daxa_f32 cos_theta = min(dot(-uv, n), 1.0f);
    daxa_f32vec3 r_out_perp =  etai_over_etat * (uv + cos_theta*n);
    daxa_f32vec3 r_out_parallel = -sqrt(abs(1.0 - length_square(r_out_perp))) * n;
    return r_out_parallel + r_out_perp;
}



daxa_b32 scatter(MATERIAL m, daxa_f32vec3 direction, daxa_f32vec3 world_nrm, inout uint seed, out daxa_f32vec3 scatter_direction) {
    switch (m.type & MATERIAL_TYPE_MASK)
    {
    case MATERIAL_TYPE_METAL:
        daxa_f32vec3 reflected = reflection(direction, world_nrm);
        scatter_direction = reflected + min(m.roughness, 1.0) * random_cosine_direction(seed);
        return dot(scatter_direction, world_nrm) > 0.0f;
    case MATERIAL_TYPE_DIELECTRIC:
        daxa_f32 etai_over_etat = m.ior;
        if (dot(direction, world_nrm) > 0.0f) {
            world_nrm = -world_nrm;
            etai_over_etat = 1.0f / etai_over_etat;
        }

        daxa_f32 cos_theta = min(dot(-direction, world_nrm), 1.0);
        daxa_f32 sin_theta = sqrt(1.0 - cos_theta*cos_theta);

        daxa_b32 cannot_refract = etai_over_etat * sin_theta > 1.0;

        if (cannot_refract || reflectance(cos_theta, etai_over_etat) > randomInRangeLCG(seed, 0.0f, 1.0f))
            scatter_direction = reflection(direction, world_nrm);
        else
            scatter_direction = refraction(direction, world_nrm, etai_over_etat);
        return true;
    case MATERIAL_TYPE_CONSTANT_MEDIUM:
        scatter_direction = random_unit_vector(seed);
        // Catch degenerate scatter direction
        if (normal_near_zero(scatter_direction))
            scatter_direction = world_nrm;
        return true;
    case MATERIAL_TYPE_LAMBERTIAN:
    default:
        scatter_direction = world_nrm + random_cosine_direction(seed);
        // Catch degenerate scatter direction
        if (normal_near_zero(scatter_direction))
            scatter_direction = world_nrm;

        return true;
    }
    return false;
}

#endif // PRNG_GLSL