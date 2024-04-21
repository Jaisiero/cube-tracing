#pragma once

#include "defines.slang"

[[vk::push_constant]] changes_push_constant p;

[shader("compute")]
    [numthreads(BRUSH_COMPUTE_X, BRUSH_COMPUTE_Y, 1)] void
    entry_brush(uint3 pixel_i : SV_DispatchThreadID)
{

}