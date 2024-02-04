#pragma once
#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>
#include "defines.glsl"
#include "path_reservoir.glsl"
#include "path_builder.glsl"


/** Live state for the path tracer.
 */
struct PATH_STATE
{
    daxa_u32 id; ///< Path ID encodes (pixel, sampleIdx) with 12 bits each for pixel x|y and 8 bits for sample index.

    // daxa_u16
    daxa_u32
        flags; ///< Flags indicating the current status. This can be multiple PathFlags flags OR'ed together.
    // daxa_u16
    daxa_u32
        length; ///< Path length (0 at origin, 1 at first secondary hit, etc.).
    // daxa_u16
    daxa_u32
        rejected_hits; ///< Number of false intersections rejected along the path. This is used as a safeguard to avoid deadlock in pathological cases.
    // daxa_f16
    daxa_f32
        scene_length;         ///< Path length in scene units (0.f at primary hit).
    daxa_u32 bounce_counters; ///< Packed counters for different types of bounces (see BounceType).

    // Scatter ray
    daxa_f32vec3 origin; ///< Origin of the scatter ray.
    daxa_f32vec3 dir;    ///< Scatter ray normalized direction.
    daxa_f32vec3 pdf;    ///< Pdf for generating the scatter ray.
    daxa_f32vec3 normal; ///< Shading normal at the scatter ray origin.
    INSTANCE_HIT hit;    ///< Hit information for the scatter ray. This is populated at committed triangle hits.

    daxa_f32vec3 thp;       ///< Path throughput.
    daxa_f32vec3 prefix_thp; /// daqi: used for computing rcVertexIrradiance[1]

    daxa_f32vec3 rc_vertex_path_tree_irradiance;

    daxa_f32vec3 L;            ///< Accumulated path contribution.
    // daxa_f32vec3 L_delta_direct; // daqi: save the direct lighting on delta surfaces

    // daxa_f32      russianRoulettePdf = 1.f;
    daxa_f32vec3 shared_scatter_dir;
    daxa_f32 prev_scatter_pdf;

    INSTANCE_HIT rc_prev_vertex_hit; // daqi: save the previous vertex of rcVertex, used in hybrid shift replay, for later reconnection
    daxa_f32vec3 rc_prev_vertex_wo;  // daqi: save the outgoing direction at the previous vertex of rcVertex, used in hybrid shift replay, for later reconnection

    daxa_f32 hit_dist; // for NRD

    // InteriorList interiorList;      ///< Interior list. Keeping track of a stack of materials with medium properties.
    daxa_u32 seed;             ///< Sample generator state.

    PATH_BUILDER path_builder; ///< Importance samples the path from the path tree.
    PATH_RESERVOIR path_reservoir;

    // TODO: pack those as flags
    daxa_b32 enable_random_replay;    // daqi: indicate the pathtracer is doing random number replay (being called from resampling stage)
    daxa_b32 random_replay_is_NEE;     // daqi: indicate the base path is a NEE path, therefore the random replay should also terminates as a NEE path
    daxa_b32 random_replay_is_escaped; // daqi: indicate the base path is a escaped path, therefore the random replay should also terminates as a escaped path
    daxa_u32 random_replay_length;    // daqi: the length of the random replay (same as the path length of the base path)
    daxa_b32 use_hybrid_shift;
    // this is used for hybrid shift or hybrid shift is being MIS'ed with (at both initial candidate generation and resampling)
    daxa_b32 is_replay_for_hybrid_shift;        // daqi: indicate that a random number replay is done with the hybrid shift in mind (invalidated if invertibility is violated)
    daxa_b32 is_last_vertex_classified_as_rough; // daqi: remembers if last vertex is classified as a diffuse vertex (used for specularskip in hybrid shift)
};


void path_set_active(inout PATH_STATE path) {
    path.flags |= PATH_FLAG_ACTIVE;
}

void path_set_hit(inout PATH_STATE path, INSTANCE_HIT instance) {
    path.hit = instance;
}


void generate_path(inout PATH_STATE path, daxa_i32vec2 index, daxa_u32vec2 rt_size, INSTANCE_HIT instance, Ray ray, daxa_u32 seed) {
    path_set_active(path);
    path.id = index.x | (index.y << 12);
    path.thp = daxa_f32vec3(1.f);
    path.prefix_thp = daxa_f32vec3(1.f);
    path.rc_vertex_path_tree_irradiance = daxa_f32vec3(0.f);

    // path.L_delta_direct = daxa_f32vec3(0.f);
    path.enable_random_replay = false;
    path.use_hybrid_shift = false;
    path.is_last_vertex_classified_as_rough = true;
    path.is_replay_for_hybrid_shift = false;

    path_set_hit(path, instance);

    path.origin = ray.origin;
    path.dir = ray.direction;

    path.seed = seed;

    path_builder_init(path.path_builder, seed);
    path_reservoir_initialise(path.path_reservoir);
}

