#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#extension GL_EXT_ray_query : enable
#include <daxa/daxa.inl>
#include "defines.glsl"

DAXA_DECL_PUSH_CONSTANT(PushConstant, p)

#include "direct_light_info.glsl"
#include "motion_vectors.glsl"


#define ALPHA 0.8

layout(local_size_x = 8, local_size_y = 8) in;
void main() {
  const daxa_i32vec2 index = ivec2(gl_GlobalInvocationID.xy);
  if (index.x >= p.size.x || index.y >= p.size.y) {
    return;
  }
  daxa_u32vec2 launch_size = gl_NumWorkGroups.xy * 8;

  daxa_u32 screen_index = index.x + index.y * p.size.x;

  DIRECT_ILLUMINATION_INFO di_info = get_di_from_current_frame(screen_index);

  if (di_info.distance > 0.0) {
    // SPATIAL FILTERING
    daxa_f32vec4 blended_current_pixel = daxa_f32vec4(0.0);

    daxa_u32 neighbor_count = 0;

    for (int i = -1; i <= 1; i++) {
      for (int j = -1; j <= 1; j++) {
        daxa_i32vec2 neighbour_index = index + ivec2(i, j);
        if (neighbour_index.x < 0.0 || neighbour_index.x >= p.size.x ||
            neighbour_index.y < 0.0 || neighbour_index.y >= p.size.y) {
          continue;
        }

        // Get the neighbor screen index
        daxa_u32 neighbour_screen_index =
            neighbour_index.x + neighbour_index.y * p.size.x;

        // Get the neighbor direct illumination info
        DIRECT_ILLUMINATION_INFO neighbor_di_info =
            get_di_from_current_frame(neighbour_screen_index);

        // Rejecting pixels with different materials, normals and distances
        if (di_info.distance <= 0.f || di_info.mat_index != neighbor_di_info.mat_index ||
            (dot(di_info.normal, neighbor_di_info.normal) < 0.906) ||
            (abs(di_info.distance - neighbor_di_info.distance) > 0.1 * di_info.distance)) {
          continue;
        }

        ++neighbor_count;

        daxa_f32vec4 neighbour_pixel =
            imageLoad(daxa_image2D(p.taa_frame), neighbour_index);
        blended_current_pixel += neighbour_pixel;
      }
    }

    blended_current_pixel /= neighbor_count;

    // blended_current_pixel = imageLoad(daxa_image2D(p.taa_frame), index);

    // TEMPORAL FILTERING
    // Get the motion vector
    VELOCITY velocity = velocity_buffer_get_velocity(index, p.size);
    // X from current pixel position
    daxa_f32vec2 Xi = daxa_f32vec2(index.xy);
    // X from previous pixel position
    daxa_f32vec2 Xi_1 = Xi + (velocity.velocity) +
                        daxa_f32vec2(rnd(di_info.seed), rnd(di_info.seed));
    // X from previous pixel position as integer
    daxa_i32vec2 Xi_1_i = ivec2(Xi_1);

    if (Xi_1_i.x >= 0 && Xi_1_i.x < p.size.x && Xi_1_i.y >= 0 &&
        Xi_1_i.y < p.size.y) {

      // Get the previous pixel
      daxa_f32vec4 prev_pixel =
          imageLoad(daxa_image2D(p.previous_swapchain), Xi_1_i);
      // Get the previous screen index
      daxa_u32 prev_screen_index = Xi_1_i.x + Xi_1_i.y * p.size.x;
      // Get the previous direct illumination info
      DIRECT_ILLUMINATION_INFO prev_di_info =
          get_di_from_previous_frame(prev_screen_index);

      // some simple rejection based on normals' divergence, can be improved
      daxa_b32 valid_history =
          dot(prev_di_info.normal, di_info.normal) >= 0.99 &&
          // prev_di_info.instance_hit.instance_id ==
          // di_info.instance_hit.instance_id &&
          // prev_di_info.instance_hit.primitive_id ==
          // di_info.instance_hit.primitive_id;
          prev_di_info.mat_index == di_info.mat_index;

      if (valid_history) {
        blended_current_pixel =
            ALPHA * blended_current_pixel + (1 - ALPHA) * prev_pixel;
      }
    }

    // ci(xi) = α· ˜ ci(xi)+(1−α)· ¯ ci−1(xi−1), where α = 0.8
    imageStore(daxa_image2D(p.swapchain), index, blended_current_pixel);
  }
}