#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#extension GL_EXT_ray_query : enable
// NOTE: Debugging
// #extension GL_EXT_debug_printf : enable
#include <daxa/daxa.inl>

#include "shared.inl"
#include "prng.glsl"
#include "mat.glsl"

#include "intersect.glsl"

DAXA_DECL_PUSH_CONSTANT(PushConstant, p)

daxa_b32 ray_box_intersection(Ray ray, inout hit_info hit, out MATERIAL mat, LCG lcg) {

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

    // Voxels are centered around half extent
    vec3 half_extent = vec3(VOXEL_EXTENT / 2);

    Ray local_ray = Ray((inv_transposed * vec4(ray.origin, 1)).xyz, (inv_transposed * vec4(ray.direction, 0)).xyz);

    Box box = Box(aabb_center, half_extent, safeInverse(half_extent), mat3(transposed));

    float t_max = 0.0f;

    daxa_b32 intersection = ourIntersectBoxTwoHits(box, local_ray, 
        hit.hit_distance, hit.exit_distance, hit.world_nrm, 
        false, safeInverse(local_ray.direction));

    if(intersection == false) {
        return false;
    }

   
    // hit point in world space
    hit.world_pos = hit_get_world_hit(ray, hit);

    hit.primitive_center = aabb_center;

    // Get material
    {
        // Get first primitive index from instance id
        uint primitive_index = deref(p.instance_buffer).instances[hit.instance_id].first_primitive_index;

        // Get actual primitive index from offset and primitive id
        uint actual_primitive_index = primitive_index + hit.primitive_id;

        // get primitive material index
        daxa_u32 material_index = deref(p.primitives_buffer).primitives[actual_primitive_index].material_index;
        
        // get material
        mat = deref(p.materials_buffer).materials[material_index];
    }

    daxa_b32 intersected = true;
    // // Check dissolve and transmission
    // {
    //     intersected = material_transmission(ray, hit, mat, lcg);
    // }

    return intersected;
}

daxa_f32vec3 mat_get_color_by_light(Ray ray, MATERIAL mat, LIGHT light, inout hit_info hit, LCG lcg) 
{

    vec3 L = vec3(0.0, 0.0, 0.0);
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
    vec3  attenuation = vec3(1.0);

    daxa_b32 is_shadowed = false;

    if(dot(hit.world_nrm, L) > 0) {
        float t_min   = 0.0001;
        float t_max   = light.distance;
        float t       = 0.0;
        vec3  origin = hit.world_pos;
        vec3  ray_dir = L;
        Ray shadow_ray = Ray(origin, ray_dir);
        uint cull_mask = 0xff;
        rayQueryEXT ray_query_shadow;
        hit_info hit_shadow;
        MATERIAL mat_shadow;
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
#if(DIALECTRICS_DONT_BLOCK_LIGHT == 1)                    
                    // get instance id
                    hit_shadow.instance_id = rayQueryGetIntersectionInstanceCustomIndexEXT(ray_query_shadow, true);

                    // Get primitive id
                    hit_shadow.primitive_id = rayQueryGetIntersectionPrimitiveIndexEXT(ray_query_shadow, true);
                    
                    // TODO: light leaks between cubes
                    // if(ray_box_intersection(shadow_ray, hit_shadow, mat_shadow, lcg) == true) {
                    ray_box_intersection(shadow_ray, hit_shadow, mat_shadow, lcg);
                        
                        if(mat_shadow.type != TEXTURE_TYPE_DIELECTRIC) {
#endif // DIALECTRICS_DONT_BLOCK_LIGH                            
                        // set is_shadowed to true
                            is_shadowed = true;
                            break;
#if(DIALECTRICS_DONT_BLOCK_LIGHT == 1)
                        }
                    // }
#endif // DIALECTRICS_DONT_BLOCK_LIGHT

                } 
            }
        }
        rayQueryTerminateEXT(ray_query_shadow); 

        if(is_shadowed)
        {
            attenuation *= 0.3;
        }
        else
        {
            attenuation *= 1.0;
            // Specular
            specular = compute_specular(mat, ray.direction , L, hit.world_nrm);
        }
    }

    return vec3(light.intensity * attenuation * (diffuse + specular));
}

// Credits: https://github.com/nvpro-samples/vk_raytracing_tutorial_KHR/blob/master/ray_tracing_intersection/shaders/raytrace2.rchit
daxa_b32 hit_material(inout Ray ray, MATERIAL mat, inout hit_info hit, inout daxa_f32vec3 out_color, LCG lcg)
{
    // TODO: Just one light for now
    LIGHT light = deref(p.light_buffer).lights[0];

    if(light.intensity > 0.0) {
        // TODO: Fix this
        vec3 current_diffuse_color = mat.diffuse;
        mat.diffuse = hit.hit_color;
        out_color += mat_get_color_by_light(ray, mat, light, hit, lcg);
        mat.diffuse = current_diffuse_color;
    }
    out_color += mat.emission * hit.hit_color;
    hit.hit_color *= mat.diffuse;
    // out_color += mat_get_color(ray, mat, hit, attenuation);

    vec3 scatter_direction;
    
    if(scatter(mat, ray.direction, hit.world_nrm, lcg, scatter_direction) == false) {
        // out_color = vec3(0.0, 0.0, 0.0);
        // No scatter
        return false;
    }

    ray = Ray((hit.world_pos + (DELTA_RAY * hit.world_nrm)) , scatter_direction);

    return true;
}

vec3 ray_color(Ray ray, int depth, ivec2 index, LCG lcg)
{
    vec3 out_color = vec3(0.0, 0.0, 0.0);
    if(depth <= 0) return out_color;

    // Ray query setup
    float t = 0.0f;
    float t_hit = -1.0f;
    hit_info hit = hit_info(false, vec3(1.0, 1.0, 1.0), t_hit, t_hit, vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), -1, -1, vec3(0.0, 0.0, 0.0));
    uint cull_mask = 0xff;
    float t_min = 0.0001f;
    float t_max = 1000.0f;
    rayQueryEXT ray_query;
    
    // light setup

    int instance_id = -1;
    int primitive_id = -1;
    MATERIAL mat;

    daxa_b32 keep_bouncing = false;

    for(int i = 0; i < depth; i++) {

        t_hit = -1.0f;

        keep_bouncing = false;

        rayQueryInitializeEXT(ray_query, daxa_accelerationStructureEXT(p.tlas),
                            gl_RayFlagsOpaqueEXT,
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

                    if(ray_box_intersection(ray, hit, mat, lcg) == true) {
                        hit.is_hit = true;
#if(DEBUG_NORMALS_ON == 1)
                        out_color = normal_to_color(hit.world_nrm);
                        return out_color;
#endif                        

                        if(hit_material(ray, mat, hit, out_color, lcg) == true) {
                            keep_bouncing = true;
                        }
                        // out_color = tmp_color;
                        break;
                    }
                } 
            }
        }
        rayQueryTerminateEXT(ray_query);

        if(hit.is_hit == false) {
            // lost in sky direction random direction
            // daxa_f32vec3 lost_light_direction = random_on_hemisphere(lcg, ray.direction);
            out_color = calculate_sky_color(
                    deref(p.status_buffer).time, 
                    deref(p.status_buffer).is_afternoon,
                    ray.direction);
            return out_color;
        } else if(keep_bouncing == false) {
            // lost in sky direction random direction
            // daxa_f32vec3 lost_light_direction = random_on_hemisphere(lcg, ray.direction);
            out_color *= calculate_sky_color(
                deref(p.status_buffer).time,
                deref(p.status_buffer).is_afternoon,
                ray.direction);
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

    daxa_f32 defocus_angle = deref(p.camera_buffer).defocus_angle;
    daxa_f32 focus_dist = deref(p.camera_buffer).focus_dist;

    daxa_f32 defocus_radius = focus_dist * tan(radians(defocus_angle / 2));
    daxa_f32vec2 defocus_disk = vec2(d.x * defocus_radius, 
        d.y * defocus_radius);

    daxa_f32vec4 origin = inv_view * vec4(0,0,0,1);
    ray.origin = (defocus_angle <= 0) ? origin.xyz : defocus_disk_sample(origin.xyz, defocus_disk, lcg);
    // ray.origin = origin.xyz;

#if SAMPLES_PER_PIXEL == 1

	vec4 target = inv_proj * vec4(d.x, d.y, 1, 1) ;
	vec4 direction = inv_view * vec4(normalize(target.xyz), 0) ;

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


#if(PERFECT_PIXEL_ON == 1)
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
            MATERIAL mat;

            rayQueryInitializeEXT(ray_query, daxa_accelerationStructureEXT(p.tlas),
                            gl_RayFlagsOpaqueEXT,
                            cull_mask, origin, t_min, ray_dir, t_max);
                            
            while(rayQueryProceedEXT(ray_query)) {
                uint type = rayQueryGetIntersectionTypeEXT(ray_query, false);
                if(type ==
                    gl_RayQueryCandidateIntersectionAABBEXT) {
                    rayQueryGenerateIntersectionEXT(ray_query, hit.hit_distance);
                    
                    uint type_commited = rayQueryGetIntersectionTypeEXT(ray_query, true);

                    if(type_commited ==
                        gl_RayQueryCommittedIntersectionGeneratedEXT)
                    {     
                        
                        // get instance id
                        hit.instance_id = rayQueryGetIntersectionInstanceCustomIndexEXT(ray_query, true);

                        // Get primitive id
                        hit.primitive_id = rayQueryGetIntersectionPrimitiveIndexEXT(ray_query, true);
                        
                        // TEST
                        // deref(p.status_output_buffer).instance_id = hit.instance_id;
                        // deref(p.status_output_buffer).primitive_id = hit.primitive_id;

                        if(ray_box_intersection(ray, hit, mat, lcg) == true) {
                            // if hit write instance & primtive id to status_output_buffer
                            deref(p.status_output_buffer).instance_id = hit.instance_id;
                            deref(p.status_output_buffer).primitive_id = hit.primitive_id;
                            deref(p.status_output_buffer).hit_distance = hit.hit_distance;
                            deref(p.status_output_buffer).exit_distance = hit.exit_distance;
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
#endif // PERFECT_PIXEL
}