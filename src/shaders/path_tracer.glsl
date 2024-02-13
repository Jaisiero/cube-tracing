// path_tracer.glsl
#ifndef PATH_TRACER_GLSL_GLSL
#define PATH_TRACER_GLSL_GLSL
#define DAXA_RAY_TRACING 1
#include <daxa/daxa.inl>
#include "shared.inl"
#include "primitives.glsl"
#include "light.glsl"
#include "path_state.glsl"
#include "path_tracer.glsl"



struct PATH_VERTEX
{
    daxa_u32 index;
    daxa_f32vec3 position;
    daxa_f32vec3 normal;
};

struct LIGHT_SAMPLER
{
    daxa_f32vec3 dir;
    daxa_f32 pdf;
    daxa_f32vec3 Li;
    daxa_u32 type;
};


daxa_b32 generate_scatter_ray(inout INTERSECT i, inout daxa_u32 seed) {

    call_scatter.hit = i.world_hit;
    call_scatter.nrm = i.world_nrm;
    call_scatter.ray_dir = i.wo;
    call_scatter.seed = seed;
    call_scatter.scatter_dir = vec3(0.0);
    call_scatter.done = false;
    call_scatter.mat_idx = i.material_idx;
    call_scatter.instance_hit = i.instance_hit;


    daxa_u32 mat_type = i.material_idx & MATERIAL_TYPE_MASK;

    switch (mat_type)
    {
    case MATERIAL_TYPE_METAL:
        executeCallableEXT(3, 4);
        break;
    case MATERIAL_TYPE_DIELECTRIC:
        executeCallableEXT(4, 4);
        break;
    case MATERIAL_TYPE_CONSTANT_MEDIUM:
        executeCallableEXT(5, 4);
        break;
    case MATERIAL_TYPE_LAMBERTIAN:
    default:
        executeCallableEXT(2, 4);
        break;
    }
    seed = call_scatter.seed;
    i.world_hit = call_scatter.hit;
    i.world_nrm = call_scatter.nrm;
    i.wi = call_scatter.scatter_dir;

    return !call_scatter.done;
}



daxa_b32 path_generate_scatter_ray(inout PATH_STATE path, inout INTERSECT i) {

    daxa_b32 valid = generate_scatter_ray(i, path.seed);

    if(valid) {
        daxa_f32vec3 weight = evaluate_material(i.mat, i.world_nrm, i.wo, i.wi);
        daxa_f32 pdf = sample_material_pdf(i.mat, i.world_nrm, i.wo, i.wi);

        path.dir = i.wi;
        
        if(path.path_length == 0 ) {
            // TODO: set diffuse primary hit for now
            path_set_diffuse_primary_hit(path, true);
        }

        path.thp *= weight;

        path.pdf = pdf;


        if(path.path_length == path.path_builder.rc_vertex_length) {
            path.path_builder.cached_jacobian.y = pdf;
        }

        path.prev_scatter_pdf = pdf;

        if(pdf <= 0.0) {
            return false;
        }

        // TODO: clear event flags.

        // TODO: We classify specular events as diffuse if the roughness is above some threshold.

        // TODO: Handle other reflexions here (pathtracer:357)
        path_increment_bounces(path, BOUNCE_TYPE_DIFFUSE);


        path.normal = i.world_nrm;

        valid = any(greaterThan(path.thp, daxa_f32vec3(0.0)));

        if(valid) {
            if(path.path_length <= path.path_builder.rc_vertex_length) {
               path_record_prefix_thp(path);
            }
        }

    }

    return valid;
}

daxa_b32 generate_replay_primary_scatter_ray(const SCENE_PARAMS params, inout PATH_STATE path, inout INTERSECT i, daxa_f32vec3 dir) {

    daxa_b32 valid = false;

    if(all(notEqual(dir, daxa_f32vec3(0.0)))) {
        valid = path_generate_scatter_ray(path, i);
    } else {
        // TODO: complete this function
        // valid = path_generate_scatter_ray_given_direction(path, i, dir);
    }

    if (!valid)
    {
        path_terminate(path);
    }
    else
    {
        // TODO: separate BSDF (pathtracer: 955)
        path.is_last_vertex_classified_as_rough = classify_as_rough(i.mat.roughness, params.roughness_threshold);
    }

    return valid;

}



void path_next_vertex(inout PATH_STATE path, out INTERSECT i) {

    i = intersect(Ray(path.origin, path.dir));

    if(i.is_hit) {
        path_set_hit(path, i.instance_hit);
        path.path_length++;
        path.scene_length += i.distance;
    }
    else {
        path_clear_hit(path);
        path.scene_length = HLF_MAX;
    }

}

void path_invalidate_and_terminate_replay_path(inout PATH_STATE path) {
    path_clear_hit(path);
    path.rc_prev_vertex_wo = daxa_f32vec3(0.0);
    path.L = daxa_f32vec3(0.0);
    path.thp = daxa_f32vec3(0.0);
    path_terminate(path);
}



daxa_b32 terminate_path_by_russian_roulette(inout PATH_STATE path) {
    const daxa_f32 rr_vale = path_luminance(path_get_current_thp(path));
    const daxa_f32 prob = max(0.f, 1.f - rr_vale);
    if (rnd(path.seed) < prob)
    {
        path_terminate(path);
        return true;
    }

    path.russian_roulette_PDF *= 1.f - prob;

    return false;
}




void path_skip_light_sample_random_numbers(inout daxa_u32 seed) {
    rnd(seed);
}


/** Evaluates the PDF for a light sample given a hit point on an emissive triangle.
    \param[in] posW Shading point in world space.
    \param[in] hit Triangle hit data.
    \return Probability density with respect to solid angle at the shading point.
*/
daxa_f32 eval_voxel_pdf(const daxa_f32vec3 pos_W, const INTERSECT i)
{
    // Compute light vector and squared distance.
    daxa_f32vec3 to_light = i.world_hit - pos_W; // Unnormalized light vector
    const daxa_f32 dist_sqr = dot(to_light, to_light);
    if (dist_sqr <= FLT_MIN) return 0.f; // Avoid NaNs below
    daxa_f32vec3 L = to_light / sqrt(dist_sqr);

    // Cosine of angle between the light's normal and the light vector (flip L since it points towards the light).
    daxa_f32 cos_theta = dot(i.world_nrm, -L);
    if (cos_theta <= 0.f) return 0.f;

    // TODO: size hardcoded for now
    const daxa_f32 side =  VOXEL_EXTENT;
    const daxa_f32 area = side * side;

    // Compute probability density with respect to solid angle from the shading point.
    // The farther away the light is and the larger the angle it is at, the larger the pdf becomes. The probability goes to infinity in the limit.
    // Note: Guard against div-by-zero here by clamping.
    // TODO: Do we need the clamp here? distSqr is already clamped, so NaN should not be possible (but +inf is).
    daxa_f32 denom = max(FLT_MIN, cos_theta * area);
    return dist_sqr / denom;
}

/** Evaluate the PDF at a shading point given a hit point on an emissive triangle.
    \param[in] i Intersection data.
    \return Probability density with respect to solid angle at the shading point.
*/
daxa_f32 path_evaluate_emissive(daxa_f32vec3 origin, daxa_f32vec3 normal, INTERSECT i, daxa_f32 light_count) {

    daxa_f32 selecting_voxel_pdf = 1.f / light_count;

    daxa_f32 voxel_pdf = eval_voxel_pdf(origin, i);

    return selecting_voxel_pdf * voxel_pdf;
}


daxa_b32 path_generate_light_sample(const SCENE_PARAMS params, INTERSECT i, const daxa_b32 sample_upper_hemisphere, const daxa_b32 sample_lower_hemisphere, inout daxa_u32 seed, out LIGHT_SAMPLER ls) {


    ls = LIGHT_SAMPLER(daxa_f32vec3(0.0), 0.0, daxa_f32vec3(0.0), 0);

    daxa_u32 light_index = min(urnd_interval(seed, 0, params.light_count), params.light_count - 1);
    LIGHT light = get_light_from_light_index(light_index);

    ls.type = light.type;

    daxa_f32 pdf = 1.0 / params.light_count;


    Ray ray = Ray(i.world_hit, i.wo);
    
    // intersection info
    HIT_INFO_INPUT hit = HIT_INFO_INPUT(
        i.world_hit,
        i.world_nrm,
        i.distance,
        -i.wo,
        i.instance_hit,
        i.material_idx,
        seed,
        0);

    daxa_f32vec3 l_pos;

    ls.Li = calculate_sampled_light_and_get_light_info(ray, hit, i.mat, params.light_count, light, pdf, ls.pdf, l_pos, ls.dir, true, true, true);

    // TODO: simplify calculate_sampled_light interface
    seed = hit.seed;

    return any(greaterThan(ls.Li, daxa_f32vec3(0.0)));
}



daxa_b32 path_handle_emissive_hit(const SCENE_PARAMS params, inout PATH_STATE path, INTERSECT i, daxa_b32 terminate_random_replay_for_escape) {

    daxa_f32vec3 attenuated_emission = daxa_f32vec3(0.0);

    daxa_f32 light_pdf = 0.f;

    daxa_f32 mis_weight = 1.f;
    daxa_f32vec3 Lr = daxa_f32vec3(0.0);

    daxa_b32 primary_hit = path.path_length == 0;

    if(!primary_hit) {
        // If NEE and MIS are enabled, and we've already sampled emissive lights,
        // then we need to evaluate the MIS weight here to account for the remaining contribution.
        light_pdf = path_evaluate_emissive(path.origin, path.normal, i, params.light_count);

        mis_weight = eval_mis(1, path.pdf, 1, light_pdf, 2.0);

        Lr = path_get_current_thp(path) * i.mat.emission * mis_weight;
    }

    attenuated_emission = path_get_current_thp(path) * i.mat.emission;
    
    // daqi: Since ScreenSpaceReSTIR cannot handle transmission and delta reflection, we must include the contribution in the color buffer 
    if (!path.enable_random_replay || terminate_random_replay_for_escape)
    {
        if (path.path_length > 1) path.L += Lr;
        // will change this to path.IsDelta() if ScreenSpaceReSTIR can handle transmission
        // if (path.path_length == 1) path.LDeltaDirect += Lr;
    }


    // daqi: here we are adding the path terminated with an escaped vertex
    if (!path.enable_random_replay || terminate_random_replay_for_escape)
    {
        daxa_f32vec3 postfix_weight = path.thp * attenuated_emission * mis_weight;

        daxa_b32 selected = path_builder_add_escape_vertex(
            path.path_builder,
            max(0, daxa_i32(path.path_length) - 1),
            path.dir,
            Lr,
            postfix_weight,
            path.use_hybrid_shift,
            path.russian_roulette_PDF,
            mis_weight,
            light_pdf,
            GEOMETRY_LIGHT_CUBE,
            path.path_reservoir,
            path.enable_random_replay);

        // if current escaped vertex has path.path_length >= 2, then it can be used as a rcVertex
        if (selected && path.use_hybrid_shift && path.path_length >= 2 && path.path_length < path.path_builder.rc_vertex_length)
        {
            // insert path flags

            //  ideally, this should use a smaller nearFieldDistance than the default threshold
            daxa_b32 is_far_field = length(i.world_hit - path.origin) >= params.near_field_distance;
            daxa_b32 is_last_vertex_acceptable_for_rc_prev = path.is_last_vertex_classified_as_rough;

            if (!(!is_far_field || !is_last_vertex_acceptable_for_rc_prev))
            {
                if (path.is_replay_for_hybrid_shift) // non-invertible case 
                {
                    path.L = daxa_f32vec3(0.f);
                }
                else
                {
                    // we found an RC vertex!
                    // set rcVertexLength to current length (this will make rcVertexLength = reseroivr.pathLength + 1)
                    daxa_f32 geometry_factor = geom_fact_sa(i.world_hit, path.origin, i.world_nrm);

                    path_builder_mark_escape_vertex_as_rc_vertex(path.path_builder, path.path_length, 
                        path.path_reservoir, path.hit, 
                        path_is_specular_bounce(path),    
                        path_is_delta_event(path),
                        path_is_transmission_event(path), 
                        light_pdf, GEOMETRY_LIGHT_CUBE, i.mat.emission, daxa_f32vec3(0.f), 
                        path.prev_scatter_pdf, geometry_factor);
                }
            }
        }
    }

    return true;
}

daxa_b32 path_handle_sample_light(const SCENE_PARAMS params, inout PATH_STATE path, INTERSECT i, daxa_b32 terminate_random_replay_for_NEE, daxa_b32 is_rc_vertex) {
    
    daxa_b32 valid_sample = false;
    // if we are doing random number replay, we should only sample the light if we are about to terminate

    // generate kNEESamples light samples
    if ((!path.enable_random_replay || terminate_random_replay_for_NEE))
    {
        // cache (NEE sampling) seed for temporal validation (only possible for non early direction reuse since it uses the cachedRandomSeed slot)
        if (path.path_length == path.path_builder.rc_vertex_length)
        {
            path.path_builder.cached_random_seed = path.seed;
        }

        LIGHT_SAMPLER ls;
        {
            // Setup path vertex.
            PATH_VERTEX vertex = PATH_VERTEX(path.path_length + 1, i.world_hit, i.world_nrm);

            // TODO: complete this function
            // // Determine if upper/lower hemispheres need to be sampled.
            // daxa_b32 sample_upper_hemisphere = ((lobes & (uint)LobeType::NonDeltaReflection) != 0);
            // if (!kUseLightsInDielectricVolumes && path.isInsideDielectricVolume())
            //     sample_upper_hemisphere = false;
            // daxa_b32 sample_lower_hemisphere = ((lobes & (uint)LobeType::NonDeltaTransmission) != 0);

             daxa_b32 sample_upper_hemisphere = true;
            daxa_b32 sample_lower_hemisphere = false;

            // Sample a light.

            valid_sample = path_generate_light_sample(params, i, sample_upper_hemisphere, sample_lower_hemisphere, path.seed, ls);

            path_set_light_sampled(path, sample_upper_hemisphere, sample_lower_hemisphere);
        }

        if (valid_sample)
        {
            // Apply MIS weight.
            daxa_f32 mis_weight = 1.f;
            daxa_f32 scatter_pdf = 0.f;

            // TODO: Check if this is correct
            scatter_pdf = sample_material_pdf(i.mat, i.world_nrm, i.wo, ls.dir);

            mis_weight *= eval_mis(1, ls.pdf, 1, scatter_pdf, 2.0);

            ls.Li *= mis_weight;

            // TODO: Check if this is correct
            daxa_f32vec3 weight = eval_bsdf_cosine(i.mat, i.world_nrm, i.wo, ls.dir);

            daxa_f32vec3 Lr = weight * ls.Li * path_get_current_thp(path);

            // NOTE: visibility already checked in path_generate_light_sample

            // TODO: is this necessary?
            if (!path.enable_random_replay || terminate_random_replay_for_NEE)
                path.L += Lr;

            // TODO: Analytic lights? (pathtracer: 1322)

            // here we are adding the path terminated with an NEE event
            // if we have enabled random replay, we know that we are going to use this path
            if (is_rc_vertex)
            {
                weight = daxa_f32vec3(1.f);
            }

            daxa_b32 selected =  path_builder_add_NEE_vertex(path.path_builder, path.path_length, ls.dir, Lr, weight * ls.Li * path.thp, path.use_hybrid_shift,
                                                                path.russian_roulette_PDF, mis_weight, ls.pdf,  ls.type, path.path_reservoir, path.enable_random_replay);  
        }
    }
    else
    // for random number replay, we should skip the random numbers for NEE if we should not terminate on current bounce
    {
        if (path.enable_random_replay)
        {
            // TODO: delta & volumetric (pathtracer: 1359)
        }

        path_skip_light_sample_random_numbers(path.seed);
    }

    return valid_sample;
}


daxa_b32 path_handle_primary_hit(const SCENE_PARAMS params, inout PATH_STATE path, inout INTERSECT i) {

    // TODO: complete this function
    // Compute origin for rays traced from this path vertex.
    path.origin = i.world_hit;

    path_handle_emissive_hit(params, path, i, false);


    path_set_light_sampled(path, false, false);

    if (path.path_length == 0)
    {
        path.path_reservoir.init_random_seed = path.seed;
    }

    daxa_b32 valid = path_generate_scatter_ray(path, i);

    // TODO: Check if (pathtracer:1403) necessary here


    return valid;
}



daxa_b32 path_check_rc_vertex(inout PATH_STATE path, INTERSECT i, daxa_f32vec3 prev_path_origin, daxa_b32 is_far_field, daxa_b32 is_current_vertex_classified_as_rough, daxa_b32 is_last_vertex_acceptable_for_rc_prev, out daxa_b32 is_rc_vertex) {
    //  if we are not doing a hybrid shift replay, we should check if current vertex satisfy the condition to be used as a rcVertex
    if (!path.is_replay_for_hybrid_shift)
    {
        daxa_b32 can_connect = (path.path_length >= 1 && path.path_length < path.path_builder.rc_vertex_length &&
                           (!(!is_far_field || !(is_current_vertex_classified_as_rough && is_last_vertex_acceptable_for_rc_prev))));

        if (!path.use_hybrid_shift && path.path_length == 1 || path.use_hybrid_shift && can_connect)
        {
            is_rc_vertex = true;
            path.path_builder.rc_vertex_hit = path.hit;
            // save the scatter PDF as cachedJacobian
            path.path_builder.cached_jacobian.x = path.prev_scatter_pdf;
            // path.path_builder.pathFlags.insertIsDeltaEvent(path.isDelta(), true);
            // path.path_builder.pathFlags.insertIsTransmissionEvent(path.isTransmission(), true);
            // if (kSeparatePathBSDF)
            //     path.pathBuilder.pathFlags.insertIsSpecularBounce(path.isSpecularBounce(), true);

            daxa_f32vec3 disp = prev_path_origin - i.world_hit;

            // save geometry term as part of cached jacobian
            path.path_builder.cached_jacobian.z = abs(dot(i.world_nrm, i.wo)) / dot(disp, disp);

            // save the current path length as the rc vertex length
            if (can_connect || !path.use_hybrid_shift)
            {
                path.path_builder.rc_vertex_length = path.path_length;
            }
        }
    }
    else
    {
        daxa_b32 invertible = true;
        daxa_b32 should_terminate = false;

        //  check situation where invertibility is violated
        if (path.path_length >= 1 && path.path_length <= path.path_builder.rc_vertex_length - 1)
        {
            // TODO: separate BSDF (pathtracer:1202)
            // if (kSeparatePathBSDF)
            // {
            //     if (params.localStrategyType & (uint)LocalStrategy::RoughnessCondition)
            //     {
            //         // method 2
            //         // non-invertible if this bounce is an NEE bounce for the base path but the current vertex is not connectible in base path but is connectible in offset path
            //         if (terminate_random_replay_for_NEE && isCurrentVertexClassifiedAsRough && is_last_vertex_acceptable_for_rc_prev)
            //             invertible = false;
            //         // non-invertible because current vertex will be assigned as a diffuse bounce by connecting to the reconnection vertex
            //         if (path.path_length == path.pathBuilder.rcVertexLength - 1 && is_last_vertex_acceptable_for_rc_prev)
            //             invertible = false;

            //         if (!is_far_field)
            //             invertible = true;
            //     }
            //     else
            //     {
            //         if (params.localStrategyType & (uint)LocalStrategy::DistanceCondition && is_far_field)
            //             invertible = false;
            //     }
            // }
            // else
            {
                if (!is_far_field || !(is_current_vertex_classified_as_rough && is_last_vertex_acceptable_for_rc_prev))
                    invertible = false;
            }
        }

        // if next vertex is rcVertex and the shift is still invertible, then we should terminate
        if (path.path_length == path.path_builder.rc_vertex_length - 1 && invertible)
        {
            // TODO: separate BSDF (pathtracer:1231)
            // not possible to generate a diffuse bounce
            if (!is_current_vertex_classified_as_rough)
            {
                //  invalidate the shift
                invertible = false;
            }
            // TODO: near field rejection case is checked in computeShiftedIntegrandReconnection in shift.slang
            else
            {
                should_terminate = true;
            }
        }

        if (invertible)
        {
            // if it is invertible and we should terminate, save the hit information to set up a reconnection
            if (should_terminate)
            {
                path.rc_prev_vertex_hit = path.hit;
                path.rc_prev_vertex_wo = i.wo;
                path_terminate(path);
            }
        }
        else // if the shift is not invertible, we should mark the case, which causes the shift to terminate when it goes back to shift.slang
        {
            path_invalidate_and_terminate_replay_path(path);
        }

        if (!path_is_active(path))
            return false;
    }

    return true;
}

void path_handle_hit(const SCENE_PARAMS params, inout PATH_STATE path, inout INTERSECT i) {

    // Upon hit:
    // - Load vertex/material data
    // - Compute volume absorption
    // - Compute MIS weight if path.path_length > 0 and emissive hit
    // - Add emitted radiance
    // - Sample light(s) using shadow rays
    // - Sample scatter ray or terminate

    daxa_b32 compute_emissive = true;

    // // TODO: RCRandomSeed
    // if (path.path_reservoir.rc_random_seed == 0) path.path_reservoir.rc_random_seed = 1;
    
    // // TODO: RCRandomSeed
    // if(path.path_reservoir.rc_random_seed == 2) path.path_reservoir.rc_random_seed = 3;

    if(path.path_length == 1 && !path_is_transmission_event(path) && !path_is_delta_event(path) ) compute_emissive = false;

    //  when doing random number replay, we will terminate the path when the length reaches the base path length and
    // when the path types match. In this case, if the base path is a escaped path (as opposed to an NEE path), we should terminate when we
    // find that offset path can also be an escaped path
    daxa_b32 terminate_random_replay_for_escape = 
        path.enable_random_replay && 
        path.path_length - 1 == path.random_replay_length && 
        path.random_replay_is_escaped && 
        path.random_replay_length >= 1;

    // Sample emissive (add escape vertex) (pathtracer:1034)
    if (compute_emissive && any(greaterThan(i.mat.emission, daxa_f32vec3(0.f))))
    {
        path_handle_emissive_hit(params, path, i, terminate_random_replay_for_escape);
    }

    // Terminate after scatter ray on last vertex has been processed.
    if (path_has_finished_surface_bounces(path) || terminate_random_replay_for_escape)
    {
        path_terminate(path);
        return;
    }

    daxa_f32vec3 prev_path_origin = path.origin;

    // Compute origin for rays traced from this path vertex.
    path.origin = i.world_hit;

    // TODO: Some lobe stuff (pathtracer:1136)

    // when doing random number replay, we will terminate the path when the length reaches the base path length and
    // when the path types match. In this case, if the base path is a NEE path (as opposed to an escaped path), we should terminate when we
    // find that offset path can also be an NEE path
    daxa_b32 terminate_random_replay_for_NEE = 
        path.enable_random_replay && 
        path.path_length == path.random_replay_length && 
        path.random_replay_is_NEE;

    daxa_b32 is_rc_vertex = false;

    daxa_b32 is_far_field = length(path.origin - prev_path_origin) >= params.near_field_distance;
    // TODO: check separate BSDF (multiple lobes) (pathtracer:1160)
    // TODO: set roughness as 1.0 for now
    daxa_b32 is_current_vertex_classified_as_rough = classify_as_rough(i.mat.roughness, params.roughness_threshold);
    daxa_b32 is_last_vertex_acceptable_for_rc_prev = path.is_last_vertex_classified_as_rough;

    // Check if rc_vertex (pathtracer:1165)
    if(!path_check_rc_vertex(path, i, prev_path_origin, is_far_field, is_current_vertex_classified_as_rough, is_last_vertex_acceptable_for_rc_prev, is_rc_vertex)) {
        return;
    }

    path_set_light_sampled(path, false, false);

    // Sample light (add NEE vertex) (pathtracer:1265)
    path_handle_sample_light(params, path, i, terminate_random_replay_for_NEE, is_rc_vertex);

    //  terminate the path if the bounce of random replay reaches the desired bounce and the base path is an NEE path
    if (terminate_random_replay_for_NEE)
    {
        path_terminate(path);
        return;
    }

    // Russian roulette (pathtracer:1378)
    // Russian roulette to terminate paths early.
    // TODO: check if this is handled correctly in ReSTIR PT
    if (params.use_russian_roulette && path.path_length >= 1)
    {
        if (path.enable_random_replay)
        {
            rnd(path.seed);
        }
        else
        {
            if (terminate_path_by_russian_roulette(path))
                return;
        }
    }

    // Scatter ray (pathtracer:1400)
    daxa_b32 valid = path_generate_scatter_ray(path, i);


    // TODO: forbid current vertex being rcVertex if conditions are not met (pathtracer:1403)

    // cache seed for temporal validation (only possible for non early direction reuse since it uses the cachedRandomSeed slot) (pathtracer:1427)
    if (path.path_length == path.path_builder.rc_vertex_length)
    {
        path.path_builder.cached_random_seed = path.seed;
    }
    
    // // TODO: RCRandomSeed
    // if(path.path_reservoir.rc_random_seed == 1) path.path_reservoir.rc_random_seed = 2;

    // TODO: check this
    daxa_b32 BPR = false;

    // save the incoming direction on rcVertex (pathtracer:1433)
    if (is_rc_vertex && valid && (daxa_i32(path.path_length > 1) == 0 || BPR == false))
    {
        path.path_builder.rc_vertex_wi[0] = path.dir;
    }

    path.is_last_vertex_classified_as_rough = is_current_vertex_classified_as_rough;
    
    // TODO: save more things afterwards (do we need them?) (pathtracer:1441)

    // if path is terminated, return (pathtracer:1456)
    if (!path_is_active(path)) return;

    // Check if last bounce for replay only (pathtracer:1459)
    const daxa_b32 is_last_vertex = path_has_finished_surface_bounces(path);

    if(is_last_vertex) valid = false;

    // TODO: Check other things to invalidate the path (caustics) (pathtracer:1465)

    // If not valid, terminate path (pathtracer:1467)
    if(!valid) path_terminate(path);
}

void path_handle_miss(const SCENE_PARAMS params, inout PATH_STATE path, inout INTERSECT i) {
    // Upon miss:
    // - Compute MIS weight if previous path vertex sampled a light
    // - Evaluate environment map
    // - Write guiding data
    // - Terminate the path


    if (params.compute_environment_light)
    {

        daxa_f32 mis_weight = 1.f;
        daxa_f32 light_pdf = 0.f;
        // TODO: implement light sampled check
        // if (path_is_light_sampled(path))
        // {
        // If NEE and MIS are enabled, and we've already sampled the env map,
        // then we need to evaluate the MIS weight here to account for the remaining contribution.

        // TODO: get_env_map_selection_probability
        // Evaluate PDF, had it been generated with light sampling.
        light_pdf = // get_env_map_selection_probability() *
            env_map_sampler_eval_pdf(path.dir);

        // Compute MIS weight by combining this with BRDF sampling.
        // Note we can assume path.pdf > 0.f since we shouldn't have got here otherwise.
        mis_weight = eval_mis(1, path.pdf, 1, light_pdf, 2.f);
        // }

        daxa_f32vec3 Le = env_map_sampler_eval(path.dir);
        daxa_f32vec3 Lr = path_get_current_thp(path) * Le * mis_weight;

        // daqi: when doing random number replay, we will terminate the path when the length reaches the base path length and
        // when the path types match. In this case, if the base path is a escaped path (as opposed to an NEE path), we should terminate when we
        // find that offset path can also be an escaped path
        daxa_b32 terminate_random_replay_for_escape = path.enable_random_replay && path.path_length == path.random_replay_length && path.random_replay_is_escaped && path.path_length >= 1;

        // daqi: Since ScreenSpaceReSTIR cannot handle transmission and delta reflection, we must include the contribution in the color buffer
        if (!path.enable_random_replay || terminate_random_replay_for_escape)
        {
            if (path.path_length > 0)
                path.L += Lr;

            // will change this to path.IsDelta() if ScreenSpaceReSTIR can handle transmission
            // if (path.path_length == 0) path.LDeltaDirect += Lr;
        }

        // daqi: here we are adding the path terminated with an escaped vertex
        if ((!path.enable_random_replay || terminate_random_replay_for_escape))
        {
            daxa_b32 selected_current_path = path_builder_add_escape_vertex(path.path_builder,
                                                                            path.path_length,
                                                                            path.dir, Lr, path.thp * Le * mis_weight,
                                                                            path.use_hybrid_shift,
                                                                            path.russian_roulette_PDF,
                                                                            mis_weight,
                                                                            light_pdf,
                                                                            GEOMETRY_LIGHT_ENV_MAP,
                                                                            path.path_reservoir,
                                                                            path.enable_random_replay);
            // daqi: if current escaped vertex has path.path_length >= 2, then it can be used as a rcVertex
            if (selected_current_path && path.use_hybrid_shift && path.path_length >= 1 && path.path_length + 1 < path.path_builder.rc_vertex_length)
            {
                daxa_b32 is_last_vertex_acceptable_for_rc_prev = path.is_last_vertex_classified_as_rough;

                // daqi: in the case of escaped to infinitely far, we always satisfy the far field requirement
                if (!(!is_last_vertex_acceptable_for_rc_prev))
                {
                    if (path.is_replay_for_hybrid_shift) // non-invertible case
                    {
                        path.L = daxa_f32vec3(0.f);
                    }
                    else
                    {
                        // we found an RC vertex!
                        // set rcVertexLength to current length (this will make rcVertexLength = reseroivr.pathLength + 1)
                        INSTANCE_HIT dummy_hit = INSTANCE_HIT(MAX_INSTANCES, MAX_PRIMITIVES);
                        path_builder_mark_escape_vertex_as_rc_vertex(path.path_builder,
                                                                     path.path_length + 1,
                                                                     path.path_reservoir,
                                                                     dummy_hit,
                                                                     path_is_delta_event(path),
                                                                     path_is_transmission_event(path),
                                                                     path_is_specular_bounce(path),
                                                                     light_pdf,
                                                                     GEOMETRY_LIGHT_ENV_MAP,
                                                                     Le,
                                                                     path.dir,
                                                                     path.prev_scatter_pdf,
                                                                     1.f);
                    }
                }
            }
        }
    }

    path_terminate(path);
}


void path_finalize(inout PATH_STATE path) {
    path_builder_finilize(path.path_reservoir);
}


daxa_f32vec3 path_output(inout PATH_STATE path) {

    path_reservoir_finalize_RIS(path.path_reservoir);
    
    // Write color directly to frame buffer.
    daxa_f32vec3 color = path.path_reservoir.F * path.path_reservoir.weight;

    if (any(isinf(color)) || any(isnan(color))) color = vec3(0.0);

    set_output_path_reservoir_by_index(path.id, path.path_reservoir);

    return color;
}



PATH_RESERVOIR trace_restir_path_tracing(const SCENE_PARAMS params, const daxa_i32vec2 index, const daxa_u32vec2 rt_size, Ray ray, INTERSECT i, inout daxa_u32 seed, inout daxa_f32vec3 throughput) {
    PATH_STATE path;
    generate_path(path, index, rt_size, i.instance_hit, ray, seed, params.max_depth);

    if(path_handle_primary_hit(params, path, i)) {
        do
        {
            path_next_vertex(path, i);

            daxa_b32 is_hit = path_is_hit(path);
// #if SER == 1
//             reorderThreadNV(daxa_u32(is_hit), 1);
// #endif // SER == 1         

            if (is_hit)
            {   
                path_handle_hit(params, path, i);
            }
            else
            {
                path_handle_miss(params, path, i);
            }
        } while(path_is_active(path));
    }

    path_finalize(path);

    throughput = path_output(path);

    seed = path.seed;

    return path.path_reservoir;
}


daxa_f32vec3 trace_random_replay_path_hybrid_simple(const SCENE_PARAMS params, const INSTANCE_HIT hit, INTERSECT i, const Ray ray, const daxa_i32 path_flags, const daxa_u32 init_random_seed, out INSTANCE_HIT dst_rc_prev_vertex_hit, out daxa_f32vec3 dst_rc_prev_vertex_wo) {
    PATH_STATE path;

    daxa_u32 path_length = path_reservoir_get_path_length(path_flags);
    daxa_u32 reconnection_length = path_reservoir_get_reconnection_length(path_flags);

    daxa_b32 is_rc_vertex_escaped_vertex = path_length + 1 == reconnection_length;
    generate_random_replay_path(path, hit, ray, init_random_seed, path_length, path_reservoir_last_vertex_NEE(path_flags), is_rc_vertex_escaped_vertex);
    path.use_hybrid_shift = true;
    path.is_replay_for_hybrid_shift = true;
    path.path_builder.rc_vertex_length = reconnection_length;

    dst_rc_prev_vertex_hit = INSTANCE_HIT(MAX_INSTANCES, MAX_PRIMITIVES);
    dst_rc_prev_vertex_wo = daxa_f32vec3(0.0);

    path.origin = i.world_hit;

    // this is also applicable for random number reuse
    path.path_builder.path_flags = 0;
    path_flags_transform_bounces_information(path.path_builder.path_flags, path_flags);

    // set up the two scatter directions (or half vectors) for reuse
    generate_replay_primary_scatter_ray(params, path, i, daxa_f32vec3(0.0));
    if (path_is_active(path)) {
        path_next_vertex(path, i);
    } 
    else
    {
        return daxa_f32vec3(0.0);
    }

    while (path_is_active(path) && path_is_hit(path))
    {
        // Volume scattering is ignored
        // Handle surface hit
        if (path_is_active(path))
        {
            if (path_is_hit(path))
            {
                path_handle_hit(params, path, i);
            }
        }

        // Move to the next path vertex.
        if (path_is_active(path) && path_is_hit(path))
            path_next_vertex(path, i);
    }

    // Handle the miss and terminate path.
    if (path_is_active(path))
    {
        path_handle_miss(params, path, i);

        // non-invertible: path length doesn't match
        if (path.path_length != path_length)
        {
            return daxa_f32vec3(0.0);
        }
    }

    dst_rc_prev_vertex_hit = INSTANCE_HIT(MAX_INSTANCES, MAX_PRIMITIVES);

    daxa_f32vec3 L = daxa_f32vec3(1.0);

    if (reconnection_length <= path_length || is_rc_vertex_escaped_vertex)
    {
        dst_rc_prev_vertex_hit = path.rc_prev_vertex_hit;
        dst_rc_prev_vertex_wo = path.rc_prev_vertex_wo;
        L = path_get_current_thp(path);
    }
    else // this branch is the case where rcVertex does not exist (or infinitely far)
    {
        L = path.L;
    }

    return L;
}



void path_tracer_trace_temporal_update(const INTERSECT dst_primary_intersection, inout PATH_RESERVOIR src_reservoir) {
    // TODO: complete this function
}




#endif // PATH_TRACER_GLSL_GLSL