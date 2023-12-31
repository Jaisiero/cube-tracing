#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>

#include "shared.inl"

DAXA_DECL_PUSH_CONSTANT(PushConstant, p)

layout(location = 0) rayPayloadInEXT HIT_PAY_LOAD prd;
layout(location = 1) rayPayloadEXT bool isShadowed;

// #define DEBUG_NORMALS

void main()
{
    vec3 world_pos = gl_WorldRayOriginEXT + gl_WorldRayDirectionEXT * gl_HitTEXT;

    mat4 model = mat4(
        gl_ObjectToWorldEXT[0][0], gl_ObjectToWorldEXT[0][1], gl_ObjectToWorldEXT[0][2], 0,
        gl_ObjectToWorldEXT[0][1], gl_ObjectToWorldEXT[1][1], gl_ObjectToWorldEXT[1][2], 0,
        gl_ObjectToWorldEXT[2][0], gl_ObjectToWorldEXT[2][1], gl_ObjectToWorldEXT[2][2], 0,
        gl_ObjectToWorldEXT[3][0], gl_ObjectToWorldEXT[3][1], gl_ObjectToWorldEXT[3][2], 1.0);

    // TODO: resuse aabb buffer
    {
        // uint prim_index = gl_PrimitiveID + gl_GeometryIndexEXT + gl_InstanceCustomIndexEXT;

        // Aabb aabb = deref(p.aabb_buffer).aabbs[prim_index];
        // Aabb aabb;
        // vec3 center = (aabb.minimum + aabb.maximum) * 0.5;
    }

    // TODO: current center starts
    // Get first primitive index from instance id
    uint primitive_index = deref(p.instance_buffer).instances[gl_InstanceCustomIndexEXT].first_primitive_index;
    // Get actual primitive index from offset and primitive id
    uint actual_primitive_index = primitive_index + gl_PrimitiveID;

    // Get center position from transform
    vec3 center = deref(p.primitives_buffer).primitives[actual_primitive_index].center;
    // TODO: current center ends

    center = (model * vec4(center, 1)).xyz;

    // Computing the normal at hit position
    vec3 world_nrm = normalize(world_pos - center);

    {
        vec3 absN = abs(world_nrm);
        float maxC = max(max(absN.x, absN.y), absN.z);
        world_nrm = (maxC == absN.x) ? vec3(sign(world_nrm.x), 0, 0) : (maxC == absN.y) ? vec3(0, sign(world_nrm.y), 0)
                                                                                        : vec3(0, 0, sign(world_nrm.z));
    }

    const vec3 diffuse = world_nrm * 0.5 + 0.5;


    prd.hit_value = diffuse;
}