#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>
#include "defines.glsl"

DAXA_DECL_PUSH_CONSTANT(PushConstant, p)

#include "primitives.glsl"

void main() {
  Ray ray;
  ray.origin = gl_WorldRayOriginEXT;
  ray.direction = gl_WorldRayDirectionEXT;

  daxa_f32mat4x3 obj2world4x3 = gl_ObjectToWorldEXT;

  // Get model matrix
  daxa_f32mat4x4 obj2world =
      mat4(obj2world4x3[0], 0, obj2world4x3[1], 0, obj2world4x3[2], 0, obj2world4x3[3], 1.0);

  daxa_f32mat4x4 world2obj = inverse(obj2world);

  daxa_f32 t_hit = -1.0;

  daxa_f32vec3 pos;
  daxa_f32vec3 nor;

  OBJECT_INFO instance_hit =
      OBJECT_INFO(gl_InstanceCustomIndexEXT, gl_PrimitiveID);

  // TODO: pass this as a parameter
  daxa_f32vec3 half_extent = daxa_f32vec3(HALF_VOXEL_EXTENT);

  t_hit =
      is_hit_from_ray_providing_model(ray, instance_hit, half_extent, t_hit,
                                      obj2world, world2obj, true, true)
          ? t_hit
          : -1.0;

  // Report hit point
  if (t_hit > 0)
    reportIntersectionEXT(t_hit, 0); // 0 is the hit kind (hit group index)
}