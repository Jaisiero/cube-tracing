#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>
#include "defines.glsl"
#include "shared.inl"
#include "mat.glsl"
#include "reservoir.glsl"
#include "light.glsl"

#if SER_ON == 1
#extension GL_NV_shader_invocation_reorder : enable
layout(location = 0) hitObjectAttributeNV vec3 hitValue;
#endif


#if defined(DIRECT_ILLUMINATION)

layout(location = 2) rayPayloadEXT HIT_INDIRECT_PAY_LOAD indirect_prd;

void main()
{

    // Get world position from hit position
    vec3 world_pos = gl_WorldRayOriginEXT + gl_WorldRayDirectionEXT * gl_HitTEXT;

    // Get model matrix
    mat4 model = mat4(
        gl_ObjectToWorldEXT[0][0], gl_ObjectToWorldEXT[0][1], gl_ObjectToWorldEXT[0][2], 0,
        gl_ObjectToWorldEXT[0][1], gl_ObjectToWorldEXT[1][1], gl_ObjectToWorldEXT[1][2], 0,
        gl_ObjectToWorldEXT[2][0], gl_ObjectToWorldEXT[2][1], gl_ObjectToWorldEXT[2][2], 0,
        gl_ObjectToWorldEXT[3][0], gl_ObjectToWorldEXT[3][1], gl_ObjectToWorldEXT[3][2], 1.0);


    daxa_u32 actual_primitive_index = get_current_primitive_index_from_instance_and_primitive_id(gl_InstanceCustomIndexEXT, gl_PrimitiveID);

    // Get aabb from primitive
    Aabb aabb = deref(p.aabb_buffer).aabbs[actual_primitive_index];

    // Get center of aabb
    vec3 center = (aabb.minimum + aabb.maximum) * 0.5;

    // Transform center to world space
    center = (model * vec4(center, 1)).xyz;

    // Computing the normal at hit position
    vec3 world_nrm = normalize(world_pos - center);
    {
        vec3 absN = abs(world_nrm);
        daxa_f32 maxC = max(max(absN.x, absN.y), absN.z);
        world_nrm = (maxC == absN.x) ? vec3(sign(world_nrm.x), 0, 0) : (maxC == absN.y) ? vec3(0, sign(world_nrm.y), 0)
                                                                                        : vec3(0, 0, sign(world_nrm.z));
    }


    // Ray info 
    Ray ray = Ray(
        gl_WorldRayOriginEXT,
        gl_WorldRayDirectionEXT);

    
    // intersection info
    HIT_INFO_INPUT hit = HIT_INFO_INPUT(
        daxa_f32vec3(0.0),
        // NOTE: In order to avoid self intersection we need to offset the ray origin
        world_pos + world_nrm * AVOID_VOXEL_COLLAIDE,
        world_nrm,
        gl_InstanceCustomIndexEXT,
        gl_PrimitiveID,
        prd.seed,
        prd.depth);

#if defined(DEBUG_NORMALS)
    prd.hit_value *= world_nrm * 0.5 + 0.5;
#else

    daxa_u32 mat_index = get_material_index_from_primitive_index(actual_primitive_index);

    MATERIAL mat = get_material_from_material_index(mat_index);

#if INDIRECT_ILLUMINATION_ON == 1
    // SCATTER
    if(prd.depth > 0) {
        vec3  ray_origin = hit.world_hit;
        vec3  ray_dir    = hit.world_nrm;
        daxa_i32 done = 0;
#if CALLABLE_ON == 1
        call_scatter.hit = hit.world_hit;
        call_scatter.nrm = hit.world_nrm;
        call_scatter.ray_dir = ray.direction;
        call_scatter.seed = prd.seed;
        call_scatter.scatter_dir = vec3(0.0);
        call_scatter.done = done;
        call_scatter.mat_idx = mat_index;
        call_scatter.instance_id = hit.instance_id;
        call_scatter.primitive_id = hit.primitive_id;

        switch (mat.type & MATERIAL_TYPE_MASK)
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
        ray_origin = call_scatter.hit;
        ray_dir    = call_scatter.scatter_dir;
        done = call_scatter.done;
#else // CALLABLE_ON
        daxa_f32vec3 scatter_hit = hit.world_hit;
        daxa_f32vec3 scatter_nrm = hit.world_nrm;
        daxa_f32vec3 scatter_dir = hit.world_nrm;
        daxa_f32vec3 scatter_ray = ray.direction;

        switch (mat.type & MATERIAL_TYPE_MASK)
        {
        case MATERIAL_TYPE_METAL:
        {
            daxa_f32vec3 reflected = reflection(scatter_ray, scatter_nrm);
            scatter_dir = reflected + min(mat.roughness, 1.0) * random_cosine_direction(prd.seed);
            done = (dot(scatter_dir, scatter_nrm) > 0.0f) ? 0 : 1;
        }
        break;
        case MATERIAL_TYPE_DIELECTRIC:
        {
            daxa_f32 etai_over_etat = mat.ior;
            if (dot(scatter_ray, scatter_nrm) > 0.0f)
            {
                scatter_nrm = -scatter_nrm;
                etai_over_etat = 1.0f / etai_over_etat;
            }

            daxa_f32 cos_theta = min(dot(-scatter_ray, scatter_nrm), 1.0);
            daxa_f32 sin_theta = sqrt(1.0 - cos_theta * cos_theta);

            daxa_b32 cannot_refract = etai_over_etat * sin_theta > 1.0;

            if (cannot_refract || reflectance(cos_theta, etai_over_etat) > rnd(prd.seed))
                scatter_dir = reflection(scatter_ray, scatter_nrm);
            else
                scatter_dir = refraction(scatter_ray, scatter_nrm, etai_over_etat);
        }
        break;
        case MATERIAL_TYPE_CONSTANT_MEDIUM:
        {
            scatter_dir = random_unit_vector(prd.seed);
            // Catch degenerate scatter direction
            if (normal_near_zero(scatter_dir))
                scatter_dir = scatter_nrm;
        }
        break;
        default:
        {
            scatter_dir = scatter_nrm + random_cosine_direction(prd.seed);
            // Catch degenerate scatter direction
            if (normal_near_zero(scatter_dir))
                scatter_dir = scatter_nrm;
        }
        break;
        }
        ray_origin = scatter_hit;
        ray_dir    = scatter_dir;

#endif // CALLABLE_ON
        
        if(done == 1) {
            prd.depth = 0;
        } else {
            prd.depth--;
            daxa_f32 t_min   = 0.0001;
            daxa_f32 t_max   = 100000.0;
            uint cull_mask = 0xff;
            uint  flags  = gl_RayFlagsNoneEXT;

            indirect_prd.hit_value = prd.hit_value;
            indirect_prd.seed = prd.seed;
            indirect_prd.depth = prd.depth;

            traceRayEXT(
                daxa_accelerationStructureEXT(p.tlas),
                flags,         // rayFlags
                cull_mask,         // cullMask
                1,                 // sbtRecordOffset
                0,                 // sbtRecordStride
                0,                 // missIndex
                ray_origin,    // ray origin
                t_min,             // ray min range
                ray_dir, // ray direction
                t_max,             // ray max range
                2                  // payload (location = 2)
            );

            prd.hit_value *= indirect_prd.hit_value;
        }
    }
#endif // INDIRECT_ILLUMINATION_ON

    // // TEXTURES
    // {
    //     // NOTE: more texture types will be added later if they are needed
    //     if((mat.type & MATERIAL_TEXTURE_ON) != 0U) {
    //         hit_call.hit = (model * vec4(hit.world_hit, 1)).xyz;
    //         hit_call.nrm = hit.world_nrm;
    //         hit_call.texture_id = mat.texture_id;
    //         hit_call.sampler_id = mat.sampler_id;
    //         hit_call.hit_value = vec3(0.0);
    //         // executeCallableEXT(0, 3);
    //         out_color = hit_call.hit_value;
    //     } 
    //     else if((mat.type & MATERIAL_PERLIN_ON) != 0U) {
    //         hit_call.hit = (model * vec4(hit.world_hit, 1)).xyz;
    //         hit_call.nrm = hit.world_nrm;
    //         hit_call.texture_id = mat.texture_id;
    //         hit_call.sampler_id = mat.sampler_id;
    //         hit_call.hit_value = vec3(0.0);
    //         executeCallableEXT(1, 3);
    //         out_color = hit_call.hit_value;
    //     }
    // }

    // LIGHTS
    daxa_u32 light_count = deref(p.status_buffer).light_count;

    // OBJECTS
    daxa_u32 object_count = deref(p.status_buffer).obj_count;

    // Screen position
    daxa_u32 screen_pos = gl_LaunchIDEXT.x + gl_LaunchSizeEXT.x * gl_LaunchIDEXT.y;
    
    // radiance
    daxa_f32vec3 radiance = daxa_f32vec3(0.0);
    // PDF for lights
    daxa_f32 pdf = 1.0 / light_count;
    daxa_f32 pdf_out = 1.0;

#if LIGHT_SAMPLING_ON == 1

#if RESERVOIR_ON == 1

    radiance = reservoir_direct_illumination(light_count, object_count, ray, hit, screen_pos, mat_index, mat, model);

#else

    daxa_u32 light_index = min(urnd_interval(prd.seed, 0, light_count), light_count - 1);

    LIGHT light = deref(p.light_buffer).lights[light_index];

#if MIS_ON == 1
    daxa_f32vec3 m_wi = daxa_f32vec3(0.0);
    radiance = direct_mis(ray, hit, light_count, light, object_count, mat, m_wi, pdf, true, true);
#else 
    radiance = calculate_sampled_light(ray, hit, light, mat, light_count, pdf, pdf_out, true, true, true);
#endif // MIS_ON

#endif // RESERVOIR_ON

#else

    for(daxa_u32 l = 0; l < light_count; l++) {

        LIGHT light = deref(p.light_buffer).lights[l];
        
        daxa_f32vec3 m_wi = daxa_f32vec3(0.0);

#if MIS_ON == 1
        radiance += direct_mis(ray, hit, light_count, light, object_count, mat, m_wi, pdf, false, true);
#else 
        radiance += calculate_sampled_light(ray, hit, light, mat, light_count, pdf, pdf_out, false, false, true);
#endif // MIS_ON
    }
    
#endif // LIGHT_SAMPLING_ON

    prd.hit_value *= radiance;

    prd.hit_value += mat.emission;

    DIRECT_ILLUMINATION_INFO di_info = DIRECT_ILLUMINATION_INFO(daxa_f32vec4(hit.world_nrm, gl_HitTEXT), gl_InstanceCustomIndexEXT, gl_PrimitiveID);

    // Store normal
    deref(p.di_buffer).DI_info[screen_pos] = di_info;

#endif
}

#elif defined(INDIRECT_ILLUMINATION)

layout(location = 2) rayPayloadInEXT HIT_INDIRECT_PAY_LOAD indirect_prd;

void main()
{

    // Get world position from hit position
    vec3 world_pos = gl_WorldRayOriginEXT + gl_WorldRayDirectionEXT * gl_HitTEXT;

    // Get model matrix
    mat4 inv_model = mat4(
        gl_ObjectToWorldEXT[0][0], gl_ObjectToWorldEXT[0][1], gl_ObjectToWorldEXT[0][2], 0,
        gl_ObjectToWorldEXT[0][1], gl_ObjectToWorldEXT[1][1], gl_ObjectToWorldEXT[1][2], 0,
        gl_ObjectToWorldEXT[2][0], gl_ObjectToWorldEXT[2][1], gl_ObjectToWorldEXT[2][2], 0,
        gl_ObjectToWorldEXT[3][0], gl_ObjectToWorldEXT[3][1], gl_ObjectToWorldEXT[3][2], 1.0);


    daxa_u32 actual_primitive_index = get_current_primitive_index_from_instance_and_primitive_id(gl_InstanceCustomIndexEXT, gl_PrimitiveID);

    // Get aabb from primitive
    Aabb aabb = deref(p.aabb_buffer).aabbs[actual_primitive_index];

    // Get center of aabb
    vec3 center = (aabb.minimum + aabb.maximum) * 0.5;

    // Transform center to world space
    center = (inv_model * vec4(center, 1)).xyz;

    // Computing the normal at hit position
    vec3 world_nrm = normalize(world_pos - center);
    {
        vec3 absN = abs(world_nrm);
        daxa_f32 maxC = max(max(absN.x, absN.y), absN.z);
        world_nrm = (maxC == absN.x) ? vec3(sign(world_nrm.x), 0, 0) : (maxC == absN.y) ? vec3(0, sign(world_nrm.y), 0)
                                                                                        : vec3(0, 0, sign(world_nrm.z));
    }


    // Ray info 
    Ray ray = Ray(
        gl_WorldRayOriginEXT,
        gl_WorldRayDirectionEXT);

    
    // intersection info
    HIT_INFO_INPUT hit = HIT_INFO_INPUT(
        daxa_f32vec3(0.0),
        // NOTE: In order to avoid self intersection we need to offset the ray origin
        world_pos + world_nrm * AVOID_VOXEL_COLLAIDE,
        world_nrm,
        gl_InstanceCustomIndexEXT,
        gl_PrimitiveID,
        indirect_prd.seed,
        indirect_prd.depth);

    daxa_u32 mat_index = get_material_index_from_primitive_index(actual_primitive_index);

    MATERIAL mat = get_material_from_material_index(mat_index);

    // LIGHTS
    daxa_u32 light_count = deref(p.status_buffer).light_count;

    // OBJECTS
    daxa_u32 object_count = deref(p.status_buffer).obj_count;

    // Screen position
    daxa_u32 screen_pos = gl_LaunchIDEXT.x + gl_LaunchSizeEXT.x * gl_LaunchIDEXT.y;

    daxa_u32 light_index = min(urnd_interval(indirect_prd.seed, 0, light_count), light_count - 1);

    LIGHT light = deref(p.light_buffer).lights[light_index];

    daxa_f32 pdf = 1.0 / light_count;
    daxa_f32 pdf_out = 1.0;

    if(indirect_prd.depth > 0) {

        daxa_f32vec3 radiance = daxa_f32vec3(0.0);

        if(indirect_prd.depth > 1) {
            call_scatter.hit = hit.world_hit;
            call_scatter.nrm = hit.world_nrm;
            call_scatter.ray_dir = ray.direction;
            call_scatter.seed = indirect_prd.seed;
            call_scatter.scatter_dir = vec3(0.0);
            call_scatter.done = 0;
            call_scatter.mat_idx = mat_index;
            call_scatter.instance_id = hit.instance_id;
            call_scatter.primitive_id = hit.primitive_id;

            switch (mat.type & MATERIAL_TYPE_MASK)
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
            indirect_prd.seed = call_scatter.seed;
            
            if(call_scatter.done == 1) {
                indirect_prd.depth = 0;
            } else {
                indirect_prd.depth--;
                daxa_f32 t_min   = 0.0001;
                daxa_f32 t_max   = 100000.0;
                vec3  ray_origin = call_scatter.hit;
                vec3  ray_dir    = call_scatter.scatter_dir;
                uint cull_mask = 0xff;
                uint  flags  = gl_RayFlagsNoneEXT;

                traceRayEXT(
                    daxa_accelerationStructureEXT(p.tlas),
                    flags,         // rayFlags
                    cull_mask,         // cullMask
                    1,                 // sbtRecordOffset
                    0,                 // sbtRecordStride
                    0,                 // missIndex
                    ray_origin,    // ray origin
                    t_min,             // ray min range
                    ray_dir, // ray direction
                    t_max,             // ray max range
                    2                  // payload (location = 2)
                );
            }
        }

#if LIGHT_SAMPLING_ON == 1
        radiance = calculate_sampled_light(ray, hit, light, mat, light_count, pdf, pdf_out, true, true, true);
#else


        for (daxa_u32 l = 0; l < light_count; l++)
        {

            LIGHT light = deref(p.light_buffer).lights[l];

            daxa_f32 pdf = 1.0;

            daxa_f32vec3 m_wi = daxa_f32vec3(0.0);

#if MIS_ON == 1
            radiance += direct_mis(ray, hit, light_count, light, object_count, mat, m_wi, pdf, pdf_out, false, false, true);
#else
            radiance += calculate_sampled_light(ray, hit, light, mat, light_count, pdf, pdf_out, false, false, true);
#endif // MIS_ON
        }

#endif // LIGHT_SAMPLING_ON
        indirect_prd.hit_value *= radiance;
    } 

    indirect_prd.hit_value += mat.emission;
}

#else 
void main()
{
}
#endif // DIRECT_ILLUMINATION