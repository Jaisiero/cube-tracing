#pragma once
#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>
#include "defines.glsl"

#include "shared.inl"
#include "prng.glsl"
#include "light.glsl"
#include "primitives.glsl"
#include "motion_vectors.glsl"

#if SER == 1
#extension GL_NV_shader_invocation_reorder : enable
#endif 


RESERVOIR get_reservoir_from_previous_frame_by_index(daxa_u32 reservoir_index) {
    PREV_RESERVOIR_BUFFER prev_reservoir_buffer = PREV_RESERVOIR_BUFFER(deref(p.restir_buffer).previous_reservoir_address);
    return prev_reservoir_buffer.reservoirs[reservoir_index];
}

void set_reservoir_from_previous_frame_by_index(daxa_u32 reservoir_index, RESERVOIR reservoir) {
    PREV_RESERVOIR_BUFFER prev_reservoir_buffer = PREV_RESERVOIR_BUFFER(deref(p.restir_buffer).previous_reservoir_address);
    prev_reservoir_buffer.reservoirs[reservoir_index] = reservoir;
}

RESERVOIR get_reservoir_from_intermediate_frame_by_index(daxa_u32 reservoir_index) {
    INT_RESERVOIR_BUFFER int_reservoir_buffer = INT_RESERVOIR_BUFFER(deref(p.restir_buffer).intermediate_reservoir_address);
    return int_reservoir_buffer.reservoirs[reservoir_index];
}

void set_reservoir_from_intermediate_frame_by_index(daxa_u32 reservoir_index, RESERVOIR reservoir) {
    INT_RESERVOIR_BUFFER int_reservoir_buffer = INT_RESERVOIR_BUFFER(deref(p.restir_buffer).intermediate_reservoir_address);
    int_reservoir_buffer.reservoirs[reservoir_index] = reservoir;
}

RESERVOIR get_reservoir_from_current_frame_by_index(daxa_u32 reservoir_index) {
    RESERVOIR_BUFFER reservoir_buffer = RESERVOIR_BUFFER(deref(p.restir_buffer).reservoir_address);
    return reservoir_buffer.reservoirs[reservoir_index];
}

void set_reservoir_from_current_frame_by_index(daxa_u32 reservoir_index, RESERVOIR reservoir) {
    RESERVOIR_BUFFER reservoir_buffer = RESERVOIR_BUFFER(deref(p.restir_buffer).reservoir_address);
    reservoir_buffer.reservoirs[reservoir_index] = reservoir;
}

DIRECT_ILLUMINATION_INFO get_di_from_previous_frame(daxa_u32 di_index) {
    PREV_DI_BUFFER prev_di_buffer = PREV_DI_BUFFER(deref(p.restir_buffer).previous_di_address);
    return prev_di_buffer.di_info[di_index];
}

void set_di_from_previous_frame(daxa_u32 di_index, DIRECT_ILLUMINATION_INFO di_info) {
    PREV_DI_BUFFER prev_di_buffer = PREV_DI_BUFFER(deref(p.restir_buffer).previous_di_address);
    prev_di_buffer.di_info[di_index] = di_info;
}

DIRECT_ILLUMINATION_INFO get_di_from_current_frame(daxa_u32 di_index) {
    DI_BUFFER di_buffer = DI_BUFFER(deref(p.restir_buffer).di_address);
    return di_buffer.di_info[di_index];
}

void set_di_from_current_frame(daxa_u32 di_index, DIRECT_ILLUMINATION_INFO di_info) {
    DI_BUFFER di_buffer = DI_BUFFER(deref(p.restir_buffer).di_address);
    di_buffer.di_info[di_index] = di_info;
}

void set_di_seed_from_current_frame(daxa_u32 di_index, daxa_u32 seed) {
    DI_BUFFER di_buffer = DI_BUFFER(deref(p.restir_buffer).di_address);
    di_buffer.di_info[di_index].seed = seed;
}


void initialise_reservoir(inout RESERVOIR reservoir)
{
  reservoir.W_y = 0.0;
  reservoir.W_sum = 0.0;
  reservoir.M = 0.0;
  reservoir.Y = 0;
  reservoir.p_hat = 0.0;
}

daxa_b32 update_reservoir(inout RESERVOIR reservoir, daxa_u32 X, daxa_f32 w, daxa_f32 c, inout daxa_u32 seed)
{
  reservoir.W_sum += w;
  reservoir.M += c;

  if (rnd(seed) < (w / reservoir.W_sum))
  {
    reservoir.Y = X;
    return true;
  }

  return false;
}

daxa_u32 get_reservoir_light_index(in RESERVOIR reservoir)
{
  return reservoir.Y;
}

daxa_b32 is_reservoir_valid(in RESERVOIR reservoir)
{
  return reservoir.M > 0.0;
}

daxa_f32vec3 calculate_radiance(Ray ray, inout HIT_INFO_INPUT hit, MATERIAL mat, daxa_u32 light_count, LIGHT light, daxa_f32 pdf, out daxa_f32 pdf_out, const in daxa_b32 calc_pdf, const in daxa_b32 use_pdf, const in daxa_b32 use_visibility)
{
  return calculate_sampled_light(ray, hit, light, mat, light_count, pdf, pdf_out, calc_pdf, use_pdf, use_visibility);
}

daxa_f32 calculate_phat(Ray ray, inout HIT_INFO_INPUT hit, MATERIAL mat, daxa_u32 light_count, LIGHT light, daxa_f32 pdf, out daxa_f32 pdf_out, const in daxa_b32 calc_pdf, const in daxa_b32 use_pdf, const in daxa_b32 use_visibility)
{
  return length(calculate_sampled_light(ray, hit, light, mat, light_count, pdf, pdf_out, calc_pdf, use_pdf, use_visibility));
}

// Use the reservoir to calculate the final radiance.
void calculate_reservoir_radiance(inout RESERVOIR reservoir, Ray ray, inout HIT_INFO_INPUT hit, MATERIAL mat, daxa_u32 light_count, inout daxa_f32 p_hat, out daxa_f32vec3 radiance)
{

  if (is_reservoir_valid(reservoir))
  {
    LIGHT light = get_light_from_light_index(get_reservoir_light_index(reservoir));

    daxa_f32 pdf = 1.0;
    daxa_f32 pdf_out = 1.0;
    // calculate the radiance of this light
    radiance = calculate_radiance(ray, hit, mat, light_count, light, pdf, pdf_out, false, false, true);

    // calculate the weight of this light
    p_hat = length(radiance);

    // calculate the weight of this light
    reservoir.W_y = p_hat > 0.0 ? (reservoir.W_sum / reservoir.M) / p_hat : 0.0;

    // keep track of p_hat
    reservoir.p_hat = p_hat;
  }
}


void calculate_reservoir_mis_radiance(inout RESERVOIR reservoir, Ray ray, inout HIT_INFO_INPUT hit, MATERIAL mat, daxa_u32 light_count, daxa_u32 obj_count, inout daxa_f32 p_hat, out INTERSECT i, out daxa_f32vec3 radiance)
{

  if (is_reservoir_valid(reservoir))
  {
    LIGHT light = get_light_from_light_index(get_reservoir_light_index(reservoir));

    daxa_f32 pdf_out = 1.0;
    
    // calculate the radiance of this light
    radiance = direct_mis(ray, hit, light_count, light, obj_count, mat, i, pdf_out, false, true);

    // calculate the weight of this light
    p_hat = length(radiance);

    // calculate the weight of this light
    reservoir.W_y = p_hat > 0.0 ? (reservoir.W_sum / reservoir.M) / p_hat : 0.0;

    // keep track of p_hat
    reservoir.p_hat = p_hat;
  }
}

void calculate_reservoir_weight(inout RESERVOIR reservoir, Ray ray, inout HIT_INFO_INPUT hit, MATERIAL mat, daxa_u32 light_count) 
{

  if (is_reservoir_valid(reservoir))
  {
    daxa_f32 pdf = 1.0;
    daxa_f32 pdf_out = 1.0;

    // calculate weight of the selected lights
    reservoir.W_y = reservoir.p_hat > 0.0 ? (reservoir.W_sum / reservoir.M) / reservoir.p_hat : 0.0;
  }
}

void calculate_reservoir_p_hat_and_weight(inout RESERVOIR reservoir, Ray ray, inout HIT_INFO_INPUT hit, MATERIAL mat, daxa_u32 light_count, inout daxa_f32 p_hat) 
{

  if (is_reservoir_valid(reservoir))
  {
    LIGHT light = get_light_from_light_index(get_reservoir_light_index(reservoir));

    daxa_f32 pdf = 1.0;
    daxa_f32 pdf_out = 1.0;
    // get weight of this reservoir
    p_hat = calculate_phat(ray, hit, mat, light_count, light, pdf, pdf_out, false, false, false);

    // calculate weight of the selected lights
    reservoir.W_y = p_hat > 0.0 ? (reservoir.W_sum / reservoir.M) / p_hat : 0.0;

    // keep track of p_hat
    reservoir.p_hat = p_hat;
  }
}

void calculate_reservoir_aggregation(inout RESERVOIR reservoir, RESERVOIR aggregation_reservoir, Ray ray, inout HIT_INFO_INPUT hit, MATERIAL mat, daxa_u32 light_count) 
{

  if (is_reservoir_valid(aggregation_reservoir))
  {
    daxa_f32 pdf = 1.0;
    daxa_f32 pdf_out = 1.0;

    // add sample from previous frame
    update_reservoir(reservoir, get_reservoir_light_index(aggregation_reservoir), aggregation_reservoir.p_hat * aggregation_reservoir.W_y * aggregation_reservoir.M, aggregation_reservoir.M, prd.seed);
  }
}

RESERVOIR RIS(daxa_u32 light_count, daxa_f32 confidence, Ray ray, inout HIT_INFO_INPUT hit, MATERIAL mat, daxa_f32 pdf, inout daxa_f32 p_hat)
{
  RESERVOIR reservoir;
  initialise_reservoir(reservoir);

  confidence = clamp(confidence, 0.0, 1.0);

  daxa_u32 NUM_OF_SAMPLES = max(daxa_u32(min(MAX_RIS_SAMPLE_COUNT * confidence, light_count)), 1);

  for (daxa_u32 l = 0; l < NUM_OF_SAMPLES; l++)
  {
    daxa_u32 light_index = min(urnd_interval(hit.seed, 0, light_count), light_count - 1);

    LIGHT light = get_light_from_light_index(light_index);

    daxa_f32 current_pdf = 1.0;
    p_hat = calculate_phat(ray, hit, mat, light_count, light, pdf, current_pdf, true, false, false);
    daxa_f32 w = p_hat / current_pdf;
    update_reservoir(reservoir, light_index, w, 1.0f, hit.seed);
  }

  calculate_reservoir_p_hat_and_weight(reservoir, ray, hit, mat, light_count, p_hat);

  return reservoir;
}




RESERVOIR FIRST_GATHER(daxa_u32 light_count, daxa_u32 screen_pos, daxa_f32 confidence_index, Ray ray, inout HIT_INFO_INPUT hit, MATERIAL mat, inout daxa_f32 p_hat)
{
  // PDF for lights
  daxa_f32 pdf = 1.0 / light_count;

  RESERVOIR reservoir = RIS(light_count, confidence_index, ray, hit, mat, pdf, p_hat);

  // // Store the reservoir
  // set_reservoir_from_current_frame_by_index(screen_pos, reservoir);

#if INDIRECT_ILLUMINATION_ON == 1
// TODO: MIS is very expensive and it is not working properly with reservoirs
// #if MIS_ON == 1
//     prd.world_hit = world_pos;
//     prd.world_nrm = world_nrm;
// #else 
    call_scatter.hit = world_pos;
    call_scatter.nrm = world_nrm;
    call_scatter.ray_dir = ray.direction;
    call_scatter.seed = hit.seed;
    call_scatter.scatter_dir = vec3(0.0);
    call_scatter.done = false;
    call_scatter.mat_idx = mat_index;
    call_scatter.instance_hit = instance_hit;

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
    prd.world_nrm = world_nrm;
    prd.ray_scatter_dir = call_scatter.scatter_dir;
// #endif // MIS_ON

#else 
    // prd.world_hit = world_pos;
    // prd.world_nrm = world_nrm;
#endif // INDIRECT_ILLUMINATION_ON


  return reservoir;
}


RESERVOIR GATHER_TEMPORAL_RESERVOIR(daxa_u32vec2 predicted_coord, daxa_u32vec2 rt_size, HIT_INFO_INPUT hit)
{
  RESERVOIR reservoir_previous;
  initialise_reservoir(reservoir_previous);

  daxa_u32 prev_predicted_index = predicted_coord.x + predicted_coord.y * rt_size.x;

  // Max screen pos
  daxa_u32 max_screen_pos = rt_size.x * rt_size.y - 1;

  // Clamp screen pos for
  prev_predicted_index = min(max_screen_pos, prev_predicted_index);

  // Temporal reuse
  {
    DIRECT_ILLUMINATION_INFO di_info_previous = get_di_from_previous_frame(prev_predicted_index);

    // Normal from previous frame
    daxa_f32vec3 normal_previous = di_info_previous.normal.xyz;

    // Depth from previous frame
    daxa_f32 depth_previous = di_info_previous.distance;

    // some simple rejection based on normals' divergence, can be improved
    bool valid_history = dot(normal_previous, hit.world_nrm) >= 0.99 && 
      di_info_previous.instance_hit.instance_id == hit.instance_hit.instance_id && 
      di_info_previous.instance_hit.primitive_id == hit.instance_hit.primitive_id;

    if (valid_history)
    {
      // Reservoir from previous frame
      reservoir_previous = get_reservoir_from_previous_frame_by_index(prev_predicted_index);
    }
  }

  return reservoir_previous;
}




void TEMPORAL_REUSE(inout RESERVOIR reservoir, RESERVOIR reservoir_previous, daxa_u32vec2 predicted_coord, daxa_u32vec2 rt_size, Ray ray, inout HIT_INFO_INPUT hit, MATERIAL mat, daxa_u32 light_count)
{

  RESERVOIR temporal_reservoir;
  initialise_reservoir(temporal_reservoir);

  // add current reservoir sample
  update_reservoir(temporal_reservoir, get_reservoir_light_index(reservoir), reservoir.p_hat * reservoir.W_y * reservoir.M, reservoir.M, prd.seed);

  // // TODO: re-check this
  // daxa_f32 influence = max(1.0, mix(clamp(reservoir_previous.M / reservoir.M, 0.0, 1.0), MIN_INFLUENCE_FROM_THE_PAST_THRESHOLD, MAX_INFLUENCE_FROM_THE_PAST_THRESHOLD));

  // NOTE: restrict influence from past samples.
  reservoir_previous.M = min(MAX_INFLUENCE_FROM_THE_PAST_THRESHOLD * reservoir.M, reservoir_previous.M);

  // add sample from previous frame
  calculate_reservoir_aggregation(temporal_reservoir, reservoir_previous, ray, hit, mat, light_count);

  // calculate the weight of this light
  calculate_reservoir_weight(temporal_reservoir, ray, hit, mat, light_count);
  
  reservoir = temporal_reservoir;
}

void SPATIAL_REUSE(inout RESERVOIR reservoir, daxa_u32vec2 predicted_coord, daxa_u32vec2 rt_size, Ray ray, inout HIT_INFO_INPUT hit, daxa_u32 current_mat_index, MATERIAL mat, daxa_u32 light_count, daxa_f32 pdf)
{
  RESERVOIR spatial_reservoir;
  initialise_reservoir(spatial_reservoir);

  daxa_f32 pdf_out = 1.0;

  // Calculate p_hat
  daxa_f32 p_hat = 0.0;

  // add previous samples
  calculate_reservoir_aggregation(spatial_reservoir, reservoir, ray, hit, mat, light_count);

  RESERVOIR neighbor_reservoir;

  // daxa_f32 spatial_influence_threshold = max(1.0, (INFLUENCE_FROM_THE_PAST_THRESHOLD) / NUM_OF_NEIGHBORS);

  for (daxa_u32 i = 0; i < NUM_OF_NEIGHBORS; i++)
  {
    // Random offset
    daxa_f32vec2 offset = 2.0 * daxa_f32vec2(rnd(prd.seed), rnd(prd.seed)) - 1;

    // Scale offset
    offset.x = predicted_coord.x + int(offset.x * NEIGHBORS_RADIUS);
    offset.y = predicted_coord.y + int(offset.y * NEIGHBORS_RADIUS);

    // Clamp offset
    offset.x = min(rt_size.x - 1, max(0, min(rt_size.x - 1, offset.x)));
    offset.y = min(rt_size.y - 1, max(0, min(rt_size.y - 1, offset.y)));

    // Convert offset to u32
    daxa_u32vec2 offset_u32 = daxa_u32vec2(offset);

    // Convert offset to linear
    daxa_u32 offset_u32_linear = offset_u32.y * rt_size.x + offset_u32.x;

    // TODO: Should depth buffer be used?
    // daxa_f32 neighbor_depth_linear = linearise_depth(deref(p.depth_buffer).depth[daxa_f32vec2(offset)].x);

    DIRECT_ILLUMINATION_INFO neighbor_di_info = get_di_from_current_frame(offset_u32_linear);

    daxa_f32 neighbor_hit_dist = neighbor_di_info.distance;

    daxa_u32 current_primitive_index = get_current_primitive_index_from_instance_and_primitive_id(neighbor_di_info.instance_hit);

    daxa_u32 neighbor_mat_index = get_material_index_from_primitive_index(current_primitive_index);

    // TODO: Adjust dist threshold dynamically
    if (
        // (neighbor_depth_linear > 1.1f * depth_linear || neighbor_depth_linear < 0.9f * depth_linear)   ||
        // abs(neighbor_hit_dist - gl_HitTEXT) > VOXEL_EXTENT ||
        neighbor_mat_index != current_mat_index ||
        dot(hit.world_nrm, neighbor_di_info.normal.xyz) < 0.906)
    {
      // skip this neighbour sample if not suitable
      continue;
    }

    neighbor_reservoir = get_reservoir_from_intermediate_frame_by_index(offset_u32_linear);

    calculate_reservoir_aggregation(spatial_reservoir, neighbor_reservoir, ray, hit, mat, light_count);
  }

  calculate_reservoir_weight(spatial_reservoir, ray, hit, mat, light_count);

  reservoir = spatial_reservoir;
}