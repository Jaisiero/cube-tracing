// prgn.glsl
#include <daxa/daxa.inl>

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

float randomLCG(inout LCG lcg) {
    lcg.state = (lcg.a * lcg.state + lcg.c) % lcg.m;
    return float(lcg.state) / float(lcg.m);
}

float randomInRangeLCG(inout LCG lcg, float min, float max) {
    float random_value = randomLCG(lcg);
    return min + random_value * (max - min);
}