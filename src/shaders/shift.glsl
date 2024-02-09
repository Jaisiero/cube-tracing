// path_tracer.glsl
#ifndef SHIFT_GLSL
#define SHIFT_GLSL
#define DAXA_RAY_TRACING 1
#include <daxa/daxa.inl>
#include "shared.inl"
#include "path_state.glsl"
#include "path_reservoir.glsl"



// dstPdf * dstJacobian transforms pdf in dst space to src space
// srcPdf / dstJacobian transforms pdf in src space to dst space
daxa_f32vec3 compute_shifted_integrand_reconnection(const SCENE_PARAMS params, inout daxa_f32 dst_jacobian, const INTERSECT dst_primary_intersection, const INTERSECT src_primary_intersection, inout PATH_RESERVOIR src_reservoir, daxa_b32 eval_visibility)
{
    return daxa_f32vec3(0.0f);

    // daxa_f32vec3 dstCachedJacobian;
    // dstJacobian = 0.f;

    // daxa_i32 rcVertexLength = !useHybridShift ? 1 : src_reservoir.pathFlags.rcVertexLength();

    // HitInfo rcVertexHit = src_reservoir.rcVertexHit.getHitInfo();
    // daxa_f32vec3 rcVertexIrradiance = src_reservoir.rcVertexIrradiance[0];
    // daxa_f32vec3 rcVertexWi = src_reservoir.rcVertexWi[0];
    // daxa_b32 rcVertexHitExists = rcVertexHit.isValid();

    // daxa_b32 isTransmission = src_reservoir.pathFlags.decodeIsTransmissionEvent(true);
    // daxa_u32 allowedSampledTypes1 = getAllowedBSDFFlags(src_reservoir.pathFlags.decodeIsSpecularBounce(true));

    // srcPrimarySd.posW = srcPrimarySd.computeNewRayOrigin(!isTransmission);
    // dstPrimarySd.posW = dstPrimarySd.computeNewRayOrigin(!isTransmission);

    // if (!rcVertexHitExists) 
    // {
    //     daxa_f32vec3 dst_integrand = 0.f;
    //     // are we having a infinite light as rcVertex?
    //     if (kUseMIS && src_reservoir.pathFlags.lightType() == (uint)PathTracer::LightSampleType::EnvMap && src_reservoir.pathFlags.pathLength() + 1 == rcVertexLength && !src_reservoir.pathFlags.lastVertexNEE())
    //     {
    //         daxa_f32vec3 wi = rcVertexWi;
    //         daxa_b32 isVisible = evalSegmentVisibility(dstPrimarySd.posW, wi, true); // test along a direction
    //         if (isVisible)
    //         {
    //             daxa_f32 srcPDF1 = useCachedJacobian ? src_reservoir.cachedJacobian.x : evalPdfBSDF(srcPrimarySd, wi);
    //             daxa_f32 dstPDF1All;
    //             daxa_f32 dstPDF1 = evalPdfBSDF(dstPrimarySd, wi, dstPDF1All, allowedSampledTypes1);
    //             dstCachedJacobian.x = dstPDF1;
    //             daxa_f32vec3 dstF1 = evalBSDFCosine(dstPrimarySd, wi, allowedSampledTypes1);
    //             daxa_f32 misWeight = PathTracer::evalMIS(1, dstPDF1All, 1, src_reservoir.lightPdf);//   dstPDF1 / (dstPDF1 + src_reservoir.lightPdf);
    //             dst_integrand = dstF1 / dstPDF1 * misWeight * rcVertexIrradiance;
    //             dstJacobian = dstPDF1 / srcPDF1;
    //         }
    //     }

    //     if (useCachedJacobian)
    //         src_reservoir.cachedJacobian = dstCachedJacobian;

    //     // fill in rcVertex0 information
    //     if (isJacobianInvalid(dstJacobian)) dstJacobian = 0.f;
    //     if (any(isnan(dst_integrand) || isinf(dst_integrand))) return 0.f;

    //     return dst_integrand;
    // }

    // daxa_b32 isRcVertexFinal = src_reservoir.pathFlags.pathLength() == rcVertexLength;
    // daxa_b32 isRcVertexEscapedVertex = src_reservoir.pathFlags.pathLength() + 1 == rcVertexLength && !src_reservoir.pathFlags.lastVertexNEE();
    // daxa_b32 isRcVertexNEE = isRcVertexFinal && src_reservoir.pathFlags.lastVertexNEE();

    // daxa_b32 isDelta1 = src_reservoir.pathFlags.decodeIsDeltaEvent(true);
    // daxa_b32 isDelta2 = src_reservoir.pathFlags.decodeIsDeltaEvent(false);

    // // delta bounce before/after rcVertex (if isRcVertexNEE, deltaAfterRc won't be set)
    // if (isDelta1 || isDelta2) return 0.f;

    // ShadingData rcVertexSd = loadShadingDataWithPrevVertexPosition(rcVertexHit, dstPrimarySd.posW, false);

    // // need to evaluate source PDF of BSDF sampling
    // daxa_f32vec3 dstConnectionV = -rcVertexSd.V; // direction point from dst primary hit point to reconnection vertex
    // daxa_f32vec3 srcConnectionV = normalize(rcVertexSd.posW - srcPrimarySd.posW);

    // daxa_f32vec3 shiftedDisp = rcVertexSd.posW - dstPrimarySd.posW;
    // daxa_f32 shifted_dist2 = dot(shiftedDisp, shiftedDisp);
    // daxa_f32 shifted_cosine = abs(dot(rcVertexSd.faceN, -dstConnectionV));

    // if ((params.localStrategyType & (uint)LocalStrategy::DistanceCondition) && useHybridShift)
    // {
    //     daxa_b32 isFarField = sqrt(shifted_dist2) >= params.nearFieldDistance;
    //     if (!isFarField) return 0.f;
    // }


    // dstCachedJacobian.z = shifted_cosine / shifted_dist2;
    // daxa_f32 Jacobian;
    // if (useCachedJacobian) Jacobian = dstCachedJacobian.z / src_reservoir.cachedJacobian.z;
    // else
    // {
    //     daxa_f32vec3 originalDisp = rcVertexSd.posW - srcPrimarySd.posW;
    //     daxa_f32 original_dist2 = dot(originalDisp, originalDisp);
    //     daxa_f32 original_cosine = abs(dot(rcVertexSd.faceN, -srcConnectionV));
    //     Jacobian = dstCachedJacobian.z* original_dist2 / original_cosine;
    // }
    // if (isJacobianInvalid(Jacobian)) return 0.f;

    // // assuming BSDF sampling
    // assert(kUseBSDFSampling);

    // // assuming bsdf sampling
    // daxa_f32 dstPDF1All = 0.f;
    // daxa_f32 dstPDF1 = evalPdfBSDF(dstPrimarySd, dstConnectionV, dstPDF1All, allowedSampledTypes1);
    // dstCachedJacobian.x = dstPDF1;
    // daxa_f32 srcPDF1 = useCachedJacobian ? src_reservoir.cachedJacobian.x : evalPdfBSDF(srcPrimarySd, srcConnectionV, allowedSampledTypes1); //

    // Jacobian *= dstPDF1 / srcPDF1;

    // if (isJacobianInvalid(Jacobian)) return 0.f;

    // daxa_f32vec3 dstF1 = evalBSDFCosine(dstPrimarySd, dstConnectionV, allowedSampledTypes1);

    // daxa_f32 dstRcVertexScatterPdfAll = 0.f;
    // daxa_f32 dstPDF2 = 1.f;
    // daxa_f32 dstRcVertexScatterPdf = 1.f; 
    // daxa_f32 srcRcVertexScatterPdf = 1.f;  

    // daxa_u32 allowedSampledTypes2 = isRcVertexNEE ? -1 : getAllowedBSDFFlags(src_reservoir.pathFlags.decodeIsSpecularBounce(false));

    // if (!isRcVertexEscapedVertex)
    // {
    //     // assuming bsdf sampling
    //     dstRcVertexScatterPdf = evalPdfBSDF(rcVertexSd, rcVertexWi, dstRcVertexScatterPdfAll, allowedSampledTypes2);
    //     dstCachedJacobian.y = dstRcVertexScatterPdf;
    //     srcRcVertexScatterPdf = useCachedJacobian ? src_reservoir.cachedJacobian.y : evalPdfBSDFWithV(rcVertexSd, -srcConnectionV, rcVertexWi, allowedSampledTypes2);

    //     if (!isRcVertexNEE) dstPDF2 = dstRcVertexScatterPdf;
    //     else dstPDF2 = src_reservoir.lightPdf;
    // }

    // daxa_f32vec3 dstF2 = 1.f;

    // if (!isRcVertexEscapedVertex)
    //     dstF2 = evalBSDFCosine(rcVertexSd, rcVertexWi, allowedSampledTypes2);

    // // connection point behind surface
    // if (all(dstF1 == 0.f) || all(dstF2 == 0.f)) return 0.f;

    // //////
    // daxa_f32vec3 dst_integrandNoF1 = dstF2 / dstPDF2 * rcVertexIrradiance;
    // daxa_f32vec3 dst_integrand = dstF1 / dstPDF1 * dst_integrandNoF1; // TODO: might need to reevaluate Le for changing emissive lights

    // if (isRcVertexEscapedVertex)
    // {
    //     daxa_f32 misWeight = PathTracer::evalMIS(1, dstPDF1All, 1, src_reservoir.lightPdf);// dstPDF1 / (src_reservoir.lightPdf + dstPDF1);
    //     dst_integrand *= misWeight;
    // }

    // // MIS weight
    // if (isRcVertexFinal && kUseMIS)
    // {
    //     if (src_reservoir.pathFlags.lightType() != (uint)PathTracer::LightSampleType::Analytic) // TODO: optimize way this check
    //     {
    //         daxa_f32 lightPdf = src_reservoir.lightPdf;
    //         daxa_f32 misWeight = PathTracer::evalMIS(1, isRcVertexNEE ? lightPdf : dstRcVertexScatterPdfAll, 1, isRcVertexNEE ? dstRcVertexScatterPdfAll : lightPdf);
    //         dst_integrand = dst_integrand * misWeight; 
    //         dst_integrandNoF1 = dst_integrandNoF1 * misWeight;
    //         if (!isRcVertexNEE)
    //             Jacobian *= dstRcVertexScatterPdf / srcRcVertexScatterPdf;
    //     }
    // }

    // // need to account for non-identity jacobian due to BSDF sampling
    // if (!isRcVertexFinal && !isRcVertexEscapedVertex)
    // {
    //     Jacobian *= dstRcVertexScatterPdf / srcRcVertexScatterPdf;
    // }

    // if (isJacobianInvalid(Jacobian)) return 0.f;

    // // Evaluate visibility: vertex 1 <-> vertex 2 (reconnection vertex).
    // if (evalVisibility)
    // {
    //     daxa_b32 isVisible = evalSegmentVisibility(dstPrimarySd.posW, rcVertexSd.posW);
    //     if (!isVisible)
    //         return 0.f;
    // }

    // if (any(isnan(dst_integrand) || isinf(dst_integrand))) return 0.f;

    // if (params.rejectShiftBasedOnJacobian)
    // {
    //     if (Jacobian > 0.f && (max(Jacobian, 1 / Jacobian) > 1 + params.jacobianRejectionThreshold))
    //     {
    //         // discard based on Jacobian (unbiased)
    //         Jacobian = 0.f;
    //         dst_integrand = 0.f;
    //     }
    // }

    // dstJacobian = Jacobian;

    // if (useCachedJacobian)
    //     src_reservoir.cachedJacobian = dstCachedJacobian;

    // return dst_integrand;
}




daxa_f32vec3 compute_shifted_integrand_(const SCENE_PARAMS params, inout daxa_f32 dst_jacobian, const INSTANCE_HIT dst_primary_hit, const INTERSECT dst_primary_intersection,
    const INTERSECT src_primary_intersection, inout PATH_RESERVOIR src_reservoir, RECONNECTION_DATA rc_data, daxa_b32 eval_visibility, daxa_b32 use_prev, daxa_b32 temporal_update_for_dynamic_scene)
{
    dst_jacobian = 0.f;

    if (src_reservoir.weight == 0.f) return daxa_f32vec3(0.0f);

    // if (ShiftMapping(kShiftStrategy) == ShiftMapping::Reconnection)
    // {

        if (temporal_update_for_dynamic_scene && params.temporal_update_for_dynamic_scene)
        {
            path_tracer_trace_temporal_update(dst_primary_intersection, src_reservoir);
        }

        return compute_shifted_integrand_reconnection(params, dst_jacobian, dst_primary_intersection, src_primary_intersection, src_reservoir, eval_visibility);
    // }
    // else if (ShiftMapping(kShiftStrategy) == ShiftMapping::RandomReplay)
    // {
    //     return computeShiftedIntegrandRandomReplay(params, use_prev, dst_jacobian, dstPrimaryHitPacked, dstPrimarySd, srcPrimarySd, src_reservoir);
    // }
    // else if (ShiftMapping(kShiftStrategy) == ShiftMapping::Hybrid)
    // {
    //     return computeShiftedIntegrandHybrid(params, use_prev, temporal_update_for_dynamic_scene, dst_jacobian, dstPrimaryHitPacked, dstPrimarySd, srcPrimarySd, src_reservoir, rc_data, eval_visibility);
    // }

    // return daxa_f32vec3(0.0f);
}



daxa_f32vec3 compute_shifted_integrand(const SCENE_PARAMS params, inout daxa_f32 dst_jacobian, const INSTANCE_HIT dst_primary_hit, const INTERSECT dst_primary_intersection,
    const INTERSECT src_primary_intersection, inout PATH_RESERVOIR src_reservoir, RECONNECTION_DATA rc_data, daxa_b32 eval_visibility, daxa_b32 use_prev, daxa_b32 temporal_update_for_dynamic_scene)
{
    PATH_RESERVOIR temp_path_reservoir = src_reservoir;
    daxa_f32vec3 res = compute_shifted_integrand_(params, dst_jacobian, dst_primary_hit, dst_primary_intersection,
                                                  src_primary_intersection, src_reservoir, rc_data, 
                                                  eval_visibility, use_prev, temporal_update_for_dynamic_scene);
    return res;
}



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
    PATH_RESERVOIR temp_path_reservoir = src_reservoir;
    daxa_f32vec3 dst_integrand = compute_shifted_integrand_(params, dst_jacobian, dst_primary_hit, dst_primary_intersection, src_primary_intersection,
                                                          temp_path_reservoir, rc_data, eval_visibility, false, temporal_update_for_dynamic_scene);

    daxa_b32 selected = path_reservoir_merge(dst_reservoir, dst_integrand, dst_jacobian, temp_path_reservoir, seed, mis_weight, force_merge);

    if (force_merge)
    {
        if (!selected)
            dst_reservoir.F = daxa_f32vec3(0.0f);
        dst_reservoir.M = src_reservoir.M;
        dst_reservoir.weight = src_reservoir.weight;
    }

    return selected;
}


daxa_b32 merge_reservoir_with_resampling_MIS(const SCENE_PARAMS params, const daxa_f32vec3 dst_integrand, daxa_f32 dst_jacobian, inout PATH_RESERVOIR dest_reservoir, const PATH_RESERVOIR temp_dst_reservoir, const PATH_RESERVOIR src_reservoir, inout daxa_u32 seed, daxa_b32 is_spatial_reuse, daxa_f32 mis_weight)
{
    return path_reservoir_merge_with_resampling_MIS(dest_reservoir, dst_integrand, dst_jacobian, temp_dst_reservoir, seed, mis_weight, false);
}


#endif // SHIFT_GLSL