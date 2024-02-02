#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>

#if SER == 1
#extension GL_NV_shader_invocation_reorder : enable
layout(location = 0) hitObjectAttributeNV vec3 hit_value;
#else
#extension GL_EXT_ray_query : enable
#endif

#include "shared.inl"
#include "defines.glsl"
#include "prng.glsl"
#include "reservoir.glsl"
#include "indirect_illumination.glsl"


Ray get_ray_from_current_pixel(daxa_f32vec2 index, daxa_f32vec2 rt_size, daxa_f32mat4x4 inv_view, daxa_f32mat4x4 inv_proj) {
    const daxa_f32vec2 pixel_center = index + vec2(0.5);
    const daxa_f32vec2 inv_UV = pixel_center / rt_size;
    daxa_f32vec2 d = inv_UV * 2.0 - 1.0;
    
    // Ray setup
    Ray ray;

    daxa_f32vec4 origin = inv_view * vec4(0,0,0,1);
    ray.origin = origin.xyz;

    vec4 target = inv_proj * vec4(d.x, d.y, 1, 1) ;
    vec4 direction = inv_view * vec4(normalize(target.xyz), 0) ;

    ray.direction = direction.xyz;

    return ray;
}

#if RESTIR_PREPASS_AND_FIRST_VISIBILITY_TEST == 1

void main()
{
    const daxa_i32vec2 index = daxa_i32vec2(gl_LaunchIDEXT.xy);
    const daxa_u32vec2 rt_size = gl_LaunchSizeEXT.xy;

    // Camera setup
    daxa_f32mat4x4 inv_view = deref(p.camera_buffer).inv_view;
    daxa_f32mat4x4 inv_proj = deref(p.camera_buffer).inv_proj;

    Ray ray = get_ray_from_current_pixel(daxa_f32vec2(index), daxa_f32vec2(rt_size), inv_view, inv_proj);
    
    daxa_u32 max_depth = deref(p.status_buffer).max_depth;
    daxa_u32 frame_number = deref(p.status_buffer).frame_number;

    daxa_u32 seed = tea(index.y * rt_size.x + index.x, frame_number * SAMPLES_PER_PIXEL);

    prd.hit_value = vec3(1.0);
    prd.seed = seed;
    prd.depth = max_depth;
    prd.world_hit = vec3(0.0);
    prd.distance = -1.0;
    prd.world_nrm = vec3(0.0);
    prd.instance_hit = INSTANCE_HIT(MAX_INSTANCES - 1, MAX_PRIMITIVES - 1);

    daxa_u32 ray_flags = gl_RayFlagsNoneEXT;
    daxa_f32 t_min = DELTA_RAY;
    daxa_f32 t_max = MAX_DISTANCE - DELTA_RAY;
    daxa_u32 cull_mask = 0xFF;

    daxa_u32 screen_pos = index.y * rt_size.x + index.x;


    daxa_b32 is_hit = false;


#if SER == 1
    daxa_f32mat4x4 model;
    daxa_f32mat4x4 inv_model;
    daxa_f32 distance = -1.0;

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
                        ray.origin.xyz,                        // ray origin
                        t_min,                                 // ray min range
                        ray.direction.xyz,                     // ray direction
                        t_max,                                 // ray max range
                        0                                      // payload (location = 0)
    );

    // reorderThreadNV(hit_object);


    if (hitObjectIsHitNV(hit_object))
    {

        daxa_u32 instance_id = hitObjectGetInstanceCustomIndexNV(hit_object);

        daxa_u32 primitive_id = hitObjectGetPrimitiveIndexNV(hit_object);

        prd.instance_hit = INSTANCE_HIT(instance_id, primitive_id);

        // TODO: pass this as a parameter
        daxa_f32vec3 half_extent = vec3(HALF_VOXEL_EXTENT);

        daxa_f32 distance = -1.0;

        prd.distance = is_hit_from_ray(ray, prd.instance_hit, half_extent, distance, prd.world_hit, prd.world_nrm, model, inv_model, true, false) ? distance : -1.0;

        daxa_f32vec4 world_hit_4 = (model * vec4(prd.world_hit, 1));
        prd.world_hit = (world_hit_4 / world_hit_4.w).xyz;
        prd.world_nrm = (transpose(inv_model) * vec4(prd.world_nrm, 0)).xyz;
        prd.world_hit += prd.world_nrm * DELTA_RAY;

        prd.mat_index = get_material_index_from_instance_and_primitive_id(prd.instance_hit);
    }  else {
        prd.hit_value *= calculate_sky_color(
            deref(p.status_buffer).time,
            deref(p.status_buffer).is_afternoon,
            ray.direction);
    }

#else
    traceRayEXT(
        daxa_accelerationStructureEXT(p.tlas),
        ray_flags,         // rayFlags
        cull_mask,         // cullMask
        0,                 // sbtRecordOffset
        0,                 // sbtRecordStride
        0,                 // missIndex
        ray.origin.xyz,    // ray origin
        t_min,             // ray min range
        ray.direction.xyz, // ray direction
        t_max,             // ray max range
        0                  // payload (location = 0)
    );
#endif // SER

    DIRECT_ILLUMINATION_INFO di_info = DIRECT_ILLUMINATION_INFO(prd.world_hit, prd.distance, prd.world_nrm, prd.ray_scatter_dir, prd.seed, prd.instance_hit, prd.mat_index, 1.0);

    is_hit = di_info.distance > 0.0;

    if(is_hit == false) {
        imageStore(daxa_image2D(p.swapchain), index, vec4(prd.hit_value, 1.0));
    } else {
        daxa_f32mat4x4 instance_model = get_geometry_transform_from_instance_id(di_info.instance_hit.instance_id);

        // Previous frame screen coord
        daxa_f32vec2 motion_vector = get_motion_vector(index.xy, di_info.position, rt_size.xy, di_info.instance_hit.instance_id, instance_model);

        VELOCITY velocity = VELOCITY(motion_vector);
        velocity_buffer_set_velocity(index, rt_size, velocity);
        

        daxa_u32 light_count = deref(p.status_buffer).light_count;
        // OBJECTS
        daxa_u32 object_count = deref(p.status_buffer).obj_count;

        daxa_f32 pdf = 1.0 / daxa_f32(light_count);
        
        // Get material
        MATERIAL mat = get_material_from_material_index(di_info.mat_index);
            
        // X from current pixel position
        daxa_f32vec2 Xi = daxa_f32vec2(index.xy) + 0.5;

        daxa_f32vec2 Xi_1 = Xi + velocity.velocity;

        daxa_u32vec2 predicted_coord = daxa_u32vec2(Xi_1);

        HIT_INFO_INPUT hit = HIT_INFO_INPUT(
                                            di_info.position.xyz,
                                            di_info.normal.xyz,
                                            di_info.distance,
                                            di_info.scatter_dir,
                                            di_info.instance_hit,
                                            di_info.mat_index,
                                            di_info.seed,
                                            max_depth);

        daxa_f32 confidence = 1.0;

#if RESERVOIR_ON == 1
#if (RESERVOIR_TEMPORAL_ON == 1)
        // Reservoir from previous frame
        RESERVOIR reservoir_previous = GATHER_TEMPORAL_RESERVOIR(predicted_coord, rt_size, hit);

        // TODO: re-check this
        // Confidence when using temporal reuse and M is the number of samples in the reservoir predicted should be 0.01 (1%) if M == 0 then 1.0 (100%). Interpolated between those values
        daxa_f32 predicted = 1.0 - clamp((reservoir_previous.M / daxa_f32(MAX_RIS_SAMPLE_COUNT)), 0.0, 1.0);

        confidence = (reservoir_previous.W_y > 0.0) ? predicted
                                                    : 1.0;

#endif // RESERVOIR_TEMPORAL_ON

        di_info.confidence = confidence;

        {
            daxa_f32vec3 radiance = vec3(0.0);

            daxa_f32 p_hat = 0.0;

            INTERSECT i;

            RESERVOIR reservoir = FIRST_GATHER(light_count, object_count, screen_pos, confidence, ray, hit, mat, p_hat, i);

            calculate_reservoir_radiance(reservoir, ray, hit, mat, light_count, p_hat, radiance);

            di_info.seed = hit.seed;

            set_reservoir_from_intermediate_frame_by_index(screen_pos, reservoir);
        }
#endif // RESERVOIR_ON
        set_di_seed_from_current_frame(screen_pos, di_info.seed);
    }

    // Store the DI info
    set_di_from_current_frame(screen_pos, di_info);
}

#elif TEMPORAL_REUSE_PASS == 1

void main() { 
#if RESERVOIR_ON == 1
    const daxa_i32vec2 index = ivec2(gl_LaunchIDEXT.xy);
    const daxa_u32vec2 rt_size = gl_LaunchSizeEXT.xy;

    // Camera setup
    daxa_f32mat4x4 inv_view = deref(p.camera_buffer).inv_view;
    daxa_f32mat4x4 inv_proj = deref(p.camera_buffer).inv_proj;
    
    daxa_u32 max_depth = deref(p.status_buffer).max_depth;

    // Ray setup
    Ray ray = get_ray_from_current_pixel(index, vec2(rt_size), inv_view, inv_proj);

    // screen_pos is the index of the pixel in the screen
    daxa_u32 screen_pos = index.y * rt_size.x + index.x;
    
     // Get hit info
    DIRECT_ILLUMINATION_INFO di_info = get_di_from_current_frame(screen_pos);
    
    daxa_b32 is_hit = di_info.distance > 0.0;
// #if SER == 1
//     reorderThreadNV(daxa_u32(hit_value), 1);
// #endif // SER
    if(is_hit) {

        daxa_u32 light_count = deref(p.status_buffer).light_count;
        // OBJECTS
        daxa_u32 object_count = deref(p.status_buffer).obj_count;

        daxa_f32 pdf = 1.0 / daxa_f32(light_count);
        
        // Get material
        MATERIAL mat = get_material_from_material_index(di_info.mat_index);

        VELOCITY velocity = velocity_buffer_get_velocity(index, rt_size);
            
        // X from current pixel position
        daxa_f32vec2 Xi = daxa_f32vec2(index.xy) + 0.5;

        daxa_f32vec2 Xi_1 = Xi + velocity.velocity;

        daxa_u32vec2 predicted_coord = daxa_u32vec2(Xi_1);

        HIT_INFO_INPUT hit = HIT_INFO_INPUT(
                                            di_info.position.xyz,
                                            di_info.normal.xyz,
                                            di_info.distance,
                                            di_info.scatter_dir,
                                            di_info.instance_hit,
                                            di_info.mat_index,
                                            di_info.seed,
                                            max_depth);

        RESERVOIR reservoir = get_reservoir_from_intermediate_frame_by_index(screen_pos);

#if (RESERVOIR_TEMPORAL_ON == 1)
        // Reservoir from previous frame
        RESERVOIR reservoir_previous = GATHER_TEMPORAL_RESERVOIR(predicted_coord, rt_size, hit);
        if(reservoir_previous.W_y > 0.0) {
            TEMPORAL_REUSE(reservoir,
                           reservoir_previous,
                           predicted_coord,
                           rt_size,
                           ray,
                           hit,
                           mat,
                           light_count);
        }
#endif // RESERVOIR_TEMPORAL_ON

        di_info.seed = hit.seed;

        set_di_seed_from_current_frame(screen_pos, di_info.seed);

        set_reservoir_from_intermediate_frame_by_index(screen_pos, reservoir);
    }
#endif // RESERVOIR_ON
}

#elif SPATIAL_REUSE_PASS == 1
void main() {
#if RESERVOIR_ON == 1
#if (RESERVOIR_SPATIAL_ON == 1)
    const daxa_i32vec2 index = ivec2(gl_LaunchIDEXT.xy);
    const daxa_u32vec2 rt_size = gl_LaunchSizeEXT.xy;

    // Camera setup
    daxa_f32mat4x4 inv_view = deref(p.camera_buffer).inv_view;
    daxa_f32mat4x4 inv_proj = deref(p.camera_buffer).inv_proj;
    
    daxa_u32 max_depth = deref(p.status_buffer).max_depth;

    // Ray setup
    Ray ray = get_ray_from_current_pixel(index, vec2(rt_size), inv_view, inv_proj);

    // screen_pos is the index of the pixel in the screen
    daxa_u32 screen_pos = index.y * rt_size.x + index.x;
    
     // Get hit info
    DIRECT_ILLUMINATION_INFO di_info = get_di_from_current_frame(screen_pos);
    
    daxa_b32 is_hit = di_info.distance > 0.0;
// #if SER == 1
//     reorderThreadNV(daxa_u32(hit_value), 1);
// #endif // SER
    if(is_hit) {
        daxa_f32mat4x4 instance_model = get_geometry_transform_from_instance_id(di_info.instance_hit.instance_id);
    
        // Get sample info from reservoir
        RESERVOIR reservoir = get_reservoir_from_intermediate_frame_by_index(screen_pos);

        daxa_u32 light_count = deref(p.status_buffer).light_count;

        daxa_f32 pdf = 1.0 / daxa_f32(light_count);
        
        // Get material
        MATERIAL mat = get_material_from_material_index(di_info.mat_index);

        HIT_INFO_INPUT hit = HIT_INFO_INPUT(di_info.position.xyz,
                                            di_info.normal.xyz,
                                            di_info.distance,
                                            di_info.scatter_dir,
                                            di_info.instance_hit,
                                            di_info.mat_index,
                                            di_info.seed,
                                            max_depth);

        daxa_f32 confidence = di_info.confidence;

        SPATIAL_REUSE(reservoir, confidence, index, rt_size, ray, hit, di_info.mat_index, mat, light_count, pdf);
        
        di_info.seed = hit.seed;
        set_di_seed_from_current_frame(screen_pos, di_info.seed);

        set_reservoir_from_current_frame_by_index(screen_pos, reservoir);
    }
#endif // RESERVOIR_SPATIAL_ON
#endif // RESERVOIR_ON
}

#elif THIRD_VISIBILITY_TEST_AND_SHADING_PASS == 1

void main()
{
    const daxa_i32vec2 index = ivec2(gl_LaunchIDEXT.xy);
    const daxa_u32vec2 rt_size = gl_LaunchSizeEXT.xy;

    // Camera setup
    daxa_f32mat4x4 inv_view = deref(p.camera_buffer).inv_view;
    daxa_f32mat4x4 inv_proj = deref(p.camera_buffer).inv_proj;
    
    // TODO: check if we can reduce it to 1 or 2
    daxa_u32 max_depth = deref(p.status_buffer).max_depth;
    // daxa_u32 max_depth = 1;


    // Ray setup
    Ray ray = get_ray_from_current_pixel(index, vec2(rt_size), inv_view, inv_proj);

    // screen_pos is the index of the pixel in the screen
    daxa_u32 screen_pos = index.y * rt_size.x + index.x;

    // Get hit info
    DIRECT_ILLUMINATION_INFO di_info = get_di_from_current_frame(screen_pos);


#if RESERVOIR_ON == 1
    // Get sample info from reservoir
    RESERVOIR reservoir = 
#if (RESERVOIR_TEMPORAL_ON == 1) && (RESERVOIR_SPATIAL_ON == 0)
        get_reservoir_from_intermediate_frame_by_index(screen_pos);
#else        
        get_reservoir_from_current_frame_by_index(screen_pos);
#endif // RESERVOIR_TEMPORAL_ON
#endif // RESERVOIR_ON

    daxa_b32 is_hit = di_info.distance > 0.0;
// #if SER == 1
//     reorderThreadNV(daxa_u32(hit_value), 1);
// #endif // SER
    if (is_hit)
    {
        daxa_f32vec3 hit_value = vec3(0.0);
        prd.hit_value = vec3(1.0);
        daxa_f32vec3 throughput = vec3(0.0);

#if(DEBUG_NORMALS_ON == 1)
        hit_value = di_info.normal * 0.5 + 0.5;
#else        
        // Get material
        MATERIAL mat = get_material_from_material_index(di_info.mat_index);

        // Get light count
        daxa_u32 light_count = deref(p.status_buffer).light_count;
        // OBJECTS
        daxa_u32 object_count = deref(p.status_buffer).obj_count;

        HIT_INFO_INPUT hit = HIT_INFO_INPUT(di_info.position.xyz,
                                            di_info.normal.xyz,
                                            di_info.distance,
                                            di_info.scatter_dir,
                                            di_info.instance_hit,
                                            di_info.mat_index,
                                            di_info.seed,
                                            max_depth);
        daxa_f32 p_hat = 0.0;

        daxa_f32vec3 radiance = vec3(0.0);

        daxa_f32 pdf = 1.0 / daxa_f32(light_count);
        daxa_f32 pdf_out = 0.0; 


        INTERSECT i;
#if RESERVOIR_ON == 1
        //Calculate reservoir radiance
        calculate_reservoir_radiance(reservoir, ray, hit, mat, light_count, p_hat, radiance);
        //Build the intersect struct
        i = INTERSECT(is_hit, di_info.distance, di_info.position.xyz, di_info.normal.zyz, di_info.scatter_dir, di_info.instance_hit, di_info.mat_index, mat);
      
        // Add the radiance to the hit value (reservoir radiance)
        hit_value += radiance * reservoir.W_y;
#else // RESERVOIR_ON
        daxa_u32 light_index = min(urnd_interval(hit.seed, 0, light_count), light_count - 1);
        // Get light
        LIGHT light = get_light_from_light_index(light_index);
#if MIS_ON == 1
        // Calculate radiance
        radiance = direct_mis(ray, hit, light_count, light, object_count, mat, i, pdf_out, true, true);
        // Build the intersect struct
        di_info.scatter_dir = i.scatter_dir;
#else
        // Calculate radiance
        radiance = calculate_radiance(ray, hit, mat, light_count, light, pdf, pdf_out, true, true, true);
        // Build the intersect struct
        i = INTERSECT(is_hit, di_info.distance, di_info.position.xyz, di_info.normal.zyz, di_info.scatter_dir, di_info.instance_hit, di_info.mat_index, mat);
#endif // MIS_ON
        // Add the radiance to the hit value
        hit_value += radiance;
#endif // RESERVOIR_ON


        di_info.seed = hit.seed;
        

#if INDIRECT_ILLUMINATION_ON == 1        
        indirect_illumination(i, di_info.seed, max_depth, light_count, object_count, throughput);
        hit_value += throughput;
#endif // INDIRECT_ILLUMINATION_ON



        hit_value += mat.emission;

#endif // DEBUG_NORMALS_ON
            
        clamp(hit_value, 0.0, 0.99999999);

        daxa_f32vec4 final_pixel;
#if (ACCUMULATOR_ON == 1 && RESERVOIR_ON == 0)
        daxa_u32 num_accumulated_frames = deref(p.status_buffer).num_accumulated_frames;
        if (num_accumulated_frames > 0)
        {
            vec4 previous_frame_pixel = imageLoad(daxa_image2D(p.swapchain), index);

            vec4 current_frame_pixel = vec4(hit_value, 1.0f);

            daxa_f32 weight = 1.0f / (num_accumulated_frames + 1.0f);
            final_pixel = mix(previous_frame_pixel, current_frame_pixel, weight);
        }
        else
        {
            final_pixel = vec4(hit_value, 1.0f);
        }
#else
        final_pixel = vec4(hit_value, 1.0f);
#endif
        imageStore(daxa_image2D(p.swapchain), index, final_pixel);

#if RESERVOIR_ON == 1
        // Store the reservoir
        set_reservoir_from_previous_frame_by_index(screen_pos, reservoir);
#endif // RESERVOIR_ON    

        set_di_from_previous_frame(screen_pos, di_info);
    }
}

#else

void main()
{

}

#endif // RESTIR_PREPASS