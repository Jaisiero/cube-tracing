#pragma once

#include "defines.slang"

[[vk::push_constant]] brush_push_constant p;

uint increment_brush_counter_instance_count(Ptr<BRUSH_COUNTER> brush_counter)
{
  uint old_instance_count;
  InterlockedAdd(brush_counter->instance_count, 1, old_instance_count);
  return old_instance_count;
}

uint increment_brush_counter_primitive_count(Ptr<BRUSH_COUNTER> brush_counter)
{
  uint old_primitive_count;
  InterlockedAdd(brush_counter->primitive_count, 1, old_primitive_count);
  return old_primitive_count;
}

uint get_geometry_first_primitive_index_from_instance_id(uint instance_id)
{
  // Get the first primitive index from the instance id
  return Ptr<INSTANCE>(p.head.world_buffer->instance_address)[instance_id].first_primitive_index;
}

uint get_current_primitive_index_from_instance_and_primitive_id(OBJECT_INFO instance_hit)
{
  // Get first primitive index from instance id
  uint primitive_index =
      get_geometry_first_primitive_index_from_instance_id(
          instance_hit.instance_id);
  // Get actual primitive index from offset and primitive id
  return primitive_index + instance_hit.primitive_id;
}

void delete_primitive_from_instance(OBJECT_INFO instance_hit)
{
  // Get the current instance bitmask
  Ptr<uint> instance_bitmask = Ptr<uint>(p.head.status_buffer->instance_bitmask_address);

  // Get the current primitive bitmask
  Ptr<uint> primitive_bitmask = Ptr<uint>(p.head.status_buffer->primitive_bitmask_address);

  // Access instance & primitive counters
  Ptr<BRUSH_COUNTER> brush_counter = Ptr<BRUSH_COUNTER>(p.head.status_buffer->brush_counter_address);

  uint primitive_index =
      get_current_primitive_index_from_instance_and_primitive_id(instance_hit);

  uint instance_index = instance_hit.instance_id;

  // atomic or operation to set the bit to 1
  uint result_instance = -1;
  InterlockedOr(instance_bitmask[instance_index >> 5],
                1 << (instance_index & 31), result_instance);

  // atomic or operation to set the bit to 1
  uint result_primitive = -1;
  InterlockedOr(primitive_bitmask[primitive_index >> 5],
                1 << (primitive_index & 31), result_primitive);

  if ((result_primitive & (1U << (primitive_index & 31))) == 0U)
  {
    increment_brush_counter_primitive_count(brush_counter);
  }

  if ((result_instance & (1U << (instance_index & 31))) == 0U)
  {
    increment_brush_counter_instance_count(brush_counter);
  }
}

[shader("compute")]
    [numthreads(BRUSH_COMPUTE_X, BRUSH_COMPUTE_Y, 1)] void
    entry_brush(uint3 pixel_i : SV_DispatchThreadID)
{
  Ptr<Status> status =
      Ptr<Status>(p.head.status_buffer);

  uint res_x = status->resolution.x;
  uint res_y = status->resolution.y;

  if (pixel_i.x >= res_x || pixel_i.y >= res_y)
  {
    return;
  }
  // Get feature flags
  uint active_features = status->is_active;

  Ptr<BRUSH_CONFIG> brush_config = Ptr<BRUSH_CONFIG>(status->brush_config_address);

  // TODO: separate this into a different pass
  const uint window_size = reinterpret<uint>(brush_config->brush_pixel_size.x);

  uint2 pixel = status->pixel;
  
  uint pixel_screen_pos = pixel.y * res_x + pixel.x;

  DIRECT_ILLUMINATION_INFO di_info_pixel =
      Ptr<DIRECT_ILLUMINATION_INFO>(p.head.restir_buffer->previous_di_address)[pixel_screen_pos];

  bool is_hit = di_info_pixel.distance > 0.0;
  if (is_hit)
  {

    uint2 window_min = max(uint2(pixel.x - window_size, pixel.y - window_size), uint2(0, 0));
    uint2 window_max = min(uint2(pixel.x + window_size, pixel.y + window_size), uint2(res_x ? res_x - 1 : 0, res_y ? res_y - 1 : 0));

    // TODO: this is a test for many voxels brush range between exact pixel and -x and x and -y and y
    if (pixel_i.x >= window_min.x && pixel_i.x <= window_max.x &&
        pixel_i.y >= window_min.y && pixel_i.y <= window_max.y)
    {
      // screen_pos is the index of the pixel in the screen
      uint screen_pos = pixel_i.y * res_x + pixel_i.x;
      // Get hit info
      DIRECT_ILLUMINATION_INFO di_info = Ptr<DIRECT_ILLUMINATION_INFO>(p.head.restir_buffer->previous_di_address)[screen_pos];

      is_hit = di_info.distance > 0.0;
      if (is_hit)
      {
        uint instance_id = di_info.instance_hit.instance_id;

        uint instance_pixel_id = di_info_pixel.instance_hit.instance_id;

        // Only affects same instance id as the pixel
        if (instance_id == instance_pixel_id)
        {
          delete_primitive_from_instance(di_info.instance_hit);
        }
      }
    }
  }
}