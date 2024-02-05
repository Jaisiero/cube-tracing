// indirect_illumination.glsl
#ifndef INDIRECT_ILLUMINATION_GLSL
#define INDIRECT_ILLUMINATION_GLSL
#include <daxa/daxa.inl>
#include "shared.inl"
#include "primitives.glsl"
#include "light.glsl"
#include "path_state.glsl"
#extension GL_EXT_ray_query : enable

struct PATH_VERTEX
{
    daxa_u32 index;
    daxa_f32vec3 position;
    daxa_f32vec3 normal;
};


daxa_b32 next_vertex(INTERSECT i, daxa_u32 seed) {

    call_scatter.hit = i.world_hit;
    call_scatter.nrm = i.world_nrm;
    call_scatter.ray_dir = i.wi;
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
    prd.seed = call_scatter.seed;
    prd.world_hit = call_scatter.hit;
    prd.world_nrm = call_scatter.nrm;
    prd.ray_scatter_dir = call_scatter.scatter_dir;

    return !prd.done;
}



daxa_b32 path_handle_emissive_hit(inout PATH_STATE path, MATERIAL mat) {
    
    if(mat.emission == daxa_f32vec3(0.0)) {
        return false;
    }

    daxa_f32vec3 attenuated_emission = daxa_f32vec3(0.0);

    daxa_f32 light_pdf = 0.f;

    daxa_f32 mis_weight = 1.f;
    daxa_f32vec3 Lr = daxa_f32vec3(0.0);

    // TODO: complete this function
    // if(no primary hit) {
    //     
    // }

    // Acumulate emitted radiance weighted by path throughput and mis weight
    Lr = path_reservoir_get_current_thp(path) * mat.emission * mis_weight;

    attenuated_emission = path_reservoir_get_current_thp(path) * mat.emission;

    path.L += Lr;
    // will change this to path.IsDelta() if ScreenSpaceReSTIR can handle transmission
    // TODO: if (!isLightSamplable && path.length == 1) path.LDeltaDirect += Lr;

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

    // TODO: complete this function

    return true;
}


daxa_b32 path_handle_sample_light(inout PATH_STATE path, MATERIAL mat, INTERSECT i, daxa_u32 seed) {
    


    daxa_b32 valid_sample = false;
    // {
    //     // Setup path vertex.
    //     PATH_VERTEX vertex = PATH_VERTEX(path.path_length + 1, i.world_hit, i.world_nrm);

    //     // Determine if upper/lower hemispheres need to be sampled.
    //     bool sampleUpperHemisphere = ((lobes & (uint)LobeType::NonDeltaReflection) != 0);
    //     if (!kUseLightsInDielectricVolumes && path.isInsideDielectricVolume())
    //         sampleUpperHemisphere = false;
    //     bool sampleLowerHemisphere = ((lobes & (uint)LobeType::NonDeltaTransmission) != 0);

    //     // Sample a light.

    //     validSample = generateLightSample(vertex, sampleUpperHemisphere, sampleLowerHemisphere, path.sg, ls);

    //     path.setLightSampled(sampleUpperHemisphere, sampleLowerHemisphere);
    // }

//                     if (validSample)
//                 {
//                     // Apply MIS weight.
//                     float misWeight = 1.f;
//                     float scatterPdf = 0.f;

//                     if (kUseMIS && ls.lightType != (uint)LightSampleType::Analytic)
//                     {
//                         scatterPdf = evalPdfBSDF(sd, ls.dir);

//                         misWeight *= evalMIS(1, ls.pdf, 1, scatterPdf);
//                     }
//                     ls.Li *= misWeight;

//                     float3 weight = evalBSDFCosine(sd, ls.dir);

//                     float3 Lr = weight * ls.Li * path.getCurrentThp();

//                     if (any(Lr > 0.f))
//                     {
//                         const Ray ray = ls.getVisibilityRay();
//                         bool visible = traceVisibilityRay(ray);
//                         if (visible)
//                         {
//                             if (!path.enableRandomReplay || terminateRandomReplayForNEE)
//                                 path.L += Lr;

//                             if (ls.lightType == (uint)LightSampleType::Analytic && ls.pdf == 0.f)
//                             {
//                                 ls.pdf = getAnalyicSelectionProbability(); // analytic light doesn't have a solid angle PDF.
//                             }

//                             // daqi: here we are adding the path terminated with an NEE event
//                             // if we have enabled random replay, we know that we are going to use this path

//                             if (PathSamplingMode(kPathSamplingMode) != PathSamplingMode::PathTracing)
//                             {
//                                 if (is_rcVertex)
//                                 {
//                                     weight = 1.f;
//                                 }
// #if BPR
//                                 if (!is_rcVertex)
//                                 {
//                                     path.rcVertexPathTreeIrradiance += weight * ls.Li * path.thp;
//                                 }

//                                 bool selected = path.pathBuilder.addNeeVertex(params, path.length, ls.dir, Lr, 
//                                     is_rcVertex ? weight * ls.Li * path.thp : path.rcVertexPathTreeIrradiance, path.useHybridShift,
//                                     path.russianRoulettePdf, misWeight, ls.pdf, ls.lightType, path.pathReservoir, path.enableRandomReplay);
// #else
//                                 bool selected = path.pathBuilder.addNeeVertex(params, path.length, ls.dir, Lr, weight * ls.Li * path.thp, path.useHybridShift,
//                                     path.russianRoulettePdf, misWeight, ls.pdf, ls.lightType, path.pathReservoir, path.enableRandomReplay);
// #endif
//                             }
//                         }
//                     }
//                 }


    return valid_sample;
}


daxa_b32 path_handle_primary_hit(inout PATH_STATE path, MATERIAL mat, INTERSECT i, daxa_u32 seed) {
    

    // save as previous path origin to compute distance between vertices
    daxa_f32vec3 prev_path_origin = path.origin;

    // Compute origin for rays traced from this path vertex.
    path.origin = i.world_hit;

    // TODO: 
    // // // Determine if BSDF supports sampling with next-event estimation.
    // //     // The available lobes depend on the material.
    // //     uint lobes = getBSDFLobes(sd);

    // //     bool supportsNEE = (lobes & (uint)LobeType::NonDelta) != 0;


    // // daqi: when doing random number replay, we will terminate the path when the length reaches the base path length and 
    // // when the path types match. In this case, if the base path is a NEE path (as opposed to an escaped path), we should terminate when we 
    // // find that offset path can also be an NEE path
    // daxa_b32 terminate_random_replay_for_NEE = path.enable_random_replay && path.path_length == path.random_replay_length && path.random_replay_is_NEE;

    // daxa_b32 is_rc_vertex = false;

    // daxa_b32 is_far_field = length(path.origin - prev_path_origin) >= NEAR_FIELD_DISTANCE;

    // // TODO: every material now is diffuse
    // // daxa_b32 isCurrentVertexClassifiedAsRough =
    // //     kSeparatePathBSDF ? hasRoughComponent(sd, params.specularRoughnessThreshold) : classifyAsRough(sd, SPECULAR_ROUGHNESS_THRESHOLD);

    // daxa_b32 is_last_vertex_acceptable_for_rc_prev = path.is_last_vertex_classified_as_rough;

    // TODO: 
    // daqi: if we are not doing a hybrid shift replay, we should check if current vertex satisfy the condition to be used as a rcVertex


    path_set_light_sampled(path, false, false);

    // generate kNEESamples light samples
    // cache (NEE sampling) seed for temporal validation (only possible for non early direction reuse since it uses the cachedRandomSeed slot)
    if (path.path_length == path.path_builder.rc_vertex_length)
    {
        path.path_builder.cached_random_seed = path.seed;
    }


    path_handle_sample_light(path, mat, i, seed);


    return true;
}


void indirect_illumination(const daxa_i32vec2 index, const daxa_u32vec2 rt_size, Ray ray, MATERIAL mat, INTERSECT i, daxa_u32 seed, daxa_u32 max_depth, daxa_u32 light_count, daxa_u32 object_count, inout daxa_f32vec3 throughput) {
    
    
    // prd.throughput = vec3(1.0);
    prd.seed = seed;
    prd.depth = max_depth;
    prd.world_hit = i.world_hit;
    prd.distance = i.distance;
    prd.world_nrm = i.world_nrm;
    prd.ray_scatter_dir = i.wi;
    prd.mat_index = i.material_idx;
    prd.instance_hit = i.instance_hit;
    // prd.done = true;

    PATH_STATE path;
    generate_path(path, index, rt_size, i.instance_hit, ray, seed);

    // path_handle_emissive_hit(path, mat);

    path_handle_primary_hit(path, mat, i, seed);

    

    next_vertex(i, seed);


    // TODO: Do something with path here for primary hit

    for (;;)
    {

        HIT_INFO_INPUT hit = HIT_INFO_INPUT(
            i.world_hit,
            i.world_nrm,
            i.distance,
            i.wi,
            i.instance_hit,
            i.material_idx,
            seed,
            max_depth);
        Ray scattered_ray = Ray(i.world_hit, i.wi);

        if(i.is_hit) {
            
            daxa_u32 light_index = min(urnd_interval(prd.seed, 0, light_count), light_count - 1);

            LIGHT light = get_light_from_light_index(light_index);

            daxa_f32 pdf_out = 1.0;

            // TODO: Handle hit path here for subsequent hits

            daxa_f32vec3 radiance = direct_mis(scattered_ray, hit, light_count, light, object_count, i.mat, i, pdf_out, true, true);

            prd.hit_value *= radiance;
            prd.hit_value += i.mat.emission;
            prd.done = false;
        }
        else
        {
            // TODO: Handle miss path here for subsequent hits

            prd.done = true;
            prd.hit_value *= calculate_sky_color(
                deref(p.status_buffer).time,
                deref(p.status_buffer).is_afternoon,
                ray.direction);
        }

        prd.depth--;
        daxa_b32 done = prd.done || prd.depth == 0;
// #if SER == 1
//     reorderThreadNV(daxa_u32(done), 1);
// #endif // SER
        if (done)
            break;
            
        prd.done = true; // Will stop if a reflective material isn't hit
    }
    throughput += prd.hit_value;

}

#endif // INDIRECT_ILLUMINATION_GLSL