// prgn.glsl
#include <daxa/daxa.inl>


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



daxa_f32vec3 random_in_unit_sphere() {
    LCG lcg;
    initLCG(lcg, 0, 0, 0);
    while (true) {
        daxa_f32vec3 p = randomVec3InRangeLCG(lcg, -1.0f, 1.0f);
        if (length_square(p) >= 1.0f) continue;
        return p;
    }
}

daxa_f32vec3 random_unit_vector() {
    return normalize(random_in_unit_sphere());
}

daxa_f32vec3 random_on_hemisphere(daxa_f32vec3 normal) {
    daxa_f32vec3 on_unit_sphere = random_unit_vector();
    if (dot(on_unit_sphere, normal) > 0.0) // In the same hemisphere as the normal
        return on_unit_sphere;
    else
        return -on_unit_sphere;
}