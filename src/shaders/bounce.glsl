// bounce.glsl
#ifndef BOUNCE_GLSL
#define BOUNCE_GLSL
#include <daxa/daxa.inl>
#include "shared.inl"
#extension GL_EXT_ray_query : enable

// SCATTER
INTERSECT intersect(Ray ray, inout HIT_INFO_INPUT hit)
{
    // prd_indirect.instance_id = MAX_INSTANCES - 1;
    // prd_indirect.seed = hit.seed;
    // prd_indirect.depth = hit.depth;
    daxa_f32 t_min = DELTA_RAY;
    daxa_f32 t_max = MAX_DISTANCE - DELTA_RAY;
    daxa_f32vec3 ray_origin = ray.origin;
    daxa_f32vec3 ray_dir = ray.direction;
    daxa_u32 cull_mask = 0xff;
    daxa_u32 ray_flags = gl_RayFlagsNoneEXT;

    
    INSTANCE_HIT instance_hit = INSTANCE_HIT(MAX_INSTANCES - 1, MAX_PRIMITIVES - 1);
    daxa_f32vec3 int_hit = daxa_f32vec3(0.0);
    daxa_f32vec3 int_nor = daxa_f32vec3(0.0);
    daxa_b32 is_hit = false;
    daxa_f32 distance = 0.0;
    daxa_f32mat4x4 model;
    daxa_f32mat4x4 inv_model;
    daxa_u32 material_idx = 0;
    MATERIAL intersected_mat;

// #if SER == 1
#if 0

    hitObjectNV hit_object;
    // Initialize to an empty hit object
    hitObjectRecordEmptyNV(hit_object);

    // Trace the ray
    hitObjectTraceRayNV(hit_object,
                        daxa_accelerationStructureEXT(p.tlas), // topLevelAccelerationStructure
                        ray_flags,                             // rayFlags
                        cull_mask,                             // cullMask
                        1,                                     // sbtRecordOffset
                        0,                                     // sbtRecordStride
                        0,                                     // missIndex
                        ray_origin,                            // ray origin
                        t_min,                                 // ray min range
                        ray_dir,                         // ray direction
                        t_max,                                 // ray max range
                        0                                      // payload (location = 0)
    );

    if (hitObjectIsHitNV(hit_object))
    {

        daxa_u32 instance_id = hitObjectGetInstanceCustomIndexNV(hit_object);

        daxa_u32 primitive_id = hitObjectGetPrimitiveIndexNV(hit_object);

        instance_hit = INSTANCE_HIT(instance_id, primitive_id);

        Ray bounce_ray = Ray(ray_origin, ray_dir);

        // TODO: pass this as a parameter
        daxa_f32vec3 half_extent = vec3(HALF_VOXEL_EXTENT);

        distance = is_hit_from_ray(bounce_ray, instance_hit, half_extent, distance, int_hit, int_nor, model, inv_model, true, false) ? distance : -1.0;

        daxa_f32vec4 int_hit_4 = (model * vec4(int_hit, 1));
        int_hit = (int_hit_4 / int_hit_4.w).xyz;
        int_nor = (transpose(inv_model) * vec4(int_nor, 0)).xyz;
        int_hit += int_nor * DELTA_RAY;
        
        is_hit = true;

        daxa_u32 actual_primitive_index = get_current_primitive_index_from_instance_and_primitive_id(instance_hit);

        material_idx = get_material_index_from_primitive_index(actual_primitive_index);

        intersected_mat = get_material_from_material_index(material_idx);
    }
#else            
    rayQueryEXT ray_query;

    rayQueryInitializeEXT(ray_query, daxa_accelerationStructureEXT(p.tlas),
                          ray_flags,
                          cull_mask, ray.origin, t_min, ray.direction, t_max);

    while (rayQueryProceedEXT(ray_query))
    {
        uint type = rayQueryGetIntersectionTypeEXT(ray_query, false);
        if (type ==
            gl_RayQueryCandidateIntersectionAABBEXT)
        {
            // get instance id
            daxa_u32 instance_id = rayQueryGetIntersectionInstanceCustomIndexEXT(ray_query, false);

            // Get primitive id
            daxa_u32 primitive_id = rayQueryGetIntersectionPrimitiveIndexEXT(ray_query, false);

            instance_hit = INSTANCE_HIT(instance_id, primitive_id);

            daxa_f32vec3 half_extent = daxa_f32vec3(HALF_VOXEL_EXTENT);

            if(is_hit_from_ray(ray, instance_hit, half_extent, distance, int_hit, int_nor, model, inv_model, false, false)) {
                rayQueryGenerateIntersectionEXT(ray_query, distance);

                daxa_u32 type_commited = rayQueryGetIntersectionTypeEXT(ray_query, true);

                if (type_commited ==
                    gl_RayQueryCommittedIntersectionGeneratedEXT)
                {
                    is_hit = true;
                    material_idx = get_material_index_from_instance_and_primitive_id(instance_hit);
                    intersected_mat = get_material_from_material_index(material_idx);
        
                    daxa_f32vec4 int_hit_4 = model * vec4(int_hit, 1);
                    int_hit = int_hit_4.xyz / int_hit_4.w;
                    int_nor = (transpose(inv_model) * vec4(int_nor, 0)).xyz;
                    int_hit += int_nor * DELTA_RAY;
                    break;
                }
            }
        }
    }

    rayQueryTerminateEXT(ray_query);
#endif // SER    

    // hit.seed = prd_indirect.seed;
    // hit.hit_value = prd_indirect.hit_value;
    // primitive_id = prd_indirect.primitive_id;
    // daxa_f32vec3 intersected_hit = prd_indirect.hit;
    // daxa_f32vec3 intersected_nrm = prd_indirect.nrm;

    return INTERSECT(is_hit, distance, int_hit, int_nor, ray.direction, instance_hit, material_idx, intersected_mat);
}
#endif // BOUNCE_GLSL