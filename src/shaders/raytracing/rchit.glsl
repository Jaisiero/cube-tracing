#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>
#include "defines.glsl"

#include "shared.inl"
#include "mat.glsl"
#include "reservoir.glsl"
#include "light.glsl"


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


    daxa_u32 actual_primitive_index = current_primitive_index();

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
    _HIT_INFO hit = _HIT_INFO(
        // NOTE: In order to avoid self intersection we need to offset the ray origin
        world_pos - world_nrm * AVOID_VOXEL_COLLAIDE, 
        world_nrm);

#if defined(DEBUG_NORMALS)
    prd.hit_value += world_nrm * 0.5 + 0.5;
#else

    daxa_u32 mat_index = get_material_index_from_primitive_index(actual_primitive_index);

    MATERIAL mat = get_material_from_material_index(mat_index);

    // SCATTER
    if(prd.depth > 1) {
        call_scatter.hit = hit.world_hit;
        call_scatter.nrm = hit.world_nrm;
        call_scatter.ray_dir = ray.direction;
        call_scatter.seed = prd.seed;
        call_scatter.scatter_dir = vec3(0.0);
        call_scatter.done = 0;
        call_scatter.mat_idx = mat_index;

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
        
        if(call_scatter.done == 1) {
            prd.depth = 0;
        } else {
            prd.depth--;
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
                0,                 // sbtRecordOffset
                0,                 // sbtRecordStride
                0,                 // missIndex
                ray_origin,    // ray origin
                t_min,             // ray min range
                ray_dir, // ray direction
                t_max,             // ray max range
                0                  // payload (location = 0)
            );
        }
    }

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

    // COLOR
    daxa_u32 light_count = deref(p.status_buffer).light_count;

    // Screen position
    daxa_u32 screen_pos = gl_LaunchIDEXT.x + gl_LaunchSizeEXT.x * gl_LaunchIDEXT.y;

#if RESERVOIR_ON == 1

    prd.hit_value *= reservoir_direct_illumination(light_count, ray, hit, screen_pos, mat_index, mat, model);

#else
    
    // radiance
    daxa_f32vec3 radiance = daxa_f32vec3(0.0);

#if LIGHT_SAMPLING_ON == 1
    // spot light pdf
    daxa_f32 spot_light_pdf = 1.0 / daxa_f32(light_count);

    daxa_u32 light_index = min(urnd_interval(prd.seed, 0, light_count), light_count - 1);

    LIGHT light = deref(p.light_buffer).lights[light_index];

    daxa_f32 pdf = 1.0;

    radiance += calculate_sampled_light(ray, hit, light, mat, light_count, pdf, true, true);

    prd.hit_value *= radiance;

#else

    for(daxa_u32 l = 0; l < light_count; l++) {

        LIGHT light = deref(p.light_buffer).lights[l];

        daxa_f32 pdf = 1.0;

        radiance += calculate_sampled_light(ray, hit, light, mat, light_count, pdf, false, true);
    }

    prd.hit_value *= radiance;
#endif // LIGHT_SAMPLING_ON

#endif // RESERVOIR_ON

    prd.hit_value += mat.emission;

    DIRECT_ILLUMINATION_INFO di_info = DIRECT_ILLUMINATION_INFO(daxa_f32vec4(hit.world_nrm, gl_HitTEXT), gl_InstanceCustomIndexEXT, gl_PrimitiveID);

    // Store normal
    deref(p.di_buffer).DI_info[screen_pos] = di_info;

#endif
}