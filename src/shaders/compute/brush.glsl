#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#extension GL_EXT_ray_query : enable
#include <daxa/daxa.inl>
#include "defines.glsl"

DAXA_DECL_PUSH_CONSTANT(changes_push_constant, p)

#define ALPHA 0.8

layout(local_size_x = 8, local_size_y = 8) in;
void main() {
  const daxa_i32vec2 index = ivec2(gl_GlobalInvocationID.xy);
  if (index.x >= p.size.x || index.y >= p.size.y) {
    return;
  }
  daxa_u32vec2 launch_size = gl_NumWorkGroups.xy * 8;

  daxa_u32 screen_index = index.x + index.y * p.size.x;

  
}