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
    prd.instance_id = MAX_INSTANCES;
    prd.primitive_id = MAX_PRIMITIVES;

    daxa_u32 ray_flags = gl_RayFlagsNoneEXT;
    daxa_f32 t_min = 0.0001;
    daxa_f32 t_max = 10000.0;
    daxa_u32 cull_mask = 0xFF;

    daxa_u32 screen_pos = index.y * rt_size.x + index.x;


// #if SER == 1
//     hitObjectNV hitObject;
//     //Initialize to an empty hit object
//     hitObjectRecordEmptyNV(hitObject);

//     // Trace the ray
//     hitObjectTraceRayNV(hitObject,
//                         daxa_accelerationStructureEXT(p.tlas), // topLevelAccelerationStructure
//                         ray_flags,      // rayFlags
//                         cull_mask,      // cullMask
//                         0,             // sbtRecordOffset
//                         0,             // sbtRecordStride
//                         0,             // missIndex
//                         ray.origin.xyz,    // ray origin
//                         t_min,          // ray min range
//                         ray.direction.xyz, // ray direction
//                         t_max,          // ray max range
//                         0              // payload (location = 0)
//     );


//     daxa_u32 instance_id = MAX_PRIMITIVES;
//     daxa_u32 primitive_id = MAX_PRIMITIVES;
//     daxa_f32vec3 world_hit = vec3(0.0);
//     daxa_f32vec3 world_nrm = vec3(0.0);
//     daxa_f32 distance = -1.0;
//     daxa_f32mat4x4 model;
//     daxa_f32mat4x4 inv_model;
    
//     if(hitObjectIsHitNV(hitObject))
//     { 
//         instance_id = hitObjectGetInstanceCustomIndexNV(hitObject);

//         primitive_id = hitObjectGetPrimitiveIndexNV(hitObject);

//         reorderThreadNV(hitObject);

//         distance = is_hit_from_ray(ray, instance_id, primitive_id, distance, world_hit, world_nrm, model, inv_model, true, false) ? distance : -1.0;

//         daxa_f32vec4 world_hit_4 = (model * vec4(world_hit, 1));
//         world_hit = (world_hit_4 / world_hit_4.w).xyz;
//         world_nrm = (transpose(inv_model) * vec4(world_nrm, 0)).xyz;
//     }

//     if(distance > 0.0) {

//         MATERIAL mat = get_material_from_instance_and_primitive_id(instance_id, primitive_id);

//         // LIGHTS
//         daxa_u32 light_count = deref(p.status_buffer).light_count;

//         // OBJECTS
//         daxa_u32 object_count = deref(p.status_buffer).obj_count;

//         HIT_INFO_INPUT hit = HIT_INFO_INPUT(
//             daxa_f32vec3(0.0),
//             // NOTE: In order to avoid self intersection we need to offset the ray origin
//             world_hit + world_nrm * AVOID_VOXEL_COLLAIDE,
//             world_nrm,
//             instance_id,
//             primitive_id,
//             prd.seed,
//             prd.depth);
        
//         daxa_f32 p_hat = 0;
//         daxa_f32 pdf = 1.0 / daxa_f32(light_count);
//         RESERVOIR reservoir = RIS(light_count, ray, hit, mat, pdf, p_hat);

//         // Store the reservoir
//         deref(p.reservoir_buffer).reservoirs[screen_pos] = reservoir;

//         // Previous frame screen coord
//         daxa_f32vec2 motion_vector = get_motion_vector(index.xy, world_hit, rt_size.xy, instance_id,  model);

//         VELOCITY velocity = VELOCITY(motion_vector);
//         deref(p.velocity_buffer).velocities[screen_pos] = velocity;

//         seed = hit.seed;
//     } else {
//         daxa_f32vec3 hit_value = calculate_sky_color(
//                     deref(p.status_buffer).time, 
//                     deref(p.status_buffer).is_afternoon,
//                     ray.direction.xyz);

//         imageStore(daxa_image2D(p.swapchain), index, vec4(hit_value, 1.0));
//     }

//     DIRECT_ILLUMINATION_INFO di_info = DIRECT_ILLUMINATION_INFO(world_hit, distance, world_nrm, seed, instance_id, primitive_id);

// #else
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

    DIRECT_ILLUMINATION_INFO di_info = DIRECT_ILLUMINATION_INFO(prd.world_hit, prd.distance, prd.world_nrm, prd.seed, prd.instance_id, prd.primitive_id);

    daxa_b32 is_hit = di_info.distance > 0.0;
// #if SER == 1
//     reorderThreadNV(daxa_u32(hit_value), 1);
// #endif // SER

    if(is_hit == false) {
        imageStore(daxa_image2D(p.swapchain), index, vec4(prd.hit_value, 1.0));
    } else {
        daxa_f32mat4x4 instance_model = get_geometry_transform_from_instance_id(di_info.instance_id);

        // Previous frame screen coord
        daxa_f32vec2 motion_vector = get_motion_vector(index.xy, di_info.position, rt_size.xy, di_info.instance_id,  instance_model);

        VELOCITY velocity = VELOCITY(motion_vector);
        deref(p.velocity_buffer).velocities[screen_pos] = velocity;

        {
            // Get sample info from reservoir
            RESERVOIR reservoir = deref(p.reservoir_buffer).reservoirs[screen_pos];

            // Get material
            MATERIAL mat = get_material_from_instance_and_primitive_id(di_info.instance_id, di_info.primitive_id);

            // Get light count
            daxa_u32 light_count = deref(p.status_buffer).light_count;

            HIT_INFO_INPUT hit = HIT_INFO_INPUT(daxa_f32vec3(0.0),
                // NOTE: In order to avoid self intersection we need to offset the ray origin
                di_info.position,
                di_info.normal,
                di_info.instance_id,
                di_info.primitive_id,
                di_info.seed,
                max_depth);

            daxa_f32vec3 radiance = vec3(0.0);

            daxa_f32 p_hat = 0.0;

            // Calculate reservoir radiance
            calculate_reservoir_radiance(reservoir, ray, hit, mat, light_count, p_hat, radiance);

            di_info.seed = hit.seed;
#if (RESERVOIR_TEMPORAL_ON == 1)
            // Update reservoir
            deref(p.reservoir_buffer).reservoirs[screen_pos] = reservoir;
#else
            // Update reservoir
            deref(p.intermediate_reservoir_buffer).reservoirs[screen_pos] = reservoir;
#endif // RESERVOIR_TEMPORAL_ON
        }
    }
// #endif // SER

    // Store the DI info
    deref(p.di_buffer).DI_info[screen_pos] = di_info;
}

#elif TEMPORAL_REUSE_PASS == 1

void main() {
    
#if (RESERVOIR_TEMPORAL_ON == 1)
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
    DIRECT_ILLUMINATION_INFO di_info = deref(p.di_buffer).DI_info[screen_pos];
    
    daxa_b32 is_hit = di_info.distance > 0.0;
// #if SER == 1
//     reorderThreadNV(daxa_u32(hit_value), 1);
// #endif // SER
    if(is_hit) {
        // Get sample info from reservoir
        RESERVOIR reservoir = deref(p.reservoir_buffer).reservoirs[screen_pos];

        daxa_u32 light_count = deref(p.status_buffer).light_count;

        daxa_f32 pdf = 1.0 / daxa_f32(light_count);
        
        // Get material
        MATERIAL mat = get_material_from_instance_and_primitive_id(di_info.instance_id, di_info.primitive_id);

        VELOCITY velocity = deref(p.velocity_buffer).velocities[screen_pos];
            
        // X from current pixel position
        daxa_f32vec2 Xi = daxa_f32vec2(index.xy) + 0.5;

        daxa_f32vec2 Xi_1 = Xi + velocity.velocity;

        daxa_u32vec2 predicted_coord = daxa_u32vec2(Xi_1);

        HIT_INFO_INPUT hit = HIT_INFO_INPUT(daxa_f32vec3(0.0),
                                            // NOTE: In order to avoid self intersection we need to offset the ray origin
                                            di_info.position.xyz,
                                            di_info.normal.xyz,
                                            di_info.instance_id,
                                            di_info.primitive_id,
                                            di_info.seed,
                                            max_depth);

        // NOTE: the fact that we are getting spatial reservoirs from the current frame
        TEMPORAL_REUSE(reservoir,
                       predicted_coord,
                       rt_size,
                       ray, hit,
                       mat,
                       light_count,
                       pdf);

        di_info.seed = hit.seed;
        deref(p.di_buffer).DI_info[screen_pos].seed = di_info.seed;

        deref(p.intermediate_reservoir_buffer).reservoirs[screen_pos] = reservoir;
    }
#endif // RESERVOIR_TEMPORAL_ON
}

#elif SECOND_VISIBILITY_TEST == 1
void main() {
#if (RESERVOIR_TEMPORAL_ON == 1)
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
    DIRECT_ILLUMINATION_INFO di_info = deref(p.di_buffer).DI_info[screen_pos];

    daxa_f32 p_hat = 0.0;

    daxa_b32 is_hit = di_info.distance > 0.0;
// #if SER == 1
//     reorderThreadNV(daxa_u32(hit_value), 1);
// #endif // SER
    if(is_hit) {
        // Get sample info from reservoir
        RESERVOIR reservoir = deref(p.intermediate_reservoir_buffer).reservoirs[screen_pos];

        // Get material
        MATERIAL mat = get_material_from_instance_and_primitive_id(di_info.instance_id, di_info.primitive_id);

        // Get light count
        daxa_u32 light_count = deref(p.status_buffer).light_count;

        HIT_INFO_INPUT hit = HIT_INFO_INPUT(daxa_f32vec3(0.0),
            // NOTE: In order to avoid self intersection we need to offset the ray origin
            di_info.position,
            di_info.normal,
            di_info.instance_id,
            di_info.primitive_id,
            di_info.seed,
            max_depth);

        daxa_f32vec3 radiance = vec3(0.0);

        // Calculate reservoir radiance
        calculate_reservoir_radiance(reservoir, ray, hit, mat, light_count, p_hat, radiance);

        di_info.seed = hit.seed;
        deref(p.di_buffer).DI_info[screen_pos].seed = di_info.seed;
#if (RESERVOIR_SPATIAL_ON == 1)
        // Update reservoir
        deref(p.intermediate_reservoir_buffer).reservoirs[screen_pos] = reservoir;
#else
        // Update reservoir
        deref(p.reservoir_buffer).reservoirs[screen_pos] = reservoir;
#endif // RESERVOIR_SPATIAL_ON
#endif // RESERVOIR_TEMPORAL_ON
    }
}

#elif SPATIAL_REUSE_PASS == 1
void main() {
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
    DIRECT_ILLUMINATION_INFO di_info = deref(p.di_buffer).DI_info[screen_pos];
    
    daxa_b32 is_hit = di_info.distance > 0.0;
// #if SER == 1
//     reorderThreadNV(daxa_u32(hit_value), 1);
// #endif // SER
    if(is_hit) {
        daxa_f32mat4x4 instance_model = get_geometry_transform_from_instance_id(di_info.instance_id);
    
#if (RESERVOIR_TEMPORAL_ON == 1)
        // Get sample info from reservoir
        RESERVOIR reservoir = deref(p.intermediate_reservoir_buffer).reservoirs[screen_pos];
#else
        // Get sample info from reservoir
        RESERVOIR reservoir = deref(p.reservoir_buffer).reservoirs[screen_pos];
#endif // RESERVOIR_TEMPORAL_ON

        daxa_u32 light_count = deref(p.status_buffer).light_count;

        daxa_f32 pdf = 1.0 / daxa_f32(light_count);

        daxa_u32 current_mat_index = get_material_index_from_instance_and_primitive_id(di_info.instance_id, di_info.primitive_id);
        
        // Get material
        MATERIAL mat = get_material_from_material_index(current_mat_index);

        VELOCITY velocity = deref(p.velocity_buffer).velocities[screen_pos];
        // X from current pixel position
        daxa_f32vec2 Xi = daxa_f32vec2(index.xy) + 0.5;

        daxa_f32vec2 Xi_1 = Xi + velocity.velocity;

        daxa_u32vec2 predicted_coord = daxa_u32vec2(Xi_1);

        HIT_INFO_INPUT hit = HIT_INFO_INPUT(daxa_f32vec3(0.0),
                                            // NOTE: In order to avoid self intersection we need to offset the ray origin
                                            di_info.position.xyz,
                                            di_info.normal.xyz,
                                            di_info.instance_id,
                                            di_info.primitive_id,
                                            di_info.seed,
                                            max_depth);

                                            // (inout RESERVOIR reservoir, daxa_u32vec2 predicted_coord, daxa_u32vec2 rt_size, Ray ray, inout HIT_INFO_INPUT hit, daxa_u32 current_mat_index, MATERIAL mat, daxa_u32 light_count, daxa_f32 pdf)

        SPATIAL_REUSE(reservoir, index, rt_size, ray, hit, current_mat_index, mat, light_count, pdf);
        
        di_info.seed = hit.seed;
        deref(p.di_buffer).DI_info[screen_pos].seed = di_info.seed;

        deref(p.reservoir_buffer).reservoirs[screen_pos] = reservoir;
    }
#endif // RESERVOIR_SPATIAL_ON
}

#elif THIRD_VISIBILITY_TEST_AND_SHADING_PASS == 1

void main()
{
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
    DIRECT_ILLUMINATION_INFO di_info = deref(p.di_buffer).DI_info[screen_pos];

    // Get sample info from reservoir
    RESERVOIR reservoir = 
#if (RESERVOIR_TEMPORAL_ON == 1) || (RESERVOIR_SPATIAL_ON == 0)
        deref(p.intermediate_reservoir_buffer).reservoirs[screen_pos];
#else        
    deref(p.reservoir_buffer).reservoirs[screen_pos];
#endif // RESERVOIR_TEMPORAL_ON

    daxa_b32 is_hit = di_info.distance > 0.0;
    // #if SER == 1
    //     reorderThreadNV(daxa_u32(hit_value), 1);
    // #endif // SER
    if (is_hit)
    {
        daxa_f32vec3 hit_value = vec3(0.0);
// #if INDIRECT_ILLUMINATION_ON == 1
        prd.hit_value = vec3(1.0);
        // prd.throughput = vec3(1.0);
        prd.seed = di_info.seed;
        prd.depth = max_depth - 1;
        prd.world_hit = di_info.position;
        prd.distance = di_info.distance;
        prd.world_nrm = di_info.normal;
        prd.instance_id = di_info.instance_id;
        prd.primitive_id = di_info.primitive_id;

        daxa_f32vec3 ray_origin = prd.world_hit;
        daxa_f32vec3 ray_direction = prd.world_nrm;

        daxa_u32 ray_flags = gl_RayFlagsNoneEXT;
        daxa_f32 t_min = 0.0001;
        daxa_f32 t_max = 10000.0;
        daxa_u32 cull_mask = 0xFF;

        daxa_u32 bounces_count = max_depth;

        for (daxa_u32 i = 0; i < bounces_count; i++)
        {

            // #if SER == 1
            // //     reorderThreadNV(daxa_u32(hit_value), 1);

            // #else
            traceRayEXT(daxa_accelerationStructureEXT(p.tlas),
                        ray_flags,     // rayFlags
                        cull_mask,     // cullMask
                        1,             // sbtRecordOffset
                        0,             // sbtRecordStride
                        0,             // missIndex
                        ray_origin,    // ray origin
                        t_min,         // ray min range
                        ray_direction, // ray direction
                        t_max,         // ray max range
                        0              // payload (location = 0)
            );
            // #endif // SER

            hit_value += prd.hit_value;

            prd.depth--;
            if (prd.done == true || prd.depth == 0)
                break;

            ray_origin = prd.world_hit;
            ray_direction = prd.world_nrm;
            prd.done = true; // Will stop if a reflective material isn't hit
        }
// #endif // INDIRECT_ILLUMINATION_ON

        // Get material
        MATERIAL mat = get_material_from_instance_and_primitive_id(di_info.instance_id, di_info.primitive_id);

        // Get light count
        daxa_u32 light_count = deref(p.status_buffer).light_count;

        HIT_INFO_INPUT hit = HIT_INFO_INPUT(daxa_f32vec3(0.0),
                                            // NOTE: In order to avoid self intersection we need to offset the ray origin
                                            di_info.position.xyz,
                                            di_info.normal.xyz,
                                            di_info.instance_id,
                                            di_info.primitive_id,
                                            di_info.seed,
                                            max_depth);
        daxa_f32 p_hat = 0.0;

        daxa_f32vec3 radiance = vec3(0.0);

        calculate_reservoir_radiance(reservoir, ray, hit, mat, light_count, p_hat, radiance);

        daxa_f32 pdf = 1.0 / daxa_f32(light_count);
        daxa_f32 pdf_out = 0.0;

        
        LIGHT light = deref(p.light_buffer).lights[get_reservoir_light_index(reservoir)];
        hit_value *= radiance * reservoir.W_y;
            
        clamp(hit_value, 0.0, 0.99999999);

        imageStore(daxa_image2D(p.swapchain), index, daxa_f32vec4(hit_value, 1.0));
        
        di_info.seed = hit.seed;
    }

    // Store the reservoir
    deref(p.previous_reservoir_buffer).reservoirs[screen_pos] = reservoir;

    deref(p.previous_di_buffer).DI_info[screen_pos] = di_info;

}

#else

void main()
{

}

#endif // RESTIR_PREPASS