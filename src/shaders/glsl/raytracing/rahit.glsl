#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>
#include "defines.glsl"

DAXA_DECL_PUSH_CONSTANT(PushConstant, p)

#include "random.glsl"
#include "primitives.glsl"

void main()
{

  OBJECT_INFO instance_hit = OBJECT_INFO(gl_InstanceCustomIndexEXT, gl_PrimitiveID);
  // Get first primitive index from instance id
  daxa_u32 actual_primitive_index = get_current_primitive_index_from_instance_and_primitive_id(instance_hit);

  // Get material index from primitive
  MATERIAL mat = get_material_from_primitive_index(actual_primitive_index);

  if (mat.illum != 4)
    return;

  if (mat.dissolve == 0.0)
    ignoreIntersectionEXT;
  else if (rnd(prd.seed) > mat.dissolve)
    ignoreIntersectionEXT;
}
