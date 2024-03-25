#pragma once
#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>
#include "defines.glsl"
#include "Box.glsl"
#include "prng.glsl"

// INSTANCE BUFFER
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


daxa_u32 get_current_primitive_index_from_instance_and_primitive_id(OBJECT_INFO instance_hit) {
    // Get first primitive index from instance id
    daxa_u32 primitive_index = get_geometry_first_primitive_index_from_instance_id(instance_hit.instance_id);
    // Get actual primitive index from offset and primitive id
    return primitive_index + instance_hit.primitive_id;
}

daxa_u32 get_brush_counter_instance_count(){
    BRUSH_COUNTER_BUFFER p = BRUSH_COUNTER_BUFFER(deref(p.status_buffer).brush_counter_address);
    return atomicAdd(p.brush_counter.instance_count, 0);
}

daxa_u32 get_brush_counter_primitive_count(){
    BRUSH_COUNTER_BUFFER p = BRUSH_COUNTER_BUFFER(deref(p.status_buffer).brush_counter_address);
    return atomicAdd(p.brush_counter.primitive_count, 0);
}

daxa_u32 increment_brush_counter_instance_count(){
    BRUSH_COUNTER_BUFFER p = BRUSH_COUNTER_BUFFER(deref(p.status_buffer).brush_counter_address);
    return atomicAdd(p.brush_counter.instance_count, 1);
}

daxa_u32 increment_brush_counter_primitive_count(){
    BRUSH_COUNTER_BUFFER p = BRUSH_COUNTER_BUFFER(deref(p.status_buffer).brush_counter_address);
    return atomicAdd(p.brush_counter.primitive_count, 1);
}

void delete_primtivite_from_instance(OBJECT_INFO instance_hit){
    PRIMITIVE_BITMASK_BUFFER primitive_bitmask_buffer = PRIMITIVE_BITMASK_BUFFER(deref(p.status_buffer).primitive_bitmask_address);
    INSTANCE_BITMASK_BUFFER instance_bitmask_buffer = INSTANCE_BITMASK_BUFFER(deref(p.status_buffer).instance_bitmask_address);
    daxa_u32 primitive_index = get_current_primitive_index_from_instance_and_primitive_id(instance_hit);

    daxa_u32 instance_index = instance_hit.instance_id;

    // atomic or operation to set the bit to 1
    daxa_u32 result_primitive = atomicOr(primitive_bitmask_buffer.primitive_bitmask[primitive_index / 32], 1 << (primitive_index % 32));
    // atomic or operation to set the bit to 1
    daxa_u32 result_instance = atomicOr(instance_bitmask_buffer.instance_bitmask[instance_index / 32], 1 << (instance_index % 32));


    if((result_primitive &  (1U << (primitive_index % 32))) == 0U){
        increment_brush_counter_primitive_count();
    }

    if((result_instance &  (1U << (instance_index % 32))) == 0U){
        increment_brush_counter_instance_count();
    }
}

INSTANCE get_instance_from_instance_id(daxa_u32 instance_id) {
    INSTANCES_BUFFER instance_buffer = INSTANCES_BUFFER(deref(p.world_buffer).instance_address);
    return instance_buffer.instances[instance_id];
}

// REMAPPED PRIMITIVE BUFFER
daxa_u32 get_remapped_primitive_index(daxa_u32 primitive_index) {
    REMAPPED_PRIMITIVE_BUFFER remapped_primitive_buffer = REMAPPED_PRIMITIVE_BUFFER(deref(p.world_buffer).remapped_primitive_address);
    return remapped_primitive_buffer.primitives[primitive_index];
}

daxa_u32 get_remapped_primitive_index_by_object_hit(OBJECT_INFO instance_hit) {
    daxa_u32 primitive_index = get_current_primitive_index_from_instance_and_primitive_id(instance_hit);
    return get_remapped_primitive_index(primitive_index);
}

// AABB BUFFER
AABB get_aabb_from_primitive_index(daxa_u32 primitive_index) {
    AABB_BUFFER aabb_buffer = AABB_BUFFER(deref(p.world_buffer).aabb_address);
    return aabb_buffer.aabbs[primitive_index];
}

// PRIMITIVE BUFFER
daxa_u32 get_material_index_from_primitive_index(daxa_u32 primitive_index)
{
    PRIMITIVE_BUFFER primitive_buffer = PRIMITIVE_BUFFER(deref(p.world_buffer).primitive_address);
    return primitive_buffer.primitives[primitive_index].material_index;
}

daxa_u32 get_light_index_from_primitive_index(daxa_u32 primitive_index)
{
    PRIMITIVE_BUFFER primitive_buffer = PRIMITIVE_BUFFER(deref(p.world_buffer).primitive_address);
    return primitive_buffer.primitives[primitive_index].light_index;
}

// MATERIAL BUFFER
daxa_u32 get_material_index_from_instance_and_primitive_id(OBJECT_INFO instance_hit)
{
    // Get material index from primitive
    daxa_u32 primitive_index = get_current_primitive_index_from_instance_and_primitive_id(instance_hit);

    return get_material_index_from_primitive_index(primitive_index);
}

MATERIAL get_material_from_material_index(daxa_u32 mat_index)
{
    // Get material index from primitive
    MATERIAL_BUFFER material_buffer = MATERIAL_BUFFER(deref(p.world_buffer).material_address);
    return material_buffer.materials[mat_index];
}

MATERIAL get_material_from_primitive_index(daxa_u32 primitive_index)
{

    daxa_u32 mat_index = get_material_index_from_primitive_index(primitive_index);

    return get_material_from_material_index(mat_index);
}

MATERIAL get_material_from_instance_and_primitive_id(OBJECT_INFO instance_hit)
{

    daxa_u32 primitive_index = get_current_primitive_index_from_instance_and_primitive_id(instance_hit);

    return get_material_from_primitive_index(primitive_index);
}

void intersect_initiliaze(INTERSECT i)
{
    MATERIAL mat;
    i.is_hit = false;
    i.distance = 0;
    i.world_hit = vec3(0);
    i.world_nrm = vec3(0);
    i.wo = vec3(0);
    i.wi = vec3(0);
    i.instance_hit = OBJECT_INFO(MAX_INSTANCES, MAX_PRIMITIVES);
    i.material_idx = MAX_MATERIALS;
    i.mat = mat;
}

daxa_b32 instance_hit_valid(OBJECT_INFO instance_hit)
{
    return instance_hit.instance_id < MAX_INSTANCES && instance_hit.primitive_id < MAX_PRIMITIVES;
}



daxa_b32 classify_as_rough(daxa_f32 roughness, daxa_f32 roughness_threshold)
{
    return roughness > roughness_threshold;
}

/** Computes new ray origin based on hit position to avoid self-intersections.
    The function assumes that the hit position has been computed by barycentric
    interpolation, and not from the ray t which is less accurate.

    The method is described in Ray Tracing Gems, Chapter 6, "A Fast and Robust
    Method for Avoiding Self-Intersection" by Carsten Wächter and Nikolaus Binder.

    \param[in] pos Ray hit position.
    \param[in] normal Face normal of hit surface (normalized). The offset will be in the positive direction.
    \return Ray origin of the new ray.
*/
// TODO: revisit this function
daxa_f32vec3 compute_ray_origin(daxa_f32vec3 pos, daxa_f32vec3 normal)
{
    const daxa_f32 origin = 1.f / 32.f;
    const daxa_f32 f_scale = 1.f / 65536.f;
    const daxa_f32 i_scale = 256.f;

    // Per-component integer offset to bit representation of fp32 position.
    daxa_i32vec3 i_off = daxa_i32vec3(normal * i_scale);
    daxa_f32vec3 i_pos;
    i_pos.x = intBitsToFloat(floatBitsToInt(pos.x) + (pos.x < 0.0 ? -i_off.x : i_off.x));
    i_pos.y = intBitsToFloat(floatBitsToInt(pos.y) + (pos.y < 0.0 ? -i_off.y : i_off.y));
    i_pos.z = intBitsToFloat(floatBitsToInt(pos.z) + (pos.z < 0.0 ? -i_off.z : i_off.z));


    // Select per-component between small fixed offset or above variable offset depending on distance to origin.
    daxa_f32vec3 f_off = normal * f_scale;
    daxa_f32vec3 f_pos;
    f_pos.x = abs(pos.x) < origin ? pos.x + f_off.x : i_pos.x;
    f_pos.y = abs(pos.y) < origin ? pos.y + f_off.y : i_pos.y;
    f_pos.z = abs(pos.z) < origin ? pos.z + f_off.z : i_pos.z;
    
    return f_pos;
}

daxa_f32vec3 compute_new_ray_origin(daxa_f32vec3 pos, daxa_f32vec3 normal, daxa_b32 view_side)
{
    // TODO: revisit this function
    pos = compute_ray_origin(pos, view_side ? normal : -normal);
    return compute_ray_origin(pos, view_side ? normal : -normal);
}


// Credits: https://jcgt.org/published/0007/03/04/

// vec3 box.radius:       independent half-length along the X, Y, and Z axes
// mat3 box.rotation:     box-to-world rotation (orthonormal 3x3 matrix) transformation
// daxa_b32 rayCanStartInBox: if true, assume the origin is never in a box. GLSL optimizes this at compile time
// daxa_b32 oriented:         if false, ignore box.rotation
daxa_b32 intersect_box(Box box,
                       Ray ray,
                       out daxa_f32 distance,
                       out daxa_f32vec3 normal,
                       const daxa_b32 rayCanStartInBox,
                       const in daxa_b32 oriented,
                       in daxa_f32vec3 _invRayDirection)
{

    // Move to the box's reference frame. This is unavoidable and un-optimizable.
    ray.origin = box.rotation * (ray.origin - box.center);
    if (oriented)
    {
        ray.direction = ray.direction * box.rotation;
    }

    // This "rayCanStartInBox" branch is evaluated at compile time because `const` in GLSL
    // means compile-time constant. The multiplication by 1.0 will likewise be compiled out
    // when rayCanStartInBox = false.
    daxa_f32 winding;
    if (rayCanStartInBox)
    {
        // Winding direction: -1 if the ray starts inside of the box (i.e., and is leaving), +1 if it is starting outside of the box
        daxa_f32vec3 ray_box = abs(ray.origin) * box.invRadius;
        winding = (max(ray_box.x, max(ray_box.y, ray_box.z)) < 1.0) ? -1.0 : 1.0;
    }
    else
    {
        winding = 1.0;
    }

    // We'll use the negated sign of the ray direction in several places, so precompute it.
    // The sign() instruction is fast...but surprisingly not so fast that storing the result
    // temporarily isn't an advantage.
    daxa_f32vec3 sgn = -sign(ray.direction);

    // Ray-plane intersection. For each pair of planes, choose the one that is front-facing
    // to the ray and compute the distance to it.
    daxa_f32vec3 distanceToPlane = box.radius * winding * sgn - ray.origin;
    if (oriented)
    {
        distanceToPlane /= ray.direction;
    }
    else
    {
        distanceToPlane *= _invRayDirection;
    }

    // Perform all three ray-box tests and cast to 0 or 1 on each axis.
    // Use a macro to eliminate the redundant code (no efficiency boost from doing so, of course!)
    // Could be written with
#define TEST(U, VW)                                                                                                \
    /* Is there a hit on this axis in front of the origin? Use multiplication instead of && for a small speedup */ \
    (distanceToPlane.U >= 0.0) && /* Is that hit within the face of the box? */                                    \
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
#undef TEST

    // Normal must face back along the ray. If you need
    // to know whether we're entering or leaving the box,
    // then just look at the value of winding. If you need
    // texture coordinates, then use box.invDirection * hitPoint.

    if (oriented)
    {
        normal = box.rotation * sgn;
    }
    else
    {
        normal = sgn;
    }

    return (sgn.x != 0) || (sgn.y != 0) || (sgn.z != 0);
}

daxa_b32 is_hit_from_ray_providing_model(Ray ray,
                                         OBJECT_INFO instance_hit,
                                         daxa_f32vec3 half_extent,
                                         out daxa_f32 t_hit,
                                         out daxa_f32vec3 pos,
                                         out daxa_f32vec3 nor,
                                         daxa_f32mat4x4 model,
                                         daxa_f32mat4x4 inv_model,
                                         const in daxa_b32 ray_can_start_in_box,
                                         const in daxa_b32 oriented)
{
    INSTANCE instance = get_instance_from_instance_id(instance_hit.instance_id);

    daxa_u32 current_primitive_index = instance.first_primitive_index + instance_hit.primitive_id;

    // Get aabb from primitive
    AABB aabb = get_aabb_from_primitive_index(current_primitive_index);

    daxa_f32vec3 aabb_center = (aabb.minimum + aabb.maximum) * 0.5;

    aabb_center = (model * vec4(aabb_center, 1)).xyz;

    Box box = Box(aabb_center, half_extent, safeInverse(half_extent), mat3(inv_model));

    daxa_b32 hit = intersect_box(box, ray, t_hit, nor, ray_can_start_in_box, oriented, safeInverse(ray.direction));
    pos = ray.origin + ray.direction * t_hit;

    return hit;
}

daxa_b32 is_hit_from_ray(Ray ray,
                         OBJECT_INFO instance_hit,
                         daxa_f32vec3 half_extent,
                         out daxa_f32 t_hit,
                         out daxa_f32vec3 pos,
                         out daxa_f32vec3 nor,
                         out daxa_f32mat4x4 model,
                         out daxa_f32mat4x4 inv_model,
                         const in daxa_b32 previous_frame,
                         const in daxa_b32 ray_can_start_in_box,
                         const in daxa_b32 oriented)
{
    INSTANCE instance = get_instance_from_instance_id(instance_hit.instance_id);

    daxa_u32 current_primitive_index = instance.first_primitive_index + instance_hit.primitive_id;

    // Get aabb from primitive
    AABB aabb = get_aabb_from_primitive_index(current_primitive_index);

    // Get model matrix from instance
    if(previous_frame)
    {
        model = instance.prev_transform;
    }
    else
    {
        model = instance.transform;
    }

    inv_model = inverse(model);

    daxa_f32vec3 aabb_center = (aabb.minimum + aabb.maximum) * 0.5;

    aabb_center = (model * vec4(aabb_center, 1)).xyz;

    Box box = Box(aabb_center, half_extent, safeInverse(half_extent), mat3(inv_model));

    daxa_b32 hit = intersect_box(box, ray, t_hit, nor, ray_can_start_in_box, oriented, safeInverse(ray.direction));
    pos = ray.origin + ray.direction * t_hit;
    nor = (transpose(inv_model) * vec4(nor, 0)).xyz;

    return hit;
}

daxa_b32 is_hit_from_origin(daxa_f32vec3 origin_world_space,
                            OBJECT_INFO instance_hit,
                            daxa_f32vec3 half_extent,
                            out daxa_f32 t_hit,
                            out daxa_f32vec3 pos,
                            out daxa_f32vec3 nor,
                            out daxa_f32mat4x4 model,
                            out daxa_f32mat4x4 inv_model,
                            const in daxa_b32 previous_frame,
                            const in daxa_b32 ray_can_start_in_box,
                            const in daxa_b32 oriented)
{
    daxa_u32 current_primitive_index = get_current_primitive_index_from_instance_and_primitive_id(instance_hit);

    // Get aabb from primitive
    AABB aabb = get_aabb_from_primitive_index(current_primitive_index);

    // Get model matrix from instance
    if(previous_frame)
    {
        model = get_geometry_previous_transform_from_instance_id(instance_hit.instance_id);
    }
    else
    {
        model = get_geometry_transform_from_instance_id(instance_hit.instance_id);
    }

    inv_model = inverse(model);

    daxa_f32vec3 aabb_center = (aabb.minimum + aabb.maximum) * 0.5;

    aabb_center = (model * vec4(aabb_center, 1)).xyz;

    Ray ray_world_space = Ray(origin_world_space, daxa_f32vec3(0));
    // Ray needs to travel from origin to center of aabb
    ray_world_space.direction = normalize(aabb_center - ray_world_space.origin);

    Box box = Box(aabb_center, half_extent, safeInverse(half_extent), mat3(inv_model));

    daxa_b32 hit = intersect_box(box, ray_world_space, t_hit, nor, ray_can_start_in_box, oriented, safeInverse(ray_world_space.direction));
    pos = ray_world_space.origin + ray_world_space.direction * t_hit;

    return hit;
}

daxa_b32 is_hit_from_origin_with_geometry_center(daxa_f32vec3 origin_world_space,
                                                 daxa_f32vec3 aabb_center,
                                                 daxa_f32vec3 half_extent,
                                                 out daxa_f32 t_hit,
                                                 out daxa_f32vec3 pos,
                                                 out daxa_f32vec3 nor,
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

daxa_f32vec3 cube_like_normal(daxa_f32vec3 world_nrm)
{
    {
        daxa_f32vec3 abs_n = abs(world_nrm);
        daxa_f32 max_c = max(max(abs_n.x, abs_n.y), abs_n.z);
        return (max_c == abs_n.x) ? daxa_f32vec3(sign(world_nrm.x), 0, 0) : (max_c == abs_n.y) ? daxa_f32vec3(0, sign(world_nrm.y), 0)
                                                                                                    : daxa_f32vec3(0, 0, sign(world_nrm.z));
    }
}

void packed_intersection_info(Ray ray,
                              daxa_f32 t_hit,
                              OBJECT_INFO instance_hit,
                              daxa_f32mat4x4 model,
                              out daxa_f32vec3 world_pos,
                              out daxa_f32vec3 world_nrm,
                              out daxa_u32 actual_primitive_index)
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
    world_nrm = cube_like_normal(world_nrm);
}

/**
 * @brief Check if the instance hit exists
 *
 * @param instance_hit Instance hit
 * @return daxa_b32 True if the instance hit exists
 */
daxa_b32 instance_hit_exists(const OBJECT_INFO instance_hit)
{
  return instance_hit.instance_id < MAX_INSTANCES && instance_hit.primitive_id < MAX_PRIMITIVES;
}

daxa_b32 is_valid_geometry(const INTERSECT central_intersecion, const INTERSECT neighbor_intersection, const daxa_f32vec3 camera_pos) {
  daxa_f32 central_dist = distance(camera_pos, central_intersecion.world_hit);
  daxa_f32 neighbor_dist = distance(camera_pos, neighbor_intersection.world_hit);
  return dot(central_intersecion.world_nrm, neighbor_intersection.world_nrm) >= 0.5f && abs(central_dist - neighbor_dist) < 0.1f * central_dist;
}

/**
 *  @brief Load intersection data from vertex position and optionally load
 * material
 *
 * @param instance_hit Instance hit
 * @param world_pos World position
 * @param primary_hit Primary hit
 * @param load_material Load material
 */
INTERSECT load_intersection_data_vertex_position(
    const OBJECT_HIT instance_hit, const daxa_f32vec3 world_pos,
    const daxa_b32 is_previous_frame, daxa_b32 is_primary_hit,
    const daxa_b32 load_material) {
  INTERSECT i;

  daxa_f32 distance;
  daxa_f32vec3 pos;
  daxa_f32vec3 nor;
  daxa_f32mat4x4 model;
  daxa_f32mat4x4 inv_model;
  // TODO: This should be a parameter
  daxa_f32vec3 half_extent = daxa_f32vec3(HALF_VOXEL_EXTENT);

  Ray ray = Ray(world_pos, instance_hit.hit - world_pos);

  if (!is_hit_from_ray(ray, instance_hit.object, half_extent, distance, pos,
                          nor, model, inv_model, is_previous_frame, true,
                          true)) {
    intersect_initiliaze(i);
  } else {
    pos = compute_ray_origin(pos, nor);
    pos = compute_ray_origin(pos, nor);
    distance = length(world_pos - pos);

    daxa_f32vec3 wo = normalize(world_pos - pos);

    daxa_u32 material_idx = MAX_MATERIALS;
    MATERIAL mat;

    if (load_material) {
      material_idx =
          get_material_index_from_instance_and_primitive_id(instance_hit.object);
      mat = get_material_from_material_index(material_idx);
    }

    i = INTERSECT(true, distance, pos, nor, wo, daxa_f32vec3(0), instance_hit.object,
                  material_idx, mat);
  }

  return i;
}








/**
 *  @brief Load intersection data from vertex position by ray and optionally load
 * material
 *
 * @param instance_hit Instance hit
 * @param world_pos World position
 * @param primary_hit Primary hit
 * @param load_material Load material
 */
INTERSECT load_intersection_data_vertex_position_by_ray(
    const OBJECT_INFO instance_hit, const Ray ray,
    const daxa_b32 is_previous_frame, daxa_b32 is_primary_hit,
    const daxa_b32 load_material) {
  INTERSECT i;

  daxa_f32 distance;
  daxa_f32vec3 pos;
  daxa_f32vec3 nor;
  daxa_f32mat4x4 model;
  daxa_f32mat4x4 inv_model;
  // TODO: This should be a parameter
  daxa_f32vec3 half_extent = daxa_f32vec3(HALF_VOXEL_EXTENT);

  if (!is_hit_from_ray(ray, instance_hit, half_extent, distance, pos,
                          nor, model, inv_model, is_previous_frame, true,
                          true)) {
    intersect_initiliaze(i);
  } else {
    pos = compute_ray_origin(pos, nor);
    pos = compute_ray_origin(pos, nor);
    distance = length(ray.origin - pos);

    daxa_f32vec3 wo = normalize(ray.origin - pos);

    daxa_u32 material_idx = MAX_MATERIALS;
    MATERIAL mat;

    if (load_material) {
      material_idx =
          get_material_index_from_instance_and_primitive_id(instance_hit);
      mat = get_material_from_material_index(material_idx);
    }

    i = INTERSECT(true, distance, pos, nor, wo, daxa_f32vec3(0), instance_hit,
                  material_idx, mat);
  }

  return i;
}