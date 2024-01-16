// bounce.glsl
#ifndef BOUNCE_GLSL
#define BOUNCE_GLSL
#include <daxa/daxa.inl>
#include "shared.inl"
#include "primitives.glsl"
#extension GL_EXT_ray_query : enable

// SCATTER
INTERSECT intersect(Ray ray, inout HIT_INFO_INPUT hit)
{
    // prd_indirect.instance_id = MAX_INSTANCES;
    // prd_indirect.seed = hit.seed;
    // prd_indirect.depth = hit.depth;
    daxa_f32 t_min = 0.0001;
    daxa_f32 t_max = 100000.0;
    daxa_f32vec3 ray_origin = ray.origin;
    daxa_f32vec3 ray_dir = ray.direction;
    daxa_u32 cull_mask = 0xff;
    daxa_u32 flags = gl_RayFlagsNoneEXT;

    
    daxa_u32 instance_id = MAX_INSTANCES;
    daxa_u32 primitive_id = 0;
    daxa_f32vec3 int_hit = daxa_f32vec3(0.0);
    daxa_f32vec3 int_nor = daxa_f32vec3(0.0);
    daxa_b32 is_hit = false;
    daxa_f32 t_hit = 0.0;
    
    rayQueryEXT ray_query;

    rayQueryInitializeEXT(ray_query, daxa_accelerationStructureEXT(p.tlas),
                          flags,
                          cull_mask, ray.origin, t_min, ray.direction, t_max);

    while (rayQueryProceedEXT(ray_query))
    {
        uint type = rayQueryGetIntersectionTypeEXT(ray_query, false);
        if (type ==
            gl_RayQueryCandidateIntersectionAABBEXT)
        {
            // get instance id
            instance_id = rayQueryGetIntersectionInstanceCustomIndexEXT(ray_query, false);

            // Get primitive id
            primitive_id = rayQueryGetIntersectionPrimitiveIndexEXT(ray_query, false);

            if(is_hit_from_ray(ray, instance_id, primitive_id, t_hit, int_hit, int_nor, false, false)) {
                rayQueryGenerateIntersectionEXT(ray_query, t_hit);

                daxa_u32 type_commited = rayQueryGetIntersectionTypeEXT(ray_query, true);

                if (type_commited ==
                    gl_RayQueryCommittedIntersectionGeneratedEXT)
                {
                    is_hit = true;
                    break;
                }
            }
        }
    }

    rayQueryTerminateEXT(ray_query);

    // hit.seed = prd_indirect.seed;
    // hit.hit_value = prd_indirect.hit_value;
    // primitive_id = prd_indirect.primitive_id;
    // daxa_f32vec3 intersected_hit = prd_indirect.hit;
    // daxa_f32vec3 intersected_nrm = prd_indirect.nrm;
    MATERIAL intersected_mat;

    if(is_hit) {
        intersected_mat = get_material_from_instance_and_primitive_id(instance_id, primitive_id);
    }

    return INTERSECT(is_hit, int_hit, int_nor, instance_id, primitive_id, intersected_mat);
}
#endif // BOUNCE_GLSL