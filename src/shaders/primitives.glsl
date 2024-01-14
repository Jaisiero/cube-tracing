#pragma once
#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>
#include "defines.glsl"



daxa_f32mat4x4 get_geometry_previous_transform_from_instance_id(daxa_u32 instance_id) {
    // TODO: Transpose before sending to shader
    return transpose(deref(p.instance_buffer).instances[instance_id].prev_transform);
}

daxa_u32 get_geometry_transform_from_instance_id(daxa_u32 instance_id) {
    return deref(p.instance_buffer).instances[instance_id].first_primitive_index;
}

daxa_u32 current_primitive_index() {
    // Get first primitive index from instance id
    uint primitive_index = get_geometry_transform_from_instance_id(gl_InstanceCustomIndexEXT);
    // Get actual primitive index from offset and primitive id
    return primitive_index + gl_PrimitiveID;
}


daxa_u32 current_primitive_index_from_instance_and_primitive_id(daxa_u32 instance_id, daxa_u32 primitive_id) {
    // Get first primitive index from instance id
    uint primitive_index = get_geometry_transform_from_instance_id(instance_id);
    // Get actual primitive index from offset and primitive id
    return primitive_index + primitive_id;
}

MATERIAL get_current_material() {
    // Get material index from primitive
    PRIMITIVE primitive = deref(p.primitives_buffer).primitives[current_primitive_index()];

    daxa_u32 mat_index = primitive.material_index;

    return deref(p.materials_buffer).materials[mat_index];
}

daxa_u32 get_material_index_from_primitive_index(daxa_u32 primitive_index) {
    // Get material index from primitive
    PRIMITIVE primitive = deref(p.primitives_buffer).primitives[primitive_index];

    return primitive.material_index;
}

MATERIAL get_material_from_material_index(daxa_u32 mat_index) {
    // Get material index from primitive
    return deref(p.materials_buffer).materials[mat_index];
}

MATERIAL get_material_from_primitive_index(daxa_u32 primitive_index) {

    daxa_u32 mat_index = get_material_index_from_primitive_index(primitive_index);

    return get_material_from_material_index(mat_index);
}