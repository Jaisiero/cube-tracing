// path_tracer.glsl
#ifndef SHIFT_GLSL
#define SHIFT_GLSL
#define DAXA_RAY_TRACING 1
#include <daxa/daxa.inl>
#include "shared.inl"
#include "path_state.glsl"
#include "path_tracer.glsl"

daxa_b32 shift_and_merge_reservoir(const SCENE_PARAMS params,
                                   const daxa_b32 temporal_update_for_dynamic_scene,
                                   inout daxa_f32 dst_jacobian,
                                   const INSTANCE_HIT dst_primary_hit,
                                   const INTERSECT dst_primary_intersection,
                                   inout PATH_RESERVOIR dst_reservoir,
                                   const INTERSECT src_primary_intersection,
                                   const PATH_RESERVOIR src_reservoir,
                                   RECONNECTION_DATA rc_data,
                                   daxa_b32 eval_visibility,
                                   inout daxa_u32 seed,
                                   daxa_b32 is_spatial_reuse,
                                   daxa_f32 mis_weight,
                                   daxa_b32 force_merge)
{
    
    return false;
}


#endif // SHIFT_GLSL