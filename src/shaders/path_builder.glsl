#pragma once
#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>
#include "defines.glsl"
#include "path_reservoir.glsl"

/// Builds a Path and a PathPrefix.
struct PATH_BUILDER
{
    INSTANCE_HIT rc_vertex_hit;
    daxa_f32vec3 rc_vertex_wi[K_RC_ATTR_COUNT];
    daxa_u32 cached_random_seed;
    daxa_u32 seed;
    daxa_u32 rc_vertex_length;
    daxa_u32 path_flags; // this is a path type indicator, see the struct definition for details
    daxa_f32vec3 cached_jacobian;
};

void path_builder_init(inout PATH_BUILDER path_builder, daxa_u32 seed)
{
    path_builder.seed = seed;
    path_builder.rc_vertex_hit = INSTANCE_HIT(MAX_INSTANCES, MAX_PRIMITIVES);
    path_builder.rc_vertex_wi[0] = daxa_f32vec3(0.0);
    path_builder.cached_random_seed = 0;
    path_builder.rc_vertex_length = MAX_DEPTH;
    path_builder.path_flags = 0;
    path_builder.cached_jacobian = daxa_f32vec3(0.0);
}

void path_builder_finilize(inout PATH_RESERVOIR reservoir)
{
    reservoir.M = 1.0;
}

daxa_b32 path_builder_add_escape_vertex(inout PATH_BUILDER path_builder, daxa_u32 path_length,
                                        daxa_f32vec3 wi, daxa_f32vec3 path_weight,
                                        daxa_f32vec3 postfix_weight, daxa_b32 use_hybrid_shift,
                                        daxa_f32 russian_roulette_PDF, daxa_f32 mis_weight,
                                        daxa_f32 light_pdf, daxa_u32 light_type,
                                        inout PATH_RESERVOIR path_reservoir, daxa_b32 force_add)
{
    daxa_b32 selected = false;

    if (path_length >= 1)
    {
        daxa_b32 is_rc_vertex = path_length == path_builder.rc_vertex_length;
        if (force_add || path_reservoir_update(path_reservoir, path_weight, russian_roulette_PDF, path_builder.seed))
        {
            selected = true;
            path_reservoir.path_flags = path_builder.path_flags;
            path_reservoir_insert_path_length(path_reservoir, path_length);
            path_reservoir_insert_rc_vertex_length(path_reservoir, path_builder.rc_vertex_length);
            path_reservoir_insert_last_vertex_nee(path_reservoir, false);
            path_reservoir.rc_vertex_irradiance[0] = postfix_weight;
            path_reservoir.F = path_weight;
            path_reservoir.rc_vertex_wi[0] = path_builder.rc_vertex_wi[0];
            path_reservoir.rc_vertex_hit = path_builder.rc_vertex_hit;

            path_reservoir.cached_jacobian = path_builder.cached_jacobian;

            path_reservoir.rc_random_seed = path_builder.cached_random_seed;

            if (is_rc_vertex) // at rc_vertex
            {
                path_reservoir.rc_vertex_wi[0] = wi;
                path_reservoir.rc_vertex_irradiance[0] /= mis_weight; // exclude last vertex dependent mis weight
            }
            path_reservoir.light_pdf = light_pdf;
            path_reservoir_insert_light_type(path_reservoir, light_type);
        }
    }

    return selected;
}

daxa_b32 path_builder_add_NEE_vertex(inout PATH_BUILDER path_builder, daxa_u32 path_length, daxa_f32vec3 wi, daxa_f32vec3 path_weight, daxa_f32vec3 postfix_weight, daxa_b32 use_hybrid_shift,
                                     daxa_f32 russian_roulette_PDF, daxa_f32 mis_weight, daxa_f32 light_pdf, daxa_u32 light_type, inout PATH_RESERVOIR path_reservoir, daxa_b32 force_add)
{
    daxa_b32 selected = false;

    if (path_length >= 1)
    {
        daxa_b32 is_rc_vertex = path_length == path_builder.rc_vertex_length;
        if (force_add || path_reservoir_update(path_reservoir, path_weight, russian_roulette_PDF, path_builder.seed))
        {
            selected = true;
            path_reservoir.path_flags = path_builder.path_flags;
            path_reservoir_insert_path_length(path_reservoir, path_length); // excluding the NEE vertex
            path_reservoir_insert_rc_vertex_length(path_reservoir, path_builder.rc_vertex_length);
            path_reservoir_insert_last_vertex_nee(path_reservoir, true);
            path_reservoir.rc_vertex_irradiance[0] = postfix_weight;
            path_reservoir.F = path_weight;
            path_reservoir.rc_vertex_wi[0] = path_builder.rc_vertex_wi[0];
            path_reservoir.rc_vertex_hit = path_builder.rc_vertex_hit;

            path_reservoir.cached_jacobian = path_builder.cached_jacobian;

            path_reservoir.rc_random_seed = path_builder.cached_random_seed;

            if (is_rc_vertex) // at rc_vertex
            {
                path_reservoir.rc_vertex_irradiance[0] = path_reservoir.rc_vertex_irradiance[0] * light_pdf / mis_weight;
                path_reservoir.rc_vertex_wi[0] = wi;
            }
            path_reservoir.light_pdf = light_pdf;
            path_reservoir_insert_light_type(path_reservoir, light_type);
        }
    }

    return selected;
}

void path_builder_mark_escape_vertex_as_rc_vertex(inout PATH_BUILDER path_builder,
                                                  daxa_u32 path_length,
                                                  inout PATH_RESERVOIR path_reservoir,
                                                  INSTANCE_HIT hit,
                                                  daxa_b32 is_delta,
                                                  daxa_b32 is_transmission,
                                                  daxa_b32 is_specular_bounce,
                                                  daxa_f32 light_pdf,
                                                  daxa_u32 light_type,
                                                  daxa_f32vec3 rc_vertex_irradiance,
                                                  daxa_f32vec3 rc_vertex_wi,
                                                  daxa_f32 prev_scatter_pdf,
                                                  daxa_f32 geometry_factor)
{
    path_reservoir_insert_rc_vertex_length(path_reservoir, path_length);
    // TODO: path_reservoir_path_init_from_hit_info(path_reservoir, hit);
    path_builder.rc_vertex_hit = hit;
    path_reservoir_insert_is_delta_event(path_reservoir, is_delta, true);
    path_reservoir_insert_is_transmission_event(path_reservoir, is_transmission, true);
    path_reservoir_insert_is_specular_bounce(path_reservoir, is_specular_bounce, true);
    path_reservoir.light_pdf = light_pdf;
    path_reservoir.cached_jacobian.x = prev_scatter_pdf;
    path_reservoir_insert_light_type(path_reservoir, light_type);
    path_reservoir.rc_vertex_irradiance[0] = rc_vertex_irradiance;
    path_reservoir.rc_vertex_wi[0] = rc_vertex_wi;
    path_reservoir.cached_jacobian.z = geometry_factor;
}