#pragma once
#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>
#include "defines.glsl"
#include "Box.glsl"


daxa_f32mat4x4 get_geometry_previous_transform_from_instance_id(daxa_u32 instance_id) {
    INSTANCES_BUFFER instance_buffer = INSTANCES_BUFFER(deref(p.world_buffer).instance_address);
    return instance_buffer.instances[instance_id].prev_transform;
}

daxa_f32mat4x4 get_geometry_transform_from_instance_id(daxa_u32 instance_id) {
    INSTANCES_BUFFER instance_buffer = INSTANCES_BUFFER(deref(p.world_buffer).instance_address);
    return instance_buffer.instances[instance_id].transform;
}

daxa_u32 get_geometry_first_primitive_index_from_instance_id(daxa_u32 instance_id) {
    INSTANCES_BUFFER instance_buffer = INSTANCES_BUFFER(deref(p.world_buffer).instance_address);
    return instance_buffer.instances[instance_id].first_primitive_index;
}


daxa_u32 get_current_primitive_index_from_instance_and_primitive_id(INSTANCE_HIT instance_hit) {
    // Get first primitive index from instance id
    daxa_u32 primitive_index = get_geometry_first_primitive_index_from_instance_id(instance_hit.instance_id);
    // Get actual primitive index from offset and primitive id
    return primitive_index + instance_hit.primitive_id;
}

INSTANCE get_instance_from_instance_id(daxa_u32 instance_id) {
    INSTANCES_BUFFER instance_buffer = INSTANCES_BUFFER(deref(p.world_buffer).instance_address);
    return instance_buffer.instances[instance_id];
}

AABB get_aabb_from_primitive_index(daxa_u32 primitive_index) {
    AABB_BUFFER aabb_buffer = AABB_BUFFER(deref(p.world_buffer).aabb_address);
    return aabb_buffer.aabbs[primitive_index];
}

daxa_u32 get_material_index_from_primitive_index(daxa_u32 primitive_index) {
    PRIMITIVE_BUFFER primitive_buffer = PRIMITIVE_BUFFER(deref(p.world_buffer).primitive_address);
    return primitive_buffer.primitives[primitive_index].material_index;
}

daxa_u32 get_material_index_from_instance_and_primitive_id(INSTANCE_HIT instance_hit) {
    // Get material index from primitive
    daxa_u32 primitive_index = get_current_primitive_index_from_instance_and_primitive_id(instance_hit);

    return get_material_index_from_primitive_index(primitive_index);
}

MATERIAL get_material_from_material_index(daxa_u32 mat_index) {
    // Get material index from primitive
    MATERIAL_BUFFER material_buffer = MATERIAL_BUFFER(deref(p.world_buffer).material_address);
    return material_buffer.materials[mat_index];
}

MATERIAL get_material_from_primitive_index(daxa_u32 primitive_index) {

    daxa_u32 mat_index = get_material_index_from_primitive_index(primitive_index);

    return get_material_from_material_index(mat_index);
}

MATERIAL get_material_from_instance_and_primitive_id(INSTANCE_HIT instance_hit) {

    daxa_u32 primitive_index = get_current_primitive_index_from_instance_and_primitive_id(instance_hit);

    return get_material_from_primitive_index(primitive_index);
}


daxa_b32 classify_as_rough(daxa_f32 roughness, daxa_f32 roughness_threshold) {
    return roughness > roughness_threshold;
}

// Credits: https://jcgt.org/published/0007/03/04/

// vec3 box.radius:       independent half-length along the X, Y, and Z axes
// mat3 box.rotation:     box-to-world rotation (orthonormal 3x3 matrix) transformation
// daxa_b32 rayCanStartInBox: if true, assume the origin is never in a box. GLSL optimizes this at compile time
// daxa_b32 oriented:         if false, ignore box.rotation
daxa_b32 intersect_box(Box box, Ray ray, out daxa_f32 distance, out daxa_f32vec3 normal, const daxa_b32 rayCanStartInBox, const in daxa_b32 oriented, in daxa_f32vec3 _invRayDirection) {

    // Move to the box's reference frame. This is unavoidable and un-optimizable.
    ray.origin = box.rotation * (ray.origin - box.center);
    if (oriented) {
        ray.direction = ray.direction * box.rotation;
    }
    
    // This "rayCanStartInBox" branch is evaluated at compile time because `const` in GLSL
    // means compile-time constant. The multiplication by 1.0 will likewise be compiled out
    // when rayCanStartInBox = false.
    daxa_f32 winding;
    if (rayCanStartInBox) {
        // Winding direction: -1 if the ray starts inside of the box (i.e., and is leaving), +1 if it is starting outside of the box
        daxa_f32vec3 ray_box = abs(ray.origin) * box.invRadius;
        winding = (max(ray_box.x, max(ray_box.y, ray_box.z)) < 1.0) ? -1.0 : 1.0;
    } else {
        winding = 1.0;
    }

    // We'll use the negated sign of the ray direction in several places, so precompute it.
    // The sign() instruction is fast...but surprisingly not so fast that storing the result
    // temporarily isn't an advantage.
    daxa_f32vec3 sgn = -sign(ray.direction);

	// Ray-plane intersection. For each pair of planes, choose the one that is front-facing
    // to the ray and compute the distance to it.
    daxa_f32vec3 distanceToPlane = box.radius * winding * sgn - ray.origin;
    if (oriented) {
        distanceToPlane /= ray.direction;
    } else {
        distanceToPlane *= _invRayDirection;
    }

    // Perform all three ray-box tests and cast to 0 or 1 on each axis. 
    // Use a macro to eliminate the redundant code (no efficiency boost from doing so, of course!)
    // Could be written with 
#   define TEST(U, VW)\
         /* Is there a hit on this axis in front of the origin? Use multiplication instead of && for a small speedup */\
         (distanceToPlane.U >= 0.0) && \
         /* Is that hit within the face of the box? */\
         all(lessThan(abs(ray.origin.VW + ray.direction.VW * distanceToPlane.U), box.radius.VW))

    bvec3 test = bvec3(TEST(x, yz), TEST(y, zx), TEST(z, xy));

    // CMOV chain that guarantees exactly one element of sgn is preserved and that the value has the right sign
    sgn = test.x ? daxa_f32vec3(sgn.x, 0.0, 0.0) : (test.y ? daxa_f32vec3(0.0, sgn.y, 0.0) : daxa_f32vec3(0.0, 0.0, test.z ? sgn.z : 0.0));   
        
    // At most one element of sgn is non-zero now. That element carries the negative sign of the 
    // ray direction as well. Notice that we were able to drop storage of the test vector from registers,
    // because it will never be used again.

    // Mask the distance by the non-zero axis
    // Dot product is faster than this CMOV chain, but doesn't work when distanceToPlane contains nans or infs. 
    //
    distance = (sgn.x != 0.0) ? distanceToPlane.x : ((sgn.y != 0.0) ? distanceToPlane.y : distanceToPlane.z);
#   undef TEST

    // Normal must face back along the ray. If you need
    // to know whether we're entering or leaving the box, 
    // then just look at the value of winding. If you need
    // texture coordinates, then use box.invDirection * hitPoint.
    
    if (oriented) {
        normal = box.rotation * sgn;
    } else {
        normal = sgn;
    }
    
    return (sgn.x != 0) || (sgn.y != 0) || (sgn.z != 0);
}



daxa_b32 is_hit_from_ray_providing_model(Ray ray, INSTANCE_HIT instance_hit, daxa_f32vec3 half_extent,
                         out daxa_f32 t_hit, out daxa_f32vec3 pos, out daxa_f32vec3 nor,
                         daxa_f32mat4x4 model, daxa_f32mat4x4 inv_model,
                         const in daxa_b32 ray_can_start_in_box, const in daxa_b32 oriented)
{
    INSTANCE instance = get_instance_from_instance_id(instance_hit.instance_id);

    daxa_u32 current_primitive_index = instance.first_primitive_index + instance_hit.primitive_id;

    // Get aabb from primitive
    AABB aabb = get_aabb_from_primitive_index(current_primitive_index);

    Ray ray_object_space;
    ray_object_space.origin = (inv_model * vec4(ray.origin, 1)).xyz;
    ray_object_space.direction = (inv_model * vec4(ray.direction, 0)).xyz;
    
    daxa_f32vec3 aabb_center = (aabb.minimum + aabb.maximum) * 0.5;

    Box box = Box(aabb_center, half_extent, safeInverse(half_extent), mat3(inv_model));

    daxa_b32 hit = intersect_box(box, ray_object_space, t_hit, nor, ray_can_start_in_box, oriented, safeInverse(ray_object_space.direction));
    pos = ray_object_space.origin + ray_object_space.direction * t_hit;

    return hit;
}

daxa_b32 is_hit_from_ray(Ray ray, INSTANCE_HIT instance_hit, daxa_f32vec3 half_extent,
                         out daxa_f32 t_hit, out daxa_f32vec3 pos, out daxa_f32vec3 nor,
                         out daxa_f32mat4x4 model, out daxa_f32mat4x4 inv_model,
                         const in daxa_b32 ray_can_start_in_box, const in daxa_b32 oriented)
{
    INSTANCE instance = get_instance_from_instance_id(instance_hit.instance_id);

    daxa_u32 current_primitive_index = instance.first_primitive_index + instance_hit.primitive_id;

    // Get aabb from primitive
    AABB aabb = get_aabb_from_primitive_index(current_primitive_index);

    // Get model matrix from instance
    model = instance.transform;

    inv_model = inverse(model);

    Ray ray_object_space;
    ray_object_space.origin = (inv_model * vec4(ray.origin, 1)).xyz;
    ray_object_space.direction = (inv_model * vec4(ray.direction, 0)).xyz;
    
    daxa_f32vec3 aabb_center = (aabb.minimum + aabb.maximum) * 0.5;

    Box box = Box(aabb_center, half_extent, safeInverse(half_extent), mat3(inv_model));

    daxa_b32 hit = intersect_box(box, ray_object_space, t_hit, nor, ray_can_start_in_box, oriented, safeInverse(ray_object_space.direction));
    pos = ray_object_space.origin + ray_object_space.direction * t_hit;

    return hit;
}

daxa_b32 is_hit_from_origin(daxa_f32vec3 origin_world_space, INSTANCE_HIT instance_hit, daxa_f32vec3 half_extent,
                            out daxa_f32 t_hit, out daxa_f32vec3 pos, out daxa_f32vec3 nor,
                            out daxa_f32mat4x4 model, out daxa_f32mat4x4 inv_model,
                            const in daxa_b32 ray_can_start_in_box, const in daxa_b32 oriented)
{
    daxa_u32 current_primitive_index = get_current_primitive_index_from_instance_and_primitive_id(instance_hit);

    // Get aabb from primitive
    AABB aabb = get_aabb_from_primitive_index(current_primitive_index);

    // Get model matrix from instance
    model = get_geometry_transform_from_instance_id(instance_hit.instance_id);

    inv_model = inverse(model);
    
    daxa_f32vec3 aabb_center = (aabb.minimum + aabb.maximum) * 0.5;

    Ray ray_object_space;
    ray_object_space.origin = (inv_model * vec4(origin_world_space, 1)).xyz;
    // Ray needs to travel from origin to center of aabb
    ray_object_space.direction = normalize(aabb_center - ray_object_space.origin);

    Box box = Box(aabb_center, half_extent, safeInverse(half_extent), mat3(inv_model));

    daxa_b32 hit = intersect_box(box, ray_object_space, t_hit, nor, ray_can_start_in_box, oriented, safeInverse(ray_object_space.direction));
    pos = ray_object_space.origin + ray_object_space.direction * t_hit;

    return hit;
}

daxa_b32 is_hit_from_origin_with_geometry_center(daxa_f32vec3 origin_world_space, daxa_f32vec3 aabb_center,
                                                 daxa_f32vec3 half_extent,
                                                 out daxa_f32 t_hit, out daxa_f32vec3 pos, out daxa_f32vec3 nor,
                                                 const in daxa_b32 oriented)
{

    Ray ray_world_space;
    ray_world_space.origin = origin_world_space;
    // Ray needs to travel from origin to center of aabb
    ray_world_space.direction = normalize(aabb_center - ray_world_space.origin);

    Box box = Box(aabb_center, half_extent, safeInverse(half_extent), mat3(1.0));

    daxa_b32 hit = intersect_box(box, ray_world_space, t_hit, nor, false, oriented, safeInverse(ray_world_space.direction));
    pos = ray_world_space.origin + ray_world_space.direction * t_hit;

    return hit;
}


void cube_like_normal(inout daxa_f32vec3 world_nrm) {
    {
        daxa_f32vec3 abs_n = abs(world_nrm);
        daxa_f32 max_c = max(max(abs_n.x, abs_n.y), abs_n.z);
        world_nrm = (max_c == abs_n.x) ? daxa_f32vec3(sign(world_nrm.x), 0, 0) : (max_c == abs_n.y) ? daxa_f32vec3(0, sign(world_nrm.y), 0)
                                                                                        : daxa_f32vec3(0, 0, sign(world_nrm.z));
    }
}

void packed_intersection_info(Ray ray, daxa_f32 t_hit, INSTANCE_HIT instance_hit, daxa_f32mat4x4 model, out daxa_f32vec3 world_pos, out daxa_f32vec3 world_nrm, out daxa_u32 actual_primitive_index)
{

    // Get world position from hit position
    world_pos = ray.origin + ray.direction * t_hit;


    actual_primitive_index = get_current_primitive_index_from_instance_and_primitive_id(instance_hit);

    // Get aabb from primitive
    AABB aabb = get_aabb_from_primitive_index(actual_primitive_index);

    // Get center of aabb
    daxa_f32vec3 center = (aabb.minimum + aabb.maximum) * 0.5;

    // Transform center to world space
    center = (model * vec4(center, 1)).xyz;

    // Computing the normal at hit position
    world_nrm = normalize(world_pos - center);

    // Normal should be cube like 
    cube_like_normal(world_nrm);

}