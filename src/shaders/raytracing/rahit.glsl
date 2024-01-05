#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>

#include "shared.inl"
#include "random.glsl"

DAXA_DECL_PUSH_CONSTANT(PushConstant, p)

layout(location = 0) rayPayloadInEXT HIT_PAY_LOAD prd;

void main()
{
  // Get first primitive index from instance id
  uint primitive_index = deref(p.instance_buffer).instances[gl_InstanceCustomIndexEXT].first_primitive_index;
  // Get actual primitive index from offset and primitive id
  uint actual_primitive_index = primitive_index + gl_PrimitiveID;

  // Get material index from primitive
  PRIMITIVE primitive = deref(p.primitives_buffer).primitives[actual_primitive_index];
  MATERIAL mat = deref(p.materials_buffer).materials[primitive.material_index];

  if (mat.illum != 4)
    return;

  if (mat.dissolve == 0.0)
    ignoreIntersectionEXT;
  else if (rnd(prd.seed) > mat.dissolve)
    ignoreIntersectionEXT;
}
