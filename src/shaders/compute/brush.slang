#pragma once

#include "defines.slang"

[[vk::push_constant]] changes_push_constant p;

[shader("compute")]
[numthreads(64, 1, 1)]
void entry_brush(uint3 pixel_i : SV_DispatchThreadID)
{
    if (pixel_i.x >= p.size.x || pixel_i.y >= p.size.y)
        return;

    
}