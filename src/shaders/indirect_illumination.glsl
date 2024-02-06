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


daxa_b32 generate_scatter_ray(INTERSECT i, inout daxa_u32 seed) {

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

    return !prd.done;
}



daxa_b32 path_generate_scatter_ray(inout PATH_STATE path, INTERSECT i) {

    daxa_b32 valid = generate_scatter_ray(i, path.seed);

    if(valid) {
        // TODO: weight is always albedo for now because it is always a diffuse material
        daxa_f32vec3 weight = i.mat.diffuse;
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

        // TODO: Handle other reflexions here (pathtracer:357)
        path_increment_bounces(path, BOUNCE_TYPE_DIFFUSE);


        path.normal = i.world_nrm;

        valid = any(greaterThan(path.thp,daxa_f32vec3(0.0)));

        if(valid) {
            if(path.path_length <= path.path_builder.rc_vertex_length) {
               path_record_prefix_thp(path);
            }
        }

    }

    return valid;
}

void path_next_vertex(inout PATH_STATE path) {

    INTERSECT i = intersect(Ray(path.origin, path.dir));

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
    
    // TODO: complete this function
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


daxa_b32 path_handle_primary_hit(inout PATH_STATE path, INTERSECT i) {
    

    // TODO: complete this function
    // Compute origin for rays traced from this path vertex.
    path.origin = i.world_hit;


    path_set_light_sampled(path, false, false);

    if (path.path_length == 0)
    {
        path.path_reservoir.init_random_seed = path.seed;
    }

    daxa_b32 valid = path_generate_scatter_ray(path, i);

    // TODO: Check if (pathtracer:1403) necessary here


    return valid;
}


void path_handle_hit(inout PATH_STATE path, INTERSECT i, daxa_u32 light_count, daxa_u32 object_count) {

    // Upon hit:
    // - Load vertex/material data
    // - Compute volume absorption
    // - Compute MIS weight if path.length > 0 and emissive hit
    // - Add emitted radiance
    // - Sample light(s) using shadow rays
    // - Sample scatter ray or terminate

    // TODO: Sample emissive (add escape vertex) (pathtracer:1034)
    // path_handle_emissive_hit(path, mat);

    // TODO: check if the path is terminated (more bounces) (pathtracer:1123)

    // TODO: Go forward hit (pathtracer:1130)

    // TODO: Check if rc_vertex (pathtracer:1165)

    // TODO: Sample light (add NEE vertex) (pathtracer:1265)

    // daxa_u32 light_index = min(urnd_interval(prd.seed, 0, light_count), light_count - 1);

    // LIGHT light = get_light_from_light_index(light_index);

    // daxa_f32 pdf_out = 1.0;

    // // daxa_f32vec3 radiance = direct_mis(scattered_ray, hit, light_count, light, object_count, i.mat, i, pdf_out, true, true);

    // // prd.hit_value *= radiance;
    // // prd.hit_value += i.mat.emission;

    // TODO: Russian roulette (pathtracer:1378)

    // TODO: Scatter ray (pathtracer:1400)
    daxa_b32 valid = path_generate_scatter_ray(path, i);

    // TODO: forbid current vertex being rcVertex if conditions are not met (pathtracer:1403)

    // TODO: cache seed for temporal validation (pathtracer:1427)

    // TODO: save the incoming direction on rcVertex (pathtracer:1433)

    // TODO: save more things afterwards

    // TODO: if path is terminated, break (pathtracer:1456)

    // TODO: Check if last bounce for replay only (pathtracer:1459)

    // TODO: Check other things to invalidate the path (pathtracer:1462)

    // TODO: If not valid, terminate path (pathtracer:1467)

    prd.done = false;
}


void path_handle_miss(inout PATH_STATE path, INTERSECT i, daxa_u32 seed) {
    // TODO: Handle miss path here for subsequent hits
    // Upon miss:
    // - Compute MIS weight if previous path vertex sampled a light
    // - Evaluate environment map
    // - Write guiding data
    // - Terminate the path

    prd.done = true;
    prd.hit_value *= calculate_sky_color(
        deref(p.status_buffer).time,
        deref(p.status_buffer).is_afternoon,
        i.wo);
}

void indirect_illumination_restir_path_tracing(const daxa_i32vec2 index, const daxa_u32vec2 rt_size, Ray ray, INTERSECT i, daxa_u32 seed, daxa_u32 max_depth, daxa_u32 light_count, daxa_u32 object_count, inout daxa_f32vec3 throughput) {
    

    PATH_STATE path;
    generate_path(path, index, rt_size, i.instance_hit, ray, seed);

    path_handle_primary_hit(path, i);

    max_depth = max(1, max_depth);

    // TODO: Do something with path here for primary hit

    do
    {
        path_next_vertex(path);

        if (path_is_hit(path))
        {   
            path_handle_hit(path, i, light_count, object_count);
        }
        else
        {
            path_handle_miss(path, i, seed);
        }

        max_depth--;
        daxa_b32 done = path_is_terminated(path) || max_depth == 0;
        if (done)
            break;
    } while(path_is_active(path));
    // TODO: Check this
    throughput += path.thp + path.prefix_thp;
}




void indirect_illumination_path_tracing(const daxa_i32vec2 index, const daxa_u32vec2 rt_size, Ray ray, MATERIAL mat, INTERSECT i, daxa_u32 seed, daxa_u32 max_depth, daxa_u32 light_count, daxa_u32 object_count, inout daxa_f32vec3 throughput) {
    
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

    generate_scatter_ray(i, seed);

    for (;;)
    {

        HIT_INFO_INPUT hit = HIT_INFO_INPUT(
            i.world_hit,
            i.world_nrm,
            i.distance,
            i.wo,
            i.instance_hit,
            i.material_idx,
            seed,
            max_depth);
        Ray scattered_ray = Ray(i.world_hit, i.wo);

        if(i.is_hit) {
            
            daxa_u32 light_index = min(urnd_interval(prd.seed, 0, light_count), light_count - 1);

            LIGHT light = get_light_from_light_index(light_index);

            daxa_f32 pdf_out = 1.0;

            daxa_f32vec3 radiance = direct_mis(scattered_ray, hit, light_count, light, object_count, i.mat, i, pdf_out, true, true);

            prd.hit_value *= radiance;
            prd.hit_value += i.mat.emission;
            prd.done = false;
        }
        else
        {
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





void indirect_illumination(const daxa_i32vec2 index, const daxa_u32vec2 rt_size, Ray ray, MATERIAL mat, INTERSECT i, daxa_u32 seed, daxa_u32 max_depth, daxa_u32 light_count, daxa_u32 object_count, inout daxa_f32vec3 throughput) {
#if RESTIR_PT_ON == 1
    indirect_illumination_restir_path_tracing(index, rt_size, ray, i, seed, max_depth, light_count, object_count, throughput);
#else
    indirect_illumination_path_tracing(index, rt_size, ray, mat, i, seed, max_depth, light_count, object_count, throughput);
#endif
}
#endif // INDIRECT_ILLUMINATION_GLSL