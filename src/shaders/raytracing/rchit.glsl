#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>
#include "defines.glsl"
#include "shared.inl"
#include "mat.glsl"
#include "reservoir.glsl"
#include "light.glsl"

#if SER == 1
#extension GL_NV_shader_invocation_reorder : enable
layout(location = 0) hitObjectAttributeNV vec3 hitValue;
#endif


#if defined(RIS_SELECTION)

void main()
{

    // Ray info 
    Ray ray = Ray(
        gl_WorldRayOriginEXT,
        gl_WorldRayDirectionEXT);

    // Get model matrix
    daxa_f32mat4x4 model = mat4(
        gl_ObjectToWorldEXT[0][0], gl_ObjectToWorldEXT[0][1], gl_ObjectToWorldEXT[0][2], 0,
        gl_ObjectToWorldEXT[0][1], gl_ObjectToWorldEXT[1][1], gl_ObjectToWorldEXT[1][2], 0,
        gl_ObjectToWorldEXT[2][0], gl_ObjectToWorldEXT[2][1], gl_ObjectToWorldEXT[2][2], 0,
        gl_ObjectToWorldEXT[3][0], gl_ObjectToWorldEXT[3][1], gl_ObjectToWorldEXT[3][2], 1.0);

    daxa_f32vec3 world_pos;
    daxa_f32vec3 world_nrm;
    daxa_f32 distance = gl_HitTEXT;
    daxa_u32 actual_primitive_index = 0;
    OBJECT_INFO instance_hit = OBJECT_INFO(gl_InstanceCustomIndexEXT, gl_PrimitiveID);
    
    packed_intersection_info(ray, distance, instance_hit, model, world_pos, world_nrm, actual_primitive_index);

        // NOTE: In order to avoid self intersection we need to offset the ray origin
    // world_pos = compute_ray_origin(world_pos, world_nrm);
    distance = length(world_pos - ray.origin);

    daxa_u32 mat_index = get_material_index_from_primitive_index(actual_primitive_index);
    
    prd.world_hit = world_pos;
    prd.world_nrm = world_nrm;
    prd.distance = distance;
    prd.instance_hit = instance_hit;
    prd.mat_index = mat_index;
}

#elif defined(INDIRECT_ILLUMINATION)

void main()
{

   // Ray info 
    Ray ray = Ray(
        gl_WorldRayOriginEXT,
        gl_WorldRayDirectionEXT);

    // Get model matrix
    daxa_f32mat4x4 model = mat4(
        gl_ObjectToWorldEXT[0][0], gl_ObjectToWorldEXT[0][1], gl_ObjectToWorldEXT[0][2], 0,
        gl_ObjectToWorldEXT[0][1], gl_ObjectToWorldEXT[1][1], gl_ObjectToWorldEXT[1][2], 0,
        gl_ObjectToWorldEXT[2][0], gl_ObjectToWorldEXT[2][1], gl_ObjectToWorldEXT[2][2], 0,
        gl_ObjectToWorldEXT[3][0], gl_ObjectToWorldEXT[3][1], gl_ObjectToWorldEXT[3][2], 1.0);

    daxa_f32vec3 world_pos;
    daxa_f32vec3 world_nrm;
    daxa_f32 distance = gl_HitTEXT;
    OBJECT_INFO instance_hit = OBJECT_INFO(gl_InstanceCustomIndexEXT, gl_PrimitiveID);
    daxa_u32 actual_primitive_index = 0;
    
    packed_intersection_info(ray, distance, instance_hit, model, world_pos, world_nrm, actual_primitive_index);

    // world_pos = compute_ray_origin(world_pos, world_nrm);
    distance = length(world_pos - ray.origin);

    daxa_u32 mat_index = get_material_index_from_primitive_index(actual_primitive_index);

    MATERIAL mat = get_material_from_material_index(mat_index);

    call_scatter.hit = world_pos;
    call_scatter.nrm = world_nrm;
    call_scatter.ray_dir = ray.direction;
    call_scatter.seed = prd.seed;
    call_scatter.scatter_dir = vec3(0.0);
    call_scatter.done = false;
    call_scatter.mat_idx = mat_index;
    call_scatter.instance_hit = instance_hit;

    daxa_u32 mat_type = mat.type & MATERIAL_TYPE_MASK;
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
    prd.done = call_scatter.done;
    prd.world_hit = call_scatter.hit;
    prd.world_nrm = call_scatter.nrm;
    prd.ray_scatter_dir = call_scatter.scatter_dir;

    // Get light configuration
    LIGHT_CONFIG light_config = get_light_config_from_light_index();

    // LIGHTS
    daxa_u32 light_count = light_config.point_light_count;

    // // OBJECTS
    // daxa_u32 object_count = deref(p.status_buffer).obj_count;

    daxa_u32 light_index = min(urnd_interval(prd.seed, 0, light_count), light_count - 1);

    LIGHT light = get_point_light_from_light_index(light_index);

    daxa_f32 pdf = 1.0 / light_count;
    daxa_f32 pdf_out = 1.0;

    daxa_f32vec3 radiance = daxa_f32vec3(0.0);
    
    // intersection info
    HIT_INFO_INPUT hit = HIT_INFO_INPUT(
        world_pos,
        world_nrm,
        distance,
        prd.ray_scatter_dir,
        instance_hit,
        mat_index);

    hit.world_hit = compute_ray_origin(hit.world_hit, hit.world_nrm);
    hit.world_hit = compute_ray_origin(hit.world_hit, hit.world_nrm);

    daxa_f32 G;

    radiance = calculate_sampled_light(ray, hit, mat, light_count, light, pdf, pdf_out, G, prd.seed, true, true, true);

    prd.distance = distance;
    prd.instance_hit = instance_hit;
    prd.mat_index = mat_index;

    prd.hit_value *= radiance;
    prd.hit_value += mat.emission;
}

#else 
void main()
{
}
#endif // DIRECT_ILLUMINATION