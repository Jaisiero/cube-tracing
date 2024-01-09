#pragma once

#define DAXA_RAY_TRACING 1
#include <daxa/daxa.inl>

#include "shared.inl"
#include "prng.glsl"


void initialise_reservoir(inout RESERVOIR reservoir)
{
    reservoir.W_y = 0.0;
    reservoir.W_sum = 0.0;
    reservoir.M = 0.0;
    reservoir.Y = 0;
}

daxa_b32 update_reservoir(inout RESERVOIR reservoir, daxa_u32 X, daxa_f32 w, daxa_f32 c, inout daxa_u32 seed)
{
    reservoir.W_sum += w;
    reservoir.M += c;
 
    if ( rnd(seed) < (w / reservoir.W_sum)  )
    {
        reservoir.Y = X;
        return true;
    }
 
    return false;
}

daxa_u32 get_reservoir_light_index(in RESERVOIR reservoir)
{
    return reservoir.Y;
}

daxa_b32 is_reservoir_valid(in RESERVOIR reservoir)
{
    return reservoir.M > 0.0;
}