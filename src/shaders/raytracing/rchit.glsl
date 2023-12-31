#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>

#include "shared.inl"
#include "mat.glsl"

DAXA_DECL_PUSH_CONSTANT(PushConstant, p)

layout(location = 0) rayPayloadInEXT HIT_PAY_LOAD prd;
layout(location = 1) rayPayloadEXT bool isShadowed;

// #define DEBUG_NORMALS 1

daxa_f32vec3 _mat_get_color_by_light(Ray ray, MATERIAL mat, LIGHT light, _HIT_INFO hit, LCG lcg) 
{

    vec3 L = vec3(0.0, 0.0, 0.0);
    // Point light
    if(light.type == 0)
    {
        vec3 lDir      = light.position - hit.world_hit;
        light.distance  = length(lDir);
        light.intensity = light.intensity / (light.distance * light.distance);
        L              = normalize(lDir);
    }
    else  // Directional light
    {
        L = normalize(light.position);
    }

    // Diffuse
    vec3  diffuse     = compute_diffuse(mat, L, hit.world_nrm);
    vec3  specular    = vec3(0);
    float  attenuation = 1.0;

    if(dot(hit.world_nrm, L) > 0) {
        float t_min   = 0.0001;
        float t_max   = light.distance;
        vec3  origin = hit.world_hit;
        vec3  ray_dir = L;
        Ray shadow_ray = Ray(origin, ray_dir);
        uint cull_mask = 0xff;
        uint  flags  = gl_RayFlagsTerminateOnFirstHitEXT | gl_RayFlagsOpaqueEXT | gl_RayFlagsSkipClosestHitShaderEXT;
        isShadowed = true;

        traceRayEXT(
            daxa_accelerationStructureEXT(p.tlas),
            flags,  // rayFlags
            cull_mask,   // cullMask
            0,      // sbtRecordOffset
            0,      // sbtRecordStride
            1,      // missIndex
            shadow_ray.origin, // ray origin
            t_min,   // ray min range
            shadow_ray.direction, // ray direction
            t_max,   // ray max range
            1       // payload (location = 1)
        );

        if(isShadowed)
        {
            attenuation = 0.3;
        }
        else
        {
            // Specular
            specular = compute_specular(mat, ray.direction , L, hit.world_nrm);
        }
    }

    return vec3(light.intensity * attenuation * (diffuse + specular));
}

void main()
{
    vec3 world_pos = gl_WorldRayOriginEXT + gl_WorldRayDirectionEXT * gl_HitTEXT;

    mat4 model = mat4(
        gl_ObjectToWorldEXT[0][0], gl_ObjectToWorldEXT[0][1], gl_ObjectToWorldEXT[0][2], 0,
        gl_ObjectToWorldEXT[0][1], gl_ObjectToWorldEXT[1][1], gl_ObjectToWorldEXT[1][2], 0,
        gl_ObjectToWorldEXT[2][0], gl_ObjectToWorldEXT[2][1], gl_ObjectToWorldEXT[2][2], 0,
        gl_ObjectToWorldEXT[3][0], gl_ObjectToWorldEXT[3][1], gl_ObjectToWorldEXT[3][2], 1.0);

    

    // Get first primitive index from instance id
    uint primitive_index = deref(p.instance_buffer).instances[gl_InstanceCustomIndexEXT].first_primitive_index;
    // Get actual primitive index from offset and primitive id
    uint actual_primitive_index = primitive_index + gl_PrimitiveID;

    Aabb aabb = deref(p.aabb_buffer).aabbs[actual_primitive_index];

    vec3 center = (aabb.minimum + aabb.maximum) * 0.5;

    center = (model * vec4(center, 1)).xyz;

    // Computing the normal at hit position
    vec3 world_nrm = normalize(world_pos - center);

    {
        vec3 absN = abs(world_nrm);
        float maxC = max(max(absN.x, absN.y), absN.z);
        world_nrm = (maxC == absN.x) ? vec3(sign(world_nrm.x), 0, 0) : (maxC == absN.y) ? vec3(0, sign(world_nrm.y), 0)
                                                                                        : vec3(0, 0, sign(world_nrm.z));
    }

#if defined(DEBUG_NORMALS)
    prd.hit_value *= world_nrm * 0.5 + 0.5;
#else

    Ray ray = Ray(
        gl_WorldRayOriginEXT,
        gl_WorldRayDirectionEXT);

    PRIMITIVE primitive = deref(p.primitives_buffer).primitives[actual_primitive_index];

    MATERIAL mat = deref(p.materials_buffer).materials[primitive.material_index];

    daxa_u32 light_count = deref(p.status_buffer).light_count;

    vec3 out_color = vec3(0.0);

    _HIT_INFO hit = _HIT_INFO(
        world_pos,
        world_nrm);

    LCG lcg;
    InitLCGSetConstants(lcg);
    lcg.state = prd.seed;

    // TODO: ReSTIR or something easier first
    for(daxa_u32 l = 0; l < light_count; l++) {
        LIGHT light = deref(p.light_buffer).lights[l];

        if(light.intensity > 0.0) {
            out_color = _mat_get_color_by_light(ray, mat, light, hit, lcg);
        }
    }


    prd.hit_value *= out_color;
#endif
}