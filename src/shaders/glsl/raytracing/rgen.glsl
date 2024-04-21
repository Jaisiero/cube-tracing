#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include "defines.glsl"

DAXA_DECL_PUSH_CONSTANT(PushConstant, p)

#include "prng.glsl"
#include "indirect_illumination.glsl"
#include "restir_resampling.glsl"

// #if SER == 1
// #extension GL_NV_shader_invocation_reorder : enable
// layout(location = 0) hitObjectAttributeNV vec3 hit_value;
// #else
// #extension GL_EXT_ray_query : enable
// #endif

Ray get_ray_from_current_pixel(daxa_f32vec2 index, daxa_f32vec2 rt_size,
                               daxa_f32mat4x4 inv_view, daxa_f32mat4x4 inv_proj,
                               inout daxa_u32 seed, inout daxa_f32vec2 jitter) {

  // jitter = daxa_f32vec2(rnd_interval(seed, -0.5f + HLF_MIN, 0.5f - HLF_MIN),
  //                       rnd_interval(seed, -0.5f + HLF_MIN, 0.5f - HLF_MIN));
  jitter = daxa_f32vec2(0.0);

  const daxa_f32vec2 pixel_center = index + jitter + daxa_f32vec2(0.5);
  const daxa_f32vec2 inv_UV = pixel_center / rt_size;
  daxa_f32vec2 d = inv_UV * 2.0 - 1.0;

  // Ray setup
  Ray ray;

  daxa_f32vec4 origin = inv_view * vec4(0, 0, 0, 1);
  ray.origin = origin.xyz;

  vec4 target = inv_proj * vec4(d.x, d.y, 1, 1);
  vec4 direction = inv_view * vec4(normalize(target.xyz), 0);

  ray.direction = direction.xyz;

  return ray;
}

#if RESTIR_PREPASS_AND_FIRST_VISIBILITY_TEST == 1

void main() {
  const daxa_i32vec2 index = daxa_i32vec2(gl_LaunchIDEXT.xy);
  const daxa_u32vec2 rt_size = gl_LaunchSizeEXT.xy;

  daxa_u32 active_features = deref(p.status_buffer).is_active;

  // Camera setup
  daxa_f32mat4x4 inv_view = deref(p.camera_buffer).inv_view;
  daxa_f32mat4x4 inv_proj = deref(p.camera_buffer).inv_proj;

  daxa_u32 max_depth = deref(p.status_buffer).max_depth;
  daxa_u32 frame_number = deref(p.status_buffer).frame_number;

  // daxa_u32 seed = tea(index.y * rt_size.x + index.x, frame_number *
  // SAMPLES_PER_PIXEL);
  daxa_u32 seed = tea(index.y * rt_size.x + index.x, frame_number);

  daxa_f32vec2 jitter;

  Ray ray =
      get_ray_from_current_pixel(daxa_f32vec2(index), daxa_f32vec2(rt_size),
                                 inv_view, inv_proj, seed, jitter);

  prd.hit_value = vec3(1.0);
  prd.seed = seed;
  prd.depth = max_depth;
  prd.world_hit = vec3(0.0);
  prd.distance = -1.0;
  prd.world_nrm = vec3(0.0);
  prd.instance_hit = OBJECT_INFO(MAX_INSTANCES, MAX_PRIMITIVES);

  daxa_u32 ray_flags = gl_RayFlagsNoneEXT;
  daxa_f32 t_min = 0.0;
  daxa_f32 t_max = MAX_DISTANCE;
  daxa_u32 cull_mask = 0xFF;

  daxa_u32 screen_pos = index.y * rt_size.x + index.x;

  daxa_b32 is_hit = false;
  daxa_f32mat4x4 obj2world;
  daxa_f32mat4x4 world2obj;

#if SER == 1
  daxa_f32 distance = -1.0;

  hitObjectNV hit_object;
  // Initialize to an empty hit object
  hitObjectRecordEmptyNV(hit_object);

  // Trace the ray
  hitObjectTraceRayNV(
      hit_object,
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

  if (hitObjectIsHitNV(hit_object)) {

    daxa_u32 instance_id = hitObjectGetInstanceCustomIndexNV(hit_object);

    daxa_u32 primitive_id = hitObjectGetPrimitiveIndexNV(hit_object);

    prd.instance_hit = OBJECT_INFO(instance_id, primitive_id);

    // TODO: pass this as a parameter
    daxa_f32vec3 half_extent = daxa_f32vec3(HALF_VOXEL_EXTENT);

    daxa_f32 distance = -1.0;

    mat4x3 obj2world4x3 = hitObjectGetObjectToWorldNV(hit_object);

    obj2world = mat4(obj2world4x3[0], 0, obj2world4x3[1], 0, obj2world4x3[2], 0, obj2world4x3[3], 1.0);

    world2obj = inverse(obj2world);

    prd.distance =
        is_hit_from_ray_providing_model_get_pos_and_nor(
            ray, prd.instance_hit, half_extent, distance, prd.world_hit,
            prd.world_nrm, obj2world, world2obj, true, true)
            ? distance
            : -1.0;
    prd.distance = length(prd.world_hit - ray.origin);

    prd.mat_index =
        get_material_index_from_instance_and_primitive_id(prd.instance_hit);
  } else {
    prd.hit_value *= env_map_sampler_eval(ray.direction.xyz);
  }

#else
  traceRayEXT(daxa_accelerationStructureEXT(p.tlas),
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

  DIRECT_ILLUMINATION_INFO di_info = DIRECT_ILLUMINATION_INFO(
      prd.world_hit, prd.distance, prd.world_nrm, ray.origin, prd.seed,
      prd.instance_hit, prd.mat_index, 1.0);

  is_hit = di_info.distance > 0.0;

  // #if SER == 1
  //     reorderThreadNV(daxa_u32(is_hit), 1);
  // #endif // SER

  if (is_hit == false) {
    imageStore(daxa_image2D(p.swapchain), index,
               daxa_f32vec4(prd.hit_value, 1.0));
#if INDIRECT_ILLUMINATION_ON == 1
    set_indirect_color_by_index(screen_pos, daxa_f32vec3(0.f));
#endif // INDIRECT_ILLUMINATION_ON

#if RESTIR_ON == 1
    if ((active_features & TAA_BIT) == TAA_BIT) {
      // Store the DI info
      imageStore(daxa_image2D(p.taa_frame), index,
                 daxa_f32vec4(prd.hit_value, 1.0));
    }
#endif // RESTIR_ON

  } else {
#if SER != 1
    obj2world = get_geometry_transform_from_instance_id(
        di_info.instance_hit.instance_id);
#endif // SER

    // X from current pixel position
    daxa_f32vec2 Xi = daxa_f32vec2(index.xy)  + 0.5f;

    // Previous frame screen coord
    daxa_f32vec2 motion_vector =
        get_motion_vector(Xi, di_info.position, rt_size.xy,
                          di_info.instance_hit.instance_id, obj2world);

    VELOCITY velocity = VELOCITY(motion_vector);
    velocity_buffer_set_velocity(index, rt_size, velocity);

    // Get light configuration
    LIGHT_CONFIG light_config = get_light_config_from_light_index();

    // OBJECTS
    daxa_u32 object_count = deref(p.status_buffer).obj_count;

    // Get material
    MATERIAL mat = get_material_from_material_index(di_info.mat_index);

    daxa_f32vec2 Xi_1 = Xi + velocity.velocity;

    daxa_u32vec2 predicted_coord = daxa_u32vec2(Xi_1);

    HIT_INFO_INPUT hit = HIT_INFO_INPUT(
        di_info.position, di_info.normal, di_info.distance, daxa_f32vec3(0.0),
        di_info.instance_hit, di_info.mat_index);

    hit.world_hit = compute_ray_origin(hit.world_hit, hit.world_nrm);
    hit.world_hit = compute_ray_origin(hit.world_hit, hit.world_nrm);

    daxa_f32 confidence = 1.0;

#if RESTIR_ON == 1 && RESTIR_DI_ON == 1
#if (RESTIR_DI_TEMPORAL_ON == 1)
    // Reservoir from previous frame
    RESERVOIR reservoir_previous =
        GATHER_TEMPORAL_RESERVOIR(predicted_coord, rt_size, hit);

    // TODO: re-check this
    // Confidence when using temporal reuse and M is the number of samples in
    // the reservoir predicted should be 0.01 (1%) if M == 0 then 1.0 (100%).
    // Interpolated between those values daxa_f32 predicted =
    // clamp((reservoir_previous.M) / (MAX_INFLUENCE_FROM_THE_PAST_THRESHOLD *
    // daxa_f32(MAX_RIS_POINT_SAMPLE_COUNT)), 0.0, 1.0);
    daxa_f32 predicted =
        clamp((reservoir_previous.M) / (MAX_INFLUENCE_FROM_THE_PAST_THRESHOLD),
              0.0, 1.0);

    confidence = (reservoir_previous.W_y > 0.0) ? predicted : 0.0;

#endif // RESTIR_DI_TEMPORAL_ON

    di_info.confidence = confidence;

    {
      daxa_f32vec3 radiance = vec3(0.0);

      daxa_f32 p_hat = 0.0;

      INTERSECT i;

      RESERVOIR reservoir =
          FIRST_GATHER(active_features, light_config, object_count, screen_pos, confidence, ray,
                       hit, mat, p_hat, di_info.seed, i);

#if (RESTIR_DI_TEMPORAL_ON == 1)
      if (reservoir_previous.W_y > 0.0) {
        daxa_b32 is_remapping_active = ((active_features & REMAP_BIT) == REMAP_BIT);
        TEMPORAL_REUSE(reservoir, reservoir_previous, predicted_coord, rt_size,
                       ray, hit, mat, light_config.point_light_count, di_info.seed, is_remapping_active);
      }

#endif // RESTIR_DI_TEMPORAL_ON

      set_reservoir_from_intermediate_frame_by_index(screen_pos, reservoir);
    }
#endif // RESTIR_DI_ON

#if INDIRECT_ILLUMINATION_ON == 1
    daxa_f32vec3 final_indirect_color = daxa_f32vec3(0.f);

    daxa_f32vec3 indirect_color = daxa_f32vec3(0.0);
    // Build the intersect struct
    daxa_f32vec3 wo = normalize(ray.origin - di_info.position);
    INTERSECT i = INTERSECT(is_hit, di_info.distance, di_info.position,
                            di_info.normal, wo, daxa_f32vec3(0.f),
                            di_info.instance_hit, di_info.mat_index, mat);
    SCENE_PARAMS params = SCENE_PARAMS(
        light_count, object_count, max_depth, TEMPORAL_UPDATE_FOR_DYNAMIC_SCENE,
        SHIFT_MAPPING_RECONNECTION,
        0, // TODO: pack every flag here
        NEAR_FIELD_REJECTION, NEAR_FIELD_DISTANCE, ROUGHNESS_BASED_REJECTION,
        SPECULAR_ROUGHNESS_THRESHOLD, REJECT_BASED_ON_JACOBIAN,
        JACOBIAN_REJECTION_THRESHOLD, USE_RUSSIAN_ROULETTE,
        COMPUTE_ENVIRONMENT_LIGHT, NEIGHBOR_COUNT, NEIGHBOR_RADIUS);

    indirect_illumination(params, index, rt_size, ray, mat, i, di_info.seed,
                          indirect_color);

    // Replace NaN components with zero.
    if (any(isinf(indirect_color)) || any(isnan(indirect_color)))
      indirect_color = vec3(0.0);
#if (ACCUMULATOR_ON == 1 && RESTIR_ON == 0 && RESTIR_PT_ON == 0 ||             \
     FORCE_ACCUMULATOR_ON == 1)
    daxa_u64 num_accumulated_frames =
        deref(p.status_buffer).num_accumulated_frames;
    if (num_accumulated_frames > 0) {
      vec3 previous_frame_pixel = get_indirect_color_by_index(screen_pos);

      vec3 current_frame_pixel = indirect_color;

      daxa_f32 weight =
          daxa_f32(1.0f / (double(num_accumulated_frames) + 1.0f));
      final_indirect_color =
          mix(previous_frame_pixel, current_frame_pixel, weight);
    } else {
      final_indirect_color = indirect_color;
    }
#else
    final_indirect_color = indirect_color;
#endif // ACCUMULATOR_ON || FORCE_ACCUMULATOR_ON
    set_indirect_color_by_index(screen_pos, final_indirect_color);
#endif // INDIRECT_ILLUMINATION_ON
  }

  // Store the DI info
  set_di_from_current_frame(screen_pos, di_info);
}

#elif SPATIAL_REUSE_PASS == 1
void main() {
  
}

#elif THIRD_VISIBILITY_TEST_AND_SHADING_PASS == 1

void main() {
  const daxa_i32vec2 index = ivec2(gl_LaunchIDEXT.xy);
  const daxa_u32vec2 rt_size = gl_LaunchSizeEXT.xy;

  // TODO: check if we can reduce this to 1 or 2
  daxa_u32 max_depth = deref(p.status_buffer).max_depth;

  // screen_pos is the index of the pixel in the screen
  daxa_u32 screen_pos = index.y * rt_size.x + index.x;

  // Get feature flags
  daxa_u32 active_features = deref(p.status_buffer).is_active;

  // Get hit info
  DIRECT_ILLUMINATION_INFO di_info = get_di_from_current_frame(screen_pos);

  daxa_b32 is_hit = di_info.distance > 0.0;
  // #if SER == 1
  //     reorderThreadNV(daxa_u32(hit_value), 1);
  // #endif // SER
  if (is_hit) {
    daxa_f32vec3 hit_value = vec3(0.0);
    prd.hit_value = vec3(1.0);

    Ray ray = Ray(di_info.ray_origin,
                  normalize(di_info.position - di_info.ray_origin));

#if (DEBUG_NORMALS_ON == 1)
    hit_value = di_info.normal * 0.5 + 0.5;
#else
    // Get material
    MATERIAL mat = get_material_from_material_index(di_info.mat_index);

    // Get light configuration
    LIGHT_CONFIG light_config = get_light_config_from_light_index();

    // Get light count
    daxa_u32 light_count = light_config.point_light_count;
    // OBJECTS
    daxa_u32 object_count = deref(p.status_buffer).obj_count;

    HIT_INFO_INPUT hit = HIT_INFO_INPUT(
        di_info.position, di_info.normal, di_info.distance, daxa_f32vec3(0.f),
        di_info.instance_hit, di_info.mat_index);

    hit.world_hit = compute_ray_origin(hit.world_hit, hit.world_nrm);
    hit.world_hit = compute_ray_origin(hit.world_hit, hit.world_nrm);

    daxa_f32 p_hat = 0.0;

    daxa_f32vec3 radiance = vec3(0.0);

    daxa_f32 pdf = 1.0 / daxa_f32(light_count);
    daxa_f32 pdf_out = 0.0;

#if RESTIR_ON == 1 && RESTIR_DI_ON == 1
  // Get sample info from reservoir
  RESERVOIR reservoir =
      get_reservoir_from_intermediate_frame_by_index(screen_pos);
    daxa_f32 confidence = di_info.confidence;

    RESERVOIR spatial_reservoir = reservoir;
#if (RESTIR_DI_SPATIAL_ON == 1)
    // TODO: artifacts when using spatial reuse
    // if(confidence < 0.2) {
    SPATIAL_REUSE(spatial_reservoir, confidence, index, rt_size, ray, hit,
                  di_info.mat_index, mat, light_count, pdf, di_info.seed,
                  MIN_NEIGHBORS_RADIUS, MAX_NEIGHBORS_RADIUS);
                  

//     SPATIAL_REUSE(spatial_reservoir, confidence, index, rt_size, ray, hit,
//                   di_info.mat_index, mat, light_count, pdf, di_info.seed,
//                         5.f, 2.f);
    // }
#endif // RESTIR_DI_SPATIAL_ON

#if DIRECT_ILLUMINATION_ON == 1
    // Add the radiance to the hit value (reservoir radiance)
    hit_value += spatial_reservoir.F * spatial_reservoir.W_y;
#endif // DIRECT_ILLUMINATION_ON
#else  // RESTIR_DI_ON
    daxa_u32 light_index =
        min(urnd_interval(di_info.seed, 0, light_count), light_count - 1);
    // Get light
    LIGHT light = get_point_light_from_light_index(light_index);

    daxa_f32 G;

    // Calculate radiance
    radiance = calculate_sampled_light(ray, hit, mat, light_count, light, pdf,
                                       pdf_out, G, di_info.seed, false, true, true, true);

#if DIRECT_ILLUMINATION_ON == 1
    // Add the radiance to the hit value
    hit_value += radiance;
#endif // DIRECT_ILLUMINATION_ON
#endif // RESTIR_DI_ON

#if INDIRECT_ILLUMINATION_ON == 1
    daxa_f32vec3 indirect_color = daxa_f32vec3(0.f);
#if RESTIR_ON == 1 && RESTIR_PT_ON == 1 && RESTIR_PT_SPATIAL_ON == 1
    // Build the intersect struct
    daxa_f32vec3 wo = normalize(ray.origin - di_info.position);
    INTERSECT i = INTERSECT(is_hit, di_info.distance, di_info.position,
                            di_info.normal, wo, daxa_f32vec3(0.f),
                            di_info.instance_hit, di_info.mat_index, mat);
    SCENE_PARAMS params = SCENE_PARAMS(
        light_count, object_count, max_depth, TEMPORAL_UPDATE_FOR_DYNAMIC_SCENE,
        SHIFT_MAPPING_RECONNECTION,
        0, // TODO: pack every flag here
        NEAR_FIELD_REJECTION, NEAR_FIELD_DISTANCE, ROUGHNESS_BASED_REJECTION,
        SPECULAR_ROUGHNESS_THRESHOLD, REJECT_BASED_ON_JACOBIAN,
        JACOBIAN_REJECTION_THRESHOLD, USE_RUSSIAN_ROULETTE,
        COMPUTE_ENVIRONMENT_LIGHT, NEIGHBOR_COUNT, NEIGHBOR_RADIUS);
        
    daxa_f32mat4x4 inv_view = deref(p.camera_buffer).inv_view;
    daxa_f32vec3 camera_pos = daxa_f32vec3(inv_view[3]);
    indirect_illumination_spatial_reuse(params, index, rt_size, i, camera_pos,
                                        di_info.seed, indirect_color);
#else
    indirect_color = get_indirect_color_by_index(screen_pos);
#endif // RESTIR_PT_ON && RESTIR_PT_SPATIAL_ON
    hit_value += indirect_color;
#endif // INDIRECT_ILLUMINATION_ON

#if DIRECT_EMITTANCE_ON == 1
    hit_value += mat.emission;
#endif // DIRECT_EMITTANCE_ON

#endif // DEBUG_NORMALS_ON

    // Replace NaN components with zero.
    if (isinf(hit_value.x) || isnan(hit_value.x))
      hit_value.x = 0.0;
    if (isinf(hit_value.y) || isnan(hit_value.y))
      hit_value.y = 0.0;
    if (isinf(hit_value.z) || isnan(hit_value.z))
      hit_value.z = 0.0;

    clamp(hit_value, 0.0, 0.99999999);

    daxa_f32vec4 final_pixel;
#if (ACCUMULATOR_ON == 1 && RESTIR_ON == 0 || FORCE_ACCUMULATOR_ON == 1)
    daxa_u64 num_accumulated_frames =
        deref(p.status_buffer).num_accumulated_frames;
    if (num_accumulated_frames > 0) {
      vec4 previous_frame_pixel = imageLoad(daxa_image2D(p.swapchain), index);

      vec4 current_frame_pixel = vec4(hit_value, 1.0f);

      daxa_f32 weight =
          daxa_f32(1.0f / (double(num_accumulated_frames) + 1.0f));
      final_pixel = mix(previous_frame_pixel, current_frame_pixel, weight);
    } else {
      final_pixel = vec4(hit_value, 1.0f);
    }
#else
    final_pixel = vec4(hit_value, 1.0f);
#endif
    imageStore(daxa_image2D(p.swapchain), index, final_pixel);

#if RESTIR_ON == 1
    if ((active_features & TAA_BIT) != 0U) {
      // Store the DI info
      imageStore(daxa_image2D(p.taa_frame), index, final_pixel);
    } else {
      imageStore(daxa_image2D(p.swapchain), index, final_pixel);
    }
#else 
    imageStore(daxa_image2D(p.swapchain), index, final_pixel);
#endif // RESTIR_ON

#if RESTIR_ON == 1 && RESTIR_DI_ON == 1
    // Store the reservoir
    set_reservoir_from_previous_frame_by_index(screen_pos, spatial_reservoir);
#endif // RESTIR_DI_ON

    set_di_from_previous_frame(screen_pos, di_info);

    // // TODO: separate this into a different pass
    // const daxa_u32 window_size = 500;

    // if ((active_features & PERFECT_PIXEL_BIT) != 0U) {
    //   daxa_u32vec2 pixel = deref(p.status_buffer).pixel;

    //   daxa_u32 pixel_screen_pos = pixel.y * rt_size.x + pixel.x;
      
    //   DIRECT_ILLUMINATION_INFO di_info_pixel = get_di_from_current_frame(pixel_screen_pos);
      
    //   daxa_u32 instance_id = di_info.instance_hit.instance_id;

    //   daxa_u32 instance_pixel_id = di_info_pixel.instance_hit.instance_id;

    //   // Only affects same instance id as the pixel
    //   if(instance_id == instance_pixel_id) {
    //     // TODO: this is a test for many voxels brush range between exact pixel and -x and x and -y and y
    //     if (index.x >= pixel.x - window_size && index.x <= pixel.x +    window_size &&
    //         index.y >= pixel.y - window_size && index.y <= pixel.y + window_size)
    //     {
    //       delete_primitive_from_instance(di_info.instance_hit);
    //     }
    //   }
    // }
  }
}

#else

void main() {}

#endif // RESTIR_PREPASS