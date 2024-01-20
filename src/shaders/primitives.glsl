#pragma once
#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>
#include "defines.glsl"
#include "Box.glsl"


daxa_f32mat4x4 get_geometry_previous_transform_from_instance_id(daxa_u32 instance_id) {
    // TODO: Transpose before sending to shader
    return deref(p.instance_buffer).instances[instance_id].prev_transform;
}

daxa_f32mat4x4 get_geometry_transform_from_instance_id(daxa_u32 instance_id) {
    // TODO: Transpose before sending to shader
    return deref(p.instance_buffer).instances[instance_id].transform;
}

daxa_u32 get_geometry_first_primitive_index_from_instance_id(daxa_u32 instance_id) {
    return deref(p.instance_buffer).instances[instance_id].first_primitive_index;
}


daxa_u32 get_current_primitive_index_from_instance_and_primitive_id(daxa_u32 instance_id, daxa_u32 primitive_id) {
    // Get first primitive index from instance id
    uint primitive_index = get_geometry_first_primitive_index_from_instance_id(instance_id);
    // Get actual primitive index from offset and primitive id
    return primitive_index + primitive_id;
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

MATERIAL get_material_from_instance_and_primitive_id(daxa_u32 instance_id, daxa_u32 primitive_id) {

    daxa_u32 primitive_index = get_current_primitive_index_from_instance_and_primitive_id(instance_id, primitive_id);

    return get_material_from_primitive_index(primitive_index);
}


// // Ray-AABB intersection
// daxa_f32 hitAabb(const Aabb aabb, const Ray r)
// {
//     vec3 invDir = 1.0 / r.direction;
//     vec3 tbot = invDir * (aabb.minimum - r.origin);
//     vec3 ttop = invDir * (aabb.maximum - r.origin);
//     vec3 tmin = min(ttop, tbot);
//     vec3 tmax = max(ttop, tbot);
//     daxa_f32 t0 = max(tmin.x, max(tmin.y, tmin.z));
//     daxa_f32 t1 = min(tmax.x, min(tmax.y, tmax.z));
//     return t1 > max(t0, 0.0) ? t0 : -1.0;
// }

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

daxa_b32 is_hit_from_ray(Ray ray, daxa_u32 instance_id, daxa_u32 primitive_id, out daxa_f32 t_hit, out daxa_f32vec3 pos, out daxa_f32vec3 nor, const in daxa_b32 rayCanStartInBox, const in daxa_b32 oriented) {
    daxa_u32 current_primitive_index = get_current_primitive_index_from_instance_and_primitive_id(instance_id, primitive_id);

    // Get aabb from primitive
    Aabb aabb = deref(p.aabb_buffer).aabbs[current_primitive_index];

    // Get model matrix from instance
    daxa_f32mat4x4 model = get_geometry_transform_from_instance_id(instance_id);

    daxa_f32mat4x4 inv_model = inverse(model);

    ray.origin = (inv_model * vec4(ray.origin, 1)).xyz;
    ray.direction = (inv_model * vec4(ray.direction, 0)).xyz;
    
    daxa_f32vec3 aabb_center = (aabb.minimum + aabb.maximum) * 0.5;

    // TODO: pass this as a parameter
    daxa_f32vec3 half_extent = vec3(VOXEL_EXTENT * 0.5);

    Box box = Box(aabb_center, half_extent, safeInverse(half_extent), mat3(inv_model));

    daxa_f32vec3 normal = vec3(0.0f);
    daxa_b32 hit = intersect_box(box, ray, t_hit, nor, rayCanStartInBox, oriented, safeInverse(ray.direction));
    pos = ray.origin + ray.direction * t_hit;

    return hit;
}


void packed_intersection_info(Ray ray, daxa_f32 t_hit, daxa_u32 instance_id, daxa_u32 primitive_id, daxa_f32mat4x4 model, out daxa_f32vec3 world_pos, out daxa_f32vec3 world_nrm, out daxa_u32 actual_primitive_index)
{

    // Get world position from hit position
    world_pos = ray.origin + ray.direction * t_hit;


    actual_primitive_index = get_current_primitive_index_from_instance_and_primitive_id(instance_id, primitive_id);

    // Get aabb from primitive
    Aabb aabb = deref(p.aabb_buffer).aabbs[actual_primitive_index];

    // Get center of aabb
    daxa_f32vec3 center = (aabb.minimum + aabb.maximum) * 0.5;

    // Transform center to world space
    center = (model * vec4(center, 1)).xyz;

    // Computing the normal at hit position
    world_nrm = normalize(world_pos - center);
    {
        daxa_f32vec3 abs_n = abs(world_nrm);
        daxa_f32 max_c = max(max(abs_n.x, abs_n.y), abs_n.z);
        world_nrm = (max_c == abs_n.x) ? daxa_f32vec3(sign(world_nrm.x), 0, 0) : (max_c == abs_n.y) ? daxa_f32vec3(0, sign(world_nrm.y), 0)
                                                                                        : daxa_f32vec3(0, 0, sign(world_nrm.z));
    }

}