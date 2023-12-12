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

daxa_u32 hit_get_material_index(HIT_INFO hit) {
    
    // Get first primitive index from instance id
    uint primitive_index = deref(p.instance_buffer).instances[hit.instance_id].first_primitive_index;

    // Get actual primitive index from offset and primitive id
    uint actual_primitive_index = primitive_index + hit.primitive_id;

    // get primitive material index
    return deref(p.primitives_buffer).primitives[actual_primitive_index].material_index;
}

daxa_b32 ray_box_intersection(Ray ray, inout HIT_INFO hit, out daxa_u32 material_index, LCG lcg) {

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
    // TODO: Light leaks between voxels due to number precision?
    vec3 half_extent = vec3(VOXEL_EXTENT / 2);

    Ray local_ray = Ray((inv_transposed * vec4(ray.origin, 1)).xyz, (inv_transposed * vec4(ray.direction, 0)).xyz);

    Box box = Box(aabb_center, half_extent, safeInverse(half_extent), mat3(transposed));

    float t_max = 0.0f;

    daxa_b32 intersection = ourIntersectBoxTwoHitsAndUV(box, local_ray, 
        hit.hit_distance, hit.exit_distance, hit.world_nrm, 
        false, safeInverse(local_ray.direction), hit.uv);

    if(intersection == false) {
        return false;
    }

   
    // hit point in world space
    hit.world_pos = hit_get_world_hit(ray, hit);

    hit.primitive_center = aabb_center;

    material_index = hit_get_material_index(hit);

    // get material
    MATERIAL mat = deref(p.materials_buffer).materials[material_index];

    daxa_b32 intersected = true;
    // Check dissolve and transmission
    {
        if(mat.type == MATERIAL_TYPE_CONSTANT_MEDIUM) {
            intersected = material_transmission(ray, hit, mat.dissolve, lcg);
        }
    }

    return intersected;
}

daxa_f32vec3 mat_get_color_by_light(Ray ray, MATERIAL mat, LIGHT light, inout HIT_INFO hit, LCG lcg) 
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
        HIT_INFO hit_shadow;
        daxa_u32 shadow_mat_index;
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

                // get instance id
                hit_shadow.instance_id = rayQueryGetIntersectionInstanceCustomIndexEXT(ray_query_shadow, false);

                // Get primitive id
                hit_shadow.primitive_id = rayQueryGetIntersectionPrimitiveIndexEXT(ray_query_shadow, false);

#if(DIALECTRICS_DONT_BLOCK_LIGHT == 1)                    
                // TODO: light leaks between cubes
                if(ray_box_intersection(shadow_ray, hit_shadow, shadow_mat_index, lcg) == true) 
                {
                // ray_box_intersection(shadow_ray, hit_shadow, mat_shadow, lcg);
                
                    rayQueryGenerateIntersectionEXT(ray_query_shadow, t);
                    
                    uint type_commited = rayQueryGetIntersectionTypeEXT(ray_query_shadow, true);
                    if(type_commited ==
                        gl_RayQueryCommittedIntersectionGeneratedEXT)
                    {   
                        MATERIAL shadow_mat = deref(p.materials_buffer).materials[shadow_mat_index];
                        if(shadow_mat.type != MATERIAL_TYPE_DIELECTRIC) {
#endif // DIALECTRICS_DONT_BLOCK_LIGH                            
                        // set is_shadowed to true
                                is_shadowed = true;
                                break;
#if(DIALECTRICS_DONT_BLOCK_LIGHT == 1)
                        }
                    }
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
daxa_b32 hit_material(inout Ray ray, daxa_u32 hit_material_index, inout HIT_INFO hit, inout daxa_f32vec3 out_color, daxa_u32 light_count, LCG lcg)
{

    // get material index
    daxa_u32 material_index = hit_get_material_index(hit);
    MATERIAL mat = deref(p.materials_buffer).materials[material_index];
    
    for(daxa_u32 l = 0; l < light_count; l++) {
        LIGHT light = deref(p.light_buffer).lights[l];

        if(light.intensity > 0.0) {
            // TODO: Fix this
            vec3 current_diffuse_color = mat.diffuse;
            out_color += mat_get_color_by_light(ray, mat, light, hit, lcg);
        }
    }

    if((mat.type & MATERIAL_TEXTURE_ON) != 0U) {
        vec2 uv = hit.uv;
        vec4 texel = texture(daxa_sampler2D(mat.texture_id, mat.sampler_id), uv);
        out_color *= texel.xyz;
    }

    out_color += mat.emission * mat.diffuse;
    hit.material_index = hit_material_index;

    vec3 scatter_direction;
    
    if(scatter(mat, ray.direction, hit.world_nrm, lcg, scatter_direction) == false) {
        // out_color = vec3(0.0, 0.0, 0.0);
        // No scatter
        return false;
    }

    ray = Ray((hit.world_pos + (DELTA_RAY * hit.world_nrm)) , scatter_direction);

    return true;
}

vec3 ray_color(Ray ray, int depth, ivec2 index, daxa_u32 light_count, LCG lcg)
{
    vec3 out_color = vec3(0.0, 0.0, 0.0);
    if(depth <= 0) return out_color;

    // Ray query setup
    float t = 0.0f;
    HIT_INFO hit = HIT_INFO(false, -1.0f, -1.0f, vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0), -1, -1, vec3(0.0, 0.0, 0.0), 0, vec2(0.0, 0.0));
    uint cull_mask = 0xff;
    float t_min = 0.0001f;
    float t_max = 1000.0f;
    rayQueryEXT ray_query;
    
    // light setup

    int instance_id = -1;
    int primitive_id = -1;
    daxa_u32 material_index = 0;

    daxa_b32 keep_bouncing = false;

    for(int i = 0; i < depth; i++) {

        rayQueryInitializeEXT(ray_query, daxa_accelerationStructureEXT(p.tlas),
                            gl_RayFlagsOpaqueEXT,
                            cull_mask, ray.origin, t_min, ray.direction, t_max);
                            
        while(rayQueryProceedEXT(ray_query)) {
            uint type = rayQueryGetIntersectionTypeEXT(ray_query, false);
            if(type ==
                gl_RayQueryCandidateIntersectionAABBEXT) {
                // get instance id
                hit.instance_id = rayQueryGetIntersectionInstanceCustomIndexEXT(ray_query, false);

                // Get primitive id
                hit.primitive_id = rayQueryGetIntersectionPrimitiveIndexEXT(ray_query, false);

                if(ray_box_intersection(ray, hit, material_index, lcg) == true) {
                    hit.is_hit = true;
            
                    rayQueryGenerateIntersectionEXT(ray_query, hit.hit_distance);
            
                    uint type_commited = rayQueryGetIntersectionTypeEXT(ray_query, true);

                    if(type_commited ==
                        gl_RayQueryCommittedIntersectionGeneratedEXT)
                    {     

#if(DEBUG_NORMALS_ON == 1)
                        out_color = normal_to_color(hit.world_nrm);
                        return out_color;
#endif                        

                        if(hit_material(ray, material_index, hit, out_color, light_count, lcg) == true) {
                            keep_bouncing = true;
                        }
                        break;
                    }
                }
            }
        }
        rayQueryTerminateEXT(ray_query);

        if(hit.is_hit == false) {
            // lost in sky direction random direction
            out_color = calculate_sky_color(
                    deref(p.status_buffer).time, 
                    deref(p.status_buffer).is_afternoon,
                    ray.direction);
            return out_color;
        } else if(keep_bouncing == false) {
            // lost in sky direction random direction
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
    daxa_u32 light_count = deref(p.status_buffer).light_count;
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
    out_color = ray_color(ray, MAX_DEPTH, index, light_count, lcg);
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

        vec3 partial_out_color = ray_color(ray, MAX_DEPTH, index, light_count, lcg);

        out_color += partial_out_color / SAMPLES_PER_PIXEL;
    }
    clamp(out_color, 0.0, 0.99999999);

#endif

#if ACCUMULATOR_ON == 1
    daxa_u32 num_accumulated_frames = deref(p.status_buffer).num_accumulated_frames;
    vec4 final_pixel;
    if(num_accumulated_frames > 0) {
        vec4 previous_frame_pixel = imageLoad(daxa_image2D(p.swapchain), index);
        
        vec4 current_frame_pixel = vec4(out_color, 1.0f);

        daxa_f32 weight = 1.0f / (num_accumulated_frames + 1.0f);
        final_pixel = mix(previous_frame_pixel, current_frame_pixel, weight);
    } else {
        final_pixel = vec4(out_color, 1.0f);
    }
#else 
    vec4 final_pixel = vec4(out_color, 1.0f);
#endif

    // 

    // NOTE: We are not using gamma correction because we suspect that swapchain is already in sRGB    
    // imageStore(daxa_image2D(p.swapchain), index, fromLinear(vec4(out_color,1)));
    // imageStore(daxa_image2D(p.swapchain), index, linear_to_ gamma(vec4(out_color,1)));
    imageStore(daxa_image2D(p.swapchain), index, final_pixel);


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
            HIT_INFO hit;
            rayQueryEXT ray_query; 
            daxa_u32 material_index = 0;

            rayQueryInitializeEXT(ray_query, daxa_accelerationStructureEXT(p.tlas),
                            gl_RayFlagsOpaqueEXT,
                            cull_mask, origin, t_min, ray_dir, t_max);
                            
            while(rayQueryProceedEXT(ray_query)) {
                uint type = rayQueryGetIntersectionTypeEXT(ray_query, false);
                if(type ==
                    gl_RayQueryCandidateIntersectionAABBEXT) {    
                        
                    // get instance id
                    hit.instance_id = rayQueryGetIntersectionInstanceCustomIndexEXT(ray_query, false);

                    // Get primitive id
                    hit.primitive_id = rayQueryGetIntersectionPrimitiveIndexEXT(ray_query, false);
                        
                    // TEST
                    deref(p.status_output_buffer).instance_id = hit.instance_id;
                    deref(p.status_output_buffer).primitive_id = hit.primitive_id;

                    if(ray_box_intersection(ray, hit, material_index, lcg) == true) {
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
                        deref(p.status_output_buffer).material_index = material_index;
                        deref(p.status_output_buffer).uv = hit.uv;
                        
                        rayQueryGenerateIntersectionEXT(ray_query, hit.hit_distance);
                        
                        uint type_commited = rayQueryGetIntersectionTypeEXT(ray_query, true);

                        if(type_commited ==
                            gl_RayQueryCommittedIntersectionGeneratedEXT)
                        { 

                            break;
                        }
                    }
                }
            }
        }
    }
#endif // PERFECT_PIXEL
}