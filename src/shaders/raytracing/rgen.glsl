#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>

#include "shared.inl"
#include "defines.glsl"
#include "prng.glsl"
#include "reservoir.glsl"

#if SER == 1
#extension GL_NV_shader_invocation_reorder : enable
layout(location = 0) hitObjectAttributeNV vec3 hitValue;
#else
#extension GL_EXT_ray_query : enable
#endif

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

#if RESTIR_PREPASS == 1

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

    // Ensure that the reservoir is initialized
    RESERVOIR new_reservoir;
    initialise_reservoir(new_reservoir);
    deref(p.reservoir_buffer).reservoirs[screen_pos] = new_reservoir;


    deref(p.di_buffer).DI_info[screen_pos] = DIRECT_ILLUMINATION_INFO(prd.world_hit, prd.distance, prd.world_nrm, prd.instance_id, prd.primitive_id);


#if SER == 1
    hitObjectNV hitObject;
    //Initialize to an empty hit object
    hitObjectRecordEmptyNV(hitObject);

    // Trace the ray
    hitObjectTraceRayNV(hitObject,
                        daxa_accelerationStructureEXT(p.tlas), // topLevelAccelerationStructure
                        rayFlags,      // rayFlags
                        cullMask,      // cullMask
                        0,             // sbtRecordOffset
                        0,             // sbtRecordStride
                        0,             // missIndex
                        origin.xyz,    // ray origin
                        tMin,          // ray min range
                        direction.xyz, // ray direction
                        tMax,          // ray max range
                        0              // payload (location = 0)
    );


    daxa_u32 instance_id = MAX_PRIMITIVES;
    
    if(hitObjectIsHitNV(hitObject))
    { 
        instance_id = hitObjectGetInstanceCustomIndexNV(hitObject);
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

    DIRECT_ILLUMINATION_INFO di_info = DIRECT_ILLUMINATION_INFO(prd.world_hit, prd.distance, prd.world_nrm, prd.instance_id, prd.primitive_id);
    
    if(prd.distance == -1.0) {
        imageStore(daxa_image2D(p.swapchain), index, vec4(prd.hit_value, 1.0));
    } else {
        daxa_f32mat4x4 instance_model = get_geometry_transform_from_instance_id(di_info.instance_id);

        // Previous frame screen coord
        daxa_f32vec2 motion_vector = get_motion_vector(index.xy, di_info.position, rt_size.xy, di_info.instance_id,  instance_model);

        VELOCITY velocity = VELOCITY(motion_vector);
        deref(p.velocity_buffer).velocities[screen_pos] = velocity;
    }
#endif // SER

    // Store the DI info
    deref(p.di_buffer).DI_info[screen_pos] = di_info;
}



#elif FIRST_VISIBILITY_TEST == 1
void main() {

    const daxa_i32vec2 index = ivec2(gl_LaunchIDEXT.xy);
    const daxa_u32vec2 rt_size = gl_LaunchSizeEXT.xy;

    // Camera setup
    daxa_f32mat4x4 inv_view = deref(p.camera_buffer).inv_view;
    daxa_f32mat4x4 inv_proj = deref(p.camera_buffer).inv_proj;
    
    daxa_u32 max_depth = deref(p.status_buffer).max_depth;
    daxa_u32 frame_number = deref(p.status_buffer).frame_number;

    daxa_u32 seed = tea(index.y * rt_size.x + index.x, frame_number * SAMPLES_PER_PIXEL);

    // Ray setup
    Ray ray = get_ray_from_current_pixel(index, vec2(rt_size), inv_view, inv_proj);

    // screen_pos is the index of the pixel in the screen
    daxa_u32 screen_pos = index.y * rt_size.x + index.x;

    // Get sample info from reservoir
    RESERVOIR reservoir = deref(p.reservoir_buffer).reservoirs[screen_pos];
    
    // Get hit info
    DIRECT_ILLUMINATION_INFO di_info = deref(p.di_buffer).DI_info[screen_pos];

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
        seed,
        max_depth);

    daxa_f32 p_hat = 0.0;

    if(di_info.distance > 0.0) {
        // Calculate reservoir radiance
        calculate_reservoir_radiance(reservoir, ray, hit, mat, light_count, p_hat);

        // Update reservoir
        deref(p.reservoir_buffer).reservoirs[screen_pos] = reservoir;
    }

}

#elif TEMPORAL_REUSE_PASS == 1

void main() {
    const daxa_i32vec2 index = ivec2(gl_LaunchIDEXT.xy);
    const daxa_u32vec2 rt_size = gl_LaunchSizeEXT.xy;

    // Camera setup
    daxa_f32mat4x4 inv_view = deref(p.camera_buffer).inv_view;
    daxa_f32mat4x4 inv_proj = deref(p.camera_buffer).inv_proj;
    
    daxa_u32 max_depth = deref(p.status_buffer).max_depth;
    daxa_u32 frame_number = deref(p.status_buffer).frame_number;

    daxa_u32 seed = tea(index.y * rt_size.x + index.x, frame_number * SAMPLES_PER_PIXEL);

    // Ray setup
    Ray ray = get_ray_from_current_pixel(index, vec2(rt_size), inv_view, inv_proj);

    // screen_pos is the index of the pixel in the screen
    daxa_u32 screen_pos = index.y * rt_size.x + index.x;
    
     // Get hit info
    DIRECT_ILLUMINATION_INFO di_info = deref(p.di_buffer).DI_info[screen_pos];
    
    if(di_info.distance > 0.0) {
        
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
                                            seed,
                                            max_depth);

        // NOTE: the fact that we are getting spatial reservoirs from the current frame
        TEMPORAL_REUSE(reservoir,
                       predicted_coord,
                       rt_size,
                       ray, hit,
                       mat,
                       light_count,
                       pdf);

        deref(p.reservoir_buffer).reservoirs[screen_pos] = reservoir;
    }

}

#elif SECOND_VISIBILITY_TEST == 1
void main() {

}

#elif SPATIAL_REUSE_PASS == 1
void main() {
    const daxa_i32vec2 index = ivec2(gl_LaunchIDEXT.xy);
    const daxa_u32vec2 rt_size = gl_LaunchSizeEXT.xy;

    // Camera setup
    daxa_f32mat4x4 inv_view = deref(p.camera_buffer).inv_view;
    daxa_f32mat4x4 inv_proj = deref(p.camera_buffer).inv_proj;
    
    daxa_u32 max_depth = deref(p.status_buffer).max_depth;
    daxa_u32 frame_number = deref(p.status_buffer).frame_number;

    daxa_u32 seed = tea(index.y * rt_size.x + index.x, frame_number * SAMPLES_PER_PIXEL);

    // Ray setup
    Ray ray = get_ray_from_current_pixel(index, vec2(rt_size), inv_view, inv_proj);

    // screen_pos is the index of the pixel in the screen
    daxa_u32 screen_pos = index.y * rt_size.x + index.x;
    
     // Get hit info
    DIRECT_ILLUMINATION_INFO di_info = deref(p.di_buffer).DI_info[screen_pos];
    
    if(di_info.distance > 0.0) {

        daxa_f32mat4x4 instance_model = get_geometry_transform_from_instance_id(di_info.instance_id);
        
        // Get sample info from reservoir
        RESERVOIR reservoir = deref(p.reservoir_buffer).reservoirs[screen_pos];

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
                                            seed,
                                            max_depth);

                                            // (inout RESERVOIR reservoir, daxa_u32vec2 predicted_coord, daxa_u32vec2 rt_size, Ray ray, inout HIT_INFO_INPUT hit, daxa_u32 current_mat_index, MATERIAL mat, daxa_u32 light_count, daxa_f32 pdf)

        SPATIAL_REUSE(reservoir, predicted_coord, rt_size, ray, hit, current_mat_index, mat, light_count, pdf);

        deref(p.reservoir_buffer).reservoirs[screen_pos] = reservoir;
    }
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
    daxa_u32 frame_number = deref(p.status_buffer).frame_number;

    daxa_u32 seed = tea(index.y * rt_size.x + index.x, frame_number * SAMPLES_PER_PIXEL);

    // Ray setup
    Ray ray = get_ray_from_current_pixel(index, vec2(rt_size), inv_view, inv_proj);

    // screen_pos is the index of the pixel in the screen
    daxa_u32 screen_pos = index.y * rt_size.x + index.x;

    // Get hit info
    DIRECT_ILLUMINATION_INFO di_info = deref(p.di_buffer).DI_info[screen_pos];

    // Get sample info from reservoir
    RESERVOIR reservoir = deref(p.reservoir_buffer).reservoirs[screen_pos];
    

    if(di_info.distance > 0.0) {
        
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
                                            seed,
                                            max_depth);
        daxa_f32 p_hat = 0.0;

        // calculate_reservoir_radiance(reservoir, ray, hit, mat, light_count, p_hat);

        daxa_f32 pdf = 1.0 / daxa_f32(light_count);
        daxa_f32 pdf_out = 0.0;

        
        LIGHT light = deref(p.light_buffer).lights[get_reservoir_light_index(reservoir)];
        // TODO: Reuse calculate_sampled_light from calculate reservoir radiance
        daxa_f32vec3 hit_value = calculate_sampled_light(ray, hit, light, mat, light_count, pdf, pdf_out, true, false, false) * reservoir.W_y;
            
        clamp(hit_value, 0.0, 0.99999999);

        imageStore(daxa_image2D(p.swapchain), index, daxa_f32vec4(hit_value, 1.0));
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