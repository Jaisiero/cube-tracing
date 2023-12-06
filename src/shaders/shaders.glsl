#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#extension GL_EXT_ray_query : enable
// NOTE: Debugging
// #extension GL_EXT_debug_printf : enable
#include <daxa/daxa.inl>

#include "shared.inl"
#include "mat.glsl"
#include "prng.glsl"

#include "intersect.glsl"

DAXA_DECL_PUSH_CONSTANT(PushConstant, p)

// Credits: https://github.com/nvpro-samples/vk_raytracing_tutorial_KHR/blob/master/ray_tracing_intersection/shaders/raytrace2.rchit
daxa_b32 hit_color(inout Ray ray, inout hit_info hit, inout vec3 attenuation, inout vec3 out_color, light_info light, LCG lcg)
{
    vec3 L = vec3(0.0, 0.0, 0.0);
    // Get first primitive index from instance id
    uint primitive_index = deref(p.instance_buffer).instances[hit.instance_id].first_primitive_index;

    // Get actual primitive index from offset and primitive id
    uint actual_primitive_index = primitive_index + hit.primitive_id;

    // get primitive material index
    daxa_u32 material_index = deref(p.primitives_buffer).primitives[actual_primitive_index].material_index;
    
    // get material
    MATERIAL mat = deref(p.materials_buffer).materials[material_index];

    // Point light
    if(light.type == 0)
    {
        vec3 lDir      = light.position - hit.world_pos;
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
    // vec3 diffuse     = vec3(mat.diffuse);
    vec3  specular    = vec3(0);

    daxa_b32 is_shadowed = false;

    if(dot(hit.world_nrm, L) > 0) {
        float t_min   = 0.0001;
        float t_max   = light.distance;
        float t       = 0.0;
        vec3  origin = hit.world_pos;
        vec3  ray_dir = L;
        uint cull_mask = 0xff;
        rayQueryEXT ray_query_shadow;
        rayQueryInitializeEXT(ray_query_shadow, daxa_accelerationStructureEXT(p.tlas),
                            // gl_RayFlagsOpaqueEXT   | gl_RayFlagsTerminateOnFirstHitEXT,
                            // gl_RayFlagsTerminateOnFirstHitEXT,
                            gl_RayFlagsOpaqueEXT,
                            cull_mask, 
                            origin,
                            t_min, 
                            ray_dir, 
                            t_max);
                            
        while(rayQueryProceedEXT(ray_query_shadow)) {
            uint type = rayQueryGetIntersectionTypeEXT(ray_query_shadow, false);
            if(type ==
                gl_RayQueryCandidateIntersectionAABBEXT) {
                rayQueryGenerateIntersectionEXT(ray_query_shadow, t);
                
                uint type_commited = rayQueryGetIntersectionTypeEXT(ray_query_shadow, true);

                if(type_commited ==
                    gl_RayQueryCommittedIntersectionGeneratedEXT)
                {     
                   // set is_shadowed to true
                     is_shadowed = true;
                     break;
                } 
            }
        }
        rayQueryTerminateEXT(ray_query_shadow); 

        if(is_shadowed)
        {
            attenuation *= 0.3;
            // specular = background_color(ray.direction);
        }
        else
        {
            attenuation *= 1.0;
            // Specular
            specular = compute_specular(mat, ray.direction , L, hit.world_nrm);
        }
    }

    //Apply the normal to the color
    out_color += vec3(light.intensity * attenuation * (diffuse + specular));

    vec3 scatter_direction;
    
    if(scatter(mat, ray.direction, hit.world_nrm, lcg, scatter_direction) == false) {
        // out_color = vec3(0.0, 0.0, 0.0);
        // No scatter
        return false;
    }

    ray = Ray((hit.world_pos + (DELTA_RAY * hit.world_nrm)) , scatter_direction);

    return true;
}



daxa_b32 ray_box_intersection(Ray ray, inout hit_info hit) {

    mat4 transform = deref(p.instance_buffer).instances[hit.instance_id].transform;
    mat4 transposed = transpose(transform);

    mat4 inv_transform = inverse(transform);
    mat4 inv_transposed = transpose(inv_transform);

    // Get first primitive index from instance id
    uint primitive_index = deref(p.instance_buffer).instances[hit.instance_id].first_primitive_index;

    // Get actual primitive index from offset and primitive id
    uint actual_primitive_index = primitive_index + hit.primitive_id;

    // Get center position from transform
    vec3 aabb_center = deref(p.primitives_buffer).primitives[actual_primitive_index].center;

    // TODO: Check why is divided by 2
    vec3 half_extent = vec3(HALF_EXTENT / 2 - AVOID_VOXEL_COLLAIDE);

    Ray local_ray = Ray((inv_transposed * vec4(ray.origin, 1)).xyz, (inv_transposed * vec4(ray.direction, 0)).xyz);

    Box box = Box(aabb_center, half_extent, safeInverse(half_extent), mat3(transposed));

    daxa_b32 intersection = ourIntersectBox(box, local_ray, 
        hit.distance, hit.world_nrm, 
        false, safeInverse(local_ray.direction));

    if(intersection == false) {
        return false;
    }

    // TODO: This is because we are using a box with half extent divide by 2
    // hit point in world space
    hit.world_pos = ray.origin + ray.direction * hit.distance + (HALF_EXTENT / 2) * hit.world_nrm;

    // hit point in object space
    // vec3 obj_hit = local_ray.origin + local_ray.direction * hit.distance;

    // obj_hit = (transposed * vec4(obj_hit, 1)).xyz;
    

    hit.primitive_center = aabb_center;

    // normal in world space
    // hit.world_nrm = (inv_transposed * vec4(hit.world_nrm, 0)).xyz;

    return true;
}

vec3 ray_color(Ray ray, int depth, ivec2 index, LCG lcg)
{
    vec3 out_color = vec3(0.0, 0.0, 0.0);
    if(depth <= 0) return out_color;

    // Ray query setup
    float t = 0.0f;
    float t_hit = -1.0f;
    hit_info hit;
    uint cull_mask = 0xff;
    float t_min = 0.0001f;
    float t_max = 1000.0f;
    rayQueryEXT ray_query;

    // TODO: Configurable by buffer
    const vec3 LIGHT_POSITION = vec3(1.0, 10.0, 5.0);
    // Vector toward the light
    const float light_intensity = 100.0;
    const float light_distance  = 50.0;
    const uint light_type      = 0;  // 0: point light, 1: directional light

    light_info light;
    light.position = LIGHT_POSITION;
    light.intensity = light_intensity;
    light.distance = light_distance;
    light.type = light_type;
    
    // light setup
    vec3 attenuation = vec3(1.0);

    int instance_id = -1;
    int primitive_id = -1;

    daxa_b32 found = false;

    for(int i = 0; i < depth; i++) {

        t_hit = -1.0f;

        found = false;

        rayQueryInitializeEXT(ray_query, daxa_accelerationStructureEXT(p.tlas),
                            gl_RayFlagsOpaqueEXT   | gl_RayFlagsTerminateOnFirstHitEXT,
                            // gl_RayFlagsTerminateOnFirstHitEXT,
                            // gl_RayFlagsOpaqueEXT,
                            cull_mask, ray.origin, t_min, ray.direction, t_max);
                            
        while(rayQueryProceedEXT(ray_query)) {
            uint type = rayQueryGetIntersectionTypeEXT(ray_query, false);
            if(type ==
                gl_RayQueryCandidateIntersectionAABBEXT) {
                rayQueryGenerateIntersectionEXT(ray_query, t);
                
                uint type_commited = rayQueryGetIntersectionTypeEXT(ray_query, true);

                if(type_commited ==
                    gl_RayQueryCommittedIntersectionGeneratedEXT)
                {     
                    
                    // get instance id
                    hit.instance_id = rayQueryGetIntersectionInstanceCustomIndexEXT(ray_query, true);

                    // Get primitive id
                    hit.primitive_id = rayQueryGetIntersectionPrimitiveIndexEXT(ray_query, true);

                    if(ray_box_intersection(ray, hit) == true) {
#if(DEBUG_NORMALS == 1)
                        out_color = normal_to_color(hit.world_nrm);
                        return out_color;
#endif                        

                        if(hit_color(ray, hit, attenuation, out_color, light, lcg) == true) {
                            found = true;
                        }
                        // out_color = tmp_color;
                        break;
                    }
                } 
            }
        }
        rayQueryTerminateEXT(ray_query);

        if(found == false) {
            // No hit
            // if out_color is (0,0,0) then we are in the background primary ray otherwise we are in a shadow ray
            attenuation = out_color == vec3(0.0, 0.0, 0.0) ? vec3(1.0) : vec3(0.01);
            out_color += background_color(ray.direction) * attenuation;
            return out_color;
        }
    };

    return out_color;
}

layout(local_size_x = 8, local_size_y = 8) in;
void main()
{
    const ivec2 index = ivec2(gl_GlobalInvocationID.xy);
    if (index.x >= p.size.x || index.y >= p.size.y)
    {
        return;
    }
    uvec2 launch_size = gl_NumWorkGroups.xy * 8;

    // Color output
    vec3 out_color = vec3(0.0, 0.0, 0.0);

    // Ray setup
    Ray ray;

    // Camera setup
    daxa_f32mat4x4 inv_view = deref(p.camera_buffer).inv_view;
    daxa_f32mat4x4 inv_proj = deref(p.camera_buffer).inv_proj;
    // daxa_f32 LOD_distance = deref(p.camera_buffer).LOD_distance;

    const vec2 pixel_center = vec2(index) + vec2(0.5);
    const vec2 inv_UV = pixel_center / vec2(launch_size);
    vec2 d = inv_UV * 2.0 - 1.0;
    
    // DEBUGGING
    // deref(p.hit_distance_buffer).hit_distances[index.x + index.y * p.size.x].distance = -1.0f;

    LCG lcg;
    daxa_u32 frame_number = deref(p.status_buffer).frame_number;
    daxa_u32 seedX = index.x;
    daxa_u32 seedY = index.y;

    initLCG(lcg, frame_number, seedX, seedY);

    daxa_f32vec4 origin = inv_view * vec4(0,0,0,1);

#if SAMPLES_PER_PIXEL == 1

	vec4 target = inv_proj * vec4(d.x, d.y, 1, 1) ;
	vec4 direction = inv_view * vec4(normalize(target.xyz), 0) ;
    
    ray.origin = origin.xyz;
    ray.direction = direction.xyz;

    // 1 sample per pixel
    out_color = ray_color(ray, MAX_DEPTH, index, lcg);
#else

    // Multiple samples per pixel (anti-aliasing) 
    // Primary ray
    for(int i = 0; i < SAMPLES_PER_PIXEL; i++)
    {
        // Some random sampling for anti-aliasing
        vec2 df = d + vec2(randomInRangeLCG(lcg, 0.0f, SAMPLE_OFFSET), randomInRangeLCG(lcg, 0.0f, SAMPLE_OFFSET));
        vec4 target = inv_proj * vec4(df.x, df.y, 1, 1) ;
        vec4 direction = inv_view * vec4(normalize(target.xyz), 0) ;
        
        ray.origin = origin.xyz;
        ray.direction = direction.xyz;

        vec3 partial_out_color = ray_color(ray, MAX_DEPTH, index, lcg);

        out_color += partial_out_color / SAMPLES_PER_PIXEL;
    }
    clamp(out_color, 0.0, 0.99999999);

#endif

    // NOTE: We are not using gamma correction because we suspect that swapchain is already in sRGB    
    // imageStore(daxa_image2D(p.swapchain), index, fromLinear(vec4(out_color,1)));
    // imageStore(daxa_image2D(p.swapchain), index, linear_to_ gamma(vec4(out_color,1)));
    imageStore(daxa_image2D(p.swapchain), index, vec4(out_color,1));


    // DEBUGGING
    daxa_b32 is_active = deref(p.status_buffer).is_active;
    if(is_active == true) {
        daxa_u32vec2 pixel = deref(p.status_buffer).pixel; 
        if(index.x == pixel.x && index.y == pixel.y) {
            
            deref(p.status_output_buffer).instance_id = MAX_INSTANCES;
            deref(p.status_output_buffer).primitive_id = MAX_PRIMITIVES;

            // Ray query setup
            uint cull_mask = 0xff;
            float t_min = 0.0001f;
            float t_max = 1000.0f;
            vec3 origin = ray.origin;
            vec3 ray_dir = ray.direction;
            hit_info hit;
            rayQueryEXT ray_query; 

            rayQueryInitializeEXT(ray_query, daxa_accelerationStructureEXT(p.tlas),
                            gl_RayFlagsOpaqueEXT   | gl_RayFlagsTerminateOnFirstHitEXT,
                            cull_mask, origin, t_min, ray_dir, t_max);
                            
            while(rayQueryProceedEXT(ray_query)) {
                uint type = rayQueryGetIntersectionTypeEXT(ray_query, false);
                if(type ==
                    gl_RayQueryCandidateIntersectionAABBEXT) {
                    rayQueryGenerateIntersectionEXT(ray_query, hit.distance);
                    
                    uint type_commited = rayQueryGetIntersectionTypeEXT(ray_query, true);

                    if(type_commited ==
                        gl_RayQueryCommittedIntersectionGeneratedEXT)
                    {     
                        
                        // get instance id
                        hit.instance_id = rayQueryGetIntersectionInstanceCustomIndexEXT(ray_query, true);

                        // Get primitive id
                        hit.primitive_id = rayQueryGetIntersectionPrimitiveIndexEXT(ray_query, true);

                        if(ray_box_intersection(ray, hit) == true) {
                            // if hit write instance & primtive id to status_output_buffer
                            deref(p.status_output_buffer).instance_id = hit.instance_id;
                            deref(p.status_output_buffer).primitive_id = hit.primitive_id;
                            deref(p.status_output_buffer).hit_distance = hit.distance;
                            deref(p.status_output_buffer).hit_position = hit.world_pos;
                            deref(p.status_output_buffer).hit_normal = hit.world_nrm;
                            deref(p.status_output_buffer).origin = ray.origin;
                            deref(p.status_output_buffer).direction = ray.direction;
                            deref(p.status_output_buffer).primitive_center = hit.primitive_center;

                            break;
                        }
                    } 
                }
            }
        }
    }
}