// prgn.glsl
#include <daxa/daxa.inl>
#include "shared.inl"

// Credits: https://raytracing.github.io/books/RayTracingInOneWeekend.html#metal/modelinglightscatterandreflectance
daxa_b32 normal_near_zero(daxa_f32vec3 v)
{
    const daxa_f32 s = 1e-8;
    return (abs(v.x) < s) && (abs(v.y) < s) && (abs(v.z) < s);
}

daxa_f32 length_square(daxa_f32vec3 v) {
    return v.x * v.x + v.y * v.y + v.z * v.z;
}

struct LCG {
    daxa_u32 state;
    daxa_u32 a;
    daxa_u32 c;
    daxa_u32 m;
};

void initLCG(inout LCG lcg, daxa_u32 frame_number, daxa_u32 seed_x, daxa_u32 seed_y) {
    lcg.a = 1664525;
    lcg.c = 1013904223;
    lcg.m = 4294967295;  // 2^32 - 1
    lcg.state = frame_number + seed_x * 73856093 + seed_y * 19349663;
}

daxa_f32 randomLCG(inout LCG lcg) {
    lcg.state = (lcg.a * lcg.state + lcg.c) % lcg.m;
    return daxa_f32(lcg.state) / daxa_f32(lcg.m);
}

daxa_f32 randomInRangeLCG(inout LCG lcg, daxa_f32 min, daxa_f32 max) {
    daxa_f32 random_value = randomLCG(lcg);
    return min + random_value * (max - min);
}

daxa_f32vec3 randomVec3LCG(inout LCG lcg) {
    return daxa_f32vec3(randomLCG(lcg), randomLCG(lcg), randomLCG(lcg));
}

daxa_f32vec3 randomVec3InRangeLCG(inout LCG lcg, daxa_f32 min, daxa_f32 max) {
    return daxa_f32vec3(randomInRangeLCG(lcg, min, max), randomInRangeLCG(lcg, min, max), randomInRangeLCG(lcg, min, max));
}



daxa_f32vec3 random_in_unit_sphere(LCG lcg) {
    while (true) {
        daxa_f32vec3 p = randomVec3InRangeLCG(lcg, -1.0f, 1.0f);
        if (length_square(p) >= 1.0f) continue;
        return p;
    }
}

daxa_f32vec3 random_unit_vector(LCG lcg) {
    return normalize(random_in_unit_sphere(lcg));
}

daxa_f32vec3 random_on_hemisphere(LCG lcg, daxa_f32vec3 normal) {
    daxa_f32vec3 on_unit_sphere = random_unit_vector(lcg);
    if (dot(on_unit_sphere, normal) > 0.0) // In the same hemisphere as the normal
        return on_unit_sphere;
    else
        return -on_unit_sphere;
}


daxa_f32vec3 reflection(daxa_f32vec3 v, daxa_f32vec3 n) {
    return v - 2*dot(v,n)*n;
}


// daxa_f32 schlick(daxa_f32 cosine, daxa_f32 ref_idx) {
//     daxa_f32 r0 = (1.0f - ref_idx) / (1.0f + ref_idx);
//     r0 = r0 * r0;
//     return r0 + (1.0f - r0) * pow((1.0f - cosine), 5.0f);
// }

// daxa_f32vec3 refract(daxa_f32vec3 uv, daxa_f32vec3 n, daxa_f32 etai_over_etat) {
//     daxa_f32 cos_theta = dot(-uv, n);
//     daxa_f32vec3 r_out_parallel =  etai_over_etat * (uv + cos_theta*n);
//     daxa_f32vec3 r_out_perp = -sqrt(1.0f - length_square(r_out_parallel)) * n;
//     return r_out_parallel + r_out_perp;
// }



daxa_f32vec3 get_scatter_normal(MATERIAL m, daxa_f32vec3 direction, daxa_f32vec3 world_nrm, LCG lcg) {
    daxa_f32vec3 scatter_direction;
    switch (m.type)
    {
    case TEXTURE_TYPE_METAL:
        // return reflect(direction, world_nrm) + m.roughness * random_in_unit_sphere(lcg);
        scatter_direction = reflection(direction, world_nrm);
        break;
    case TEXTURE_TYPE_LAMBERTIAN:
    default:
        scatter_direction = world_nrm + random_unit_vector(lcg);
        // Catch degenerate scatter direction
        if (normal_near_zero(scatter_direction))
            scatter_direction = world_nrm;
    }
    return scatter_direction;
}