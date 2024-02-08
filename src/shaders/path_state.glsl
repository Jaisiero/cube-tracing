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

    daxa_u32 max_depth; ///< Maximum path depth.

    // daxa_u16
    daxa_u32 flags; ///< Flags indicating the current status. This can be multiple PathFlags flags OR'ed together.
    // daxa_u16
    daxa_u32 path_length; ///< Path length (0 at origin, 1 at first secondary hit, etc.).
    // daxa_u16
    daxa_u32 rejected_hits; ///< Number of false intersections rejected along the path. This is used as a safeguard to avoid deadlock in pathological cases.
    // daxa_f16
    daxa_f32 scene_length;         ///< Path length in scene units (0.f at primary hit).
    daxa_u32 bounce_counters; ///< Packed counters for different types of bounces (see BounceType).

    // Scatter ray
    daxa_f32vec3 origin; ///< Origin of the scatter ray.
    daxa_f32vec3 dir;    ///< Scatter ray normalized direction.
    daxa_f32 pdf;    ///< Pdf for generating the scatter ray.
    daxa_f32vec3 normal; ///< Shading normal at the scatter ray origin.
    INSTANCE_HIT hit;    ///< Hit information for the scatter ray. This is populated at committed triangle hits.

    daxa_f32vec3 thp;       ///< Path throughput.
    daxa_f32vec3 prefix_thp; ///  used for computing rcVertexIrradiance[1]

    // daxa_f32vec3 rc_vertex_path_tree_irradiance;

    daxa_f32vec3 L;            ///< Accumulated path contribution.
    // daxa_f32vec3 L_delta_direct; //  save the direct lighting on delta surfaces

    daxa_f32      russian_roulette_PDF;
    daxa_f32vec3 shared_scatter_dir;
    daxa_f32 prev_scatter_pdf;

    INSTANCE_HIT rc_prev_vertex_hit; //  save the previous vertex of rcVertex, used in hybrid shift replay, for later reconnection
    daxa_f32vec3 rc_prev_vertex_wo;  //  save the outgoing direction at the previous vertex of rcVertex, used in hybrid shift replay, for later reconnection

    daxa_f32 hit_dist; // for NRD

    // InteriorList interiorList;      ///< Interior list. Keeping track of a stack of materials with medium properties.
    daxa_u32 seed;             ///< Sample generator state.

    PATH_BUILDER path_builder; ///< Importance samples the path from the path tree.
    PATH_RESERVOIR path_reservoir;

    // TODO: pack those as flags
    daxa_b32 enable_random_replay;    //  indicate the pathtracer is doing random number replay (being called from resampling stage)
    daxa_b32 random_replay_is_NEE;     //  indicate the base path is a NEE path, therefore the random replay should also terminates as a NEE path
    daxa_b32 random_replay_is_escaped; //  indicate the base path is a escaped path, therefore the random replay should also terminates as a escaped path
    daxa_u32 random_replay_length;    //  the length of the random replay (same as the path length of the base path)
    daxa_b32 use_hybrid_shift;
    // this is used for hybrid shift or hybrid shift is being MIS'ed with (at both initial candidate generation and resampling)
    daxa_b32 is_replay_for_hybrid_shift;        //  indicate that a random number replay is done with the hybrid shift in mind (invalidated if invertibility is violated)
    daxa_b32 is_last_vertex_classified_as_rough; //  remembers if last vertex is classified as a diffuse vertex (used for specularskip in hybrid shift)
};


void path_set_flag(inout PATH_STATE path, daxa_u32 flag, daxa_b32 value) {
    if(value) {
        path.flags |= flag;
    } else {
        path.flags &= ~flag;
    }
}


daxa_b32 path_is_active(PATH_STATE path) {
    return (path.flags & PATH_FLAG_ACTIVE) != 0;
}

daxa_b32 path_is_terminated(PATH_STATE path) {
    return !path_is_active(path);
}

void path_terminate(inout PATH_STATE path) {
    path_set_flag(path, PATH_FLAG_ACTIVE, false);
}

void path_set_active(inout PATH_STATE path) {
    path_set_flag(path, PATH_FLAG_ACTIVE, true);
}

daxa_b32 path_is_hit(PATH_STATE path) {
    return (path.flags & PATH_FLAG_HIT) != 0;
}

void path_set_hit(inout PATH_STATE path, INSTANCE_HIT instance) {
    path.hit = instance;
    path_set_flag(path, PATH_FLAG_HIT, true);
}

void path_clear_hit(inout PATH_STATE path) {
    path_set_flag(path, PATH_FLAG_HIT, false);
}

daxa_u32 get_bounces(PATH_STATE path, daxa_u32 bounce_type) {
    return (path.bounce_counters >> (bounce_type << 3)) & 0xff;
}

daxa_b32 path_is_specular_bounce(PATH_STATE path) {
    return (path.flags & PATH_FLAG_SPECULAR_BOUNCE) != 0;
}

daxa_b32 path_has_finished_surface_bounces(PATH_STATE path) {
    daxa_u32 diffuse_bounces = get_bounces(path, BOUNCE_TYPE_DIFFUSE);
    // daxa_u32 specular_bounces =  get_bounces(path, BOUNCE_TYPE_SPECULAR);
    // TODO: check more lobe types

    return diffuse_bounces 
        // + specular_bounces
        > path.max_depth; // TODO: check this by parameter
}

daxa_f32vec3 path_get_current_thp(PATH_STATE path) {
    return path.thp * path.prefix_thp;
}

void path_record_prefix_thp(inout PATH_STATE path) {
    path.prefix_thp = path.thp;
    path.thp = daxa_f32vec3(1.f);
}


void path_set_light_sampled(inout PATH_STATE path, daxa_b32 upper, daxa_b32 lower) {
    path_set_flag(path, PATH_FLAG_LIGHT_SAMPLED_UPPER, upper);
    path_set_flag(path, PATH_FLAG_LIGHT_SAMPLED_LOWER, lower);
}

void path_set_diffuse_primary_hit(inout PATH_STATE path, daxa_b32 value) {
    path_set_flag(path, PATH_FLAG_DIFFUSE_PRIMARY_HIT, value);
}


void path_increment_bounces(inout PATH_STATE path, daxa_u32 bounce_type) {
    const daxa_u32 shift = bounce_type << 3;
    // We assume that bounce counters cannot overflow.
    path.bounce_counters += (1 << shift);
}


void path_flags_transform_bounces_information(out daxa_i32 path_flags_out, daxa_i32 path_flags_in) {
    // transfer delta information for half vector reuse (TODO: refactor)
    path_flags_out &= ~(0xc000000);
    path_flags_out |= ((path_flags_in >> 26) & 3) << 26;
}









void generate_path(inout PATH_STATE path, daxa_i32vec2 index, daxa_u32vec2 rt_size, INSTANCE_HIT instance, Ray ray, daxa_u32 seed, daxa_u32 max_depth) {
    path.id = index.y * rt_size.x + index.x;
    path.max_depth = max_depth;
    path.flags = 0;
    path.path_length = 0;
    path_set_active(path);
    path.rejected_hits = 0;
    path.bounce_counters = 0;

    path.origin = ray.origin;
    path.dir = ray.direction;
    path.pdf = 0.f;
    path.normal = daxa_f32vec3(0.f);

    path.thp = daxa_f32vec3(1.f);
    path.prefix_thp = daxa_f32vec3(1.f);
    // path.rc_vertex_path_tree_irradiance = daxa_f32vec3(0.f);

    path.L = daxa_f32vec3(0.f);

    path.russian_roulette_PDF = 1.f;
    path.shared_scatter_dir = daxa_f32vec3(0.f);
    path.prev_scatter_pdf = 1.f;

    path_set_hit(path, instance);
    path.rc_prev_vertex_wo = daxa_f32vec3(0.f);

    path.hit_dist = 0.f;

    path.seed = seed;

    path_builder_init(path.path_builder, seed);
    path_reservoir_initialise(path.path_reservoir);

    // path.L_delta_direct = daxa_f32vec3(0.f);
    path.enable_random_replay = false;
    path.random_replay_is_NEE = false;
    path.random_replay_is_escaped = false;
    path.random_replay_length = 0;
    path.use_hybrid_shift = false;
    path.is_replay_for_hybrid_shift = false;
    path.is_last_vertex_classified_as_rough = true;
}


void generate_random_replay_path(out PATH_STATE path, INSTANCE_HIT instance, Ray ray, daxa_u32 random_seed, daxa_u32 random_replay_length, daxa_b32 is_last_vertext_NEE, daxa_b32 is_rc_vertext_escape_vertex) 
{
    path.id = 0;
    path.max_depth = 0;
    path.flags = 0;
    path.path_length = 0;
    path_set_active(path);
    path.rejected_hits = 0;
    path.bounce_counters = 0;

    path.origin = ray.origin;
    path.dir = ray.direction;
    path.pdf = 0.f;
    path.normal = daxa_f32vec3(0.f);

    path.thp = daxa_f32vec3(1.f);
    path.prefix_thp = daxa_f32vec3(1.f);
    // path.rc_vertex_path_tree_irradiance = daxa_f32vec3(0.f);

    path.L = daxa_f32vec3(0.f);

    path.russian_roulette_PDF = 1.f;
    path.shared_scatter_dir = daxa_f32vec3(0.f);
    path.prev_scatter_pdf = 1.f;

    path_set_hit(path, instance);
    path.rc_prev_vertex_wo = daxa_f32vec3(0.f);

    path.hit_dist = 0.f;

    path.seed = random_seed;

    // path_builder_init(path.path_builder, random_seed);
    path_reservoir_initialise(path.path_reservoir);

    // path.L_delta_direct = daxa_f32vec3(0.f);
    path.enable_random_replay = true;
    path.random_replay_is_NEE = is_last_vertext_NEE && !is_rc_vertext_escape_vertex;
    path.random_replay_is_escaped = !is_last_vertext_NEE && is_rc_vertext_escape_vertex;
    path.random_replay_length = random_replay_length;
    // TODO: use hybrid for specular bounce in the future
    path.use_hybrid_shift = false;
    path.is_replay_for_hybrid_shift = false;
    path.is_last_vertex_classified_as_rough = true;
}