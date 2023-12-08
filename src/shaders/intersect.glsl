/* Our ray-box intersection */
#ifndef BOX_INTERSECTION_GLSL
#define BOX_INTERSECTION_GLSL
#include "box.glsl"

// Credits: https://jcgt.org/published/0007/03/04/

// vec3 box.radius:       independent half-length along the X, Y, and Z axes
// mat3 box.rotation:     box-to-world rotation (orthonormal 3x3 matrix) transformation
// bool rayCanStartInBox: if true, assume the origin is never in a box. GLSL optimizes this at compile time
// bool oriented:         if false, ignore box.rotation
bool ourIntersectBoxCommon(Box box, Ray ray, out float distance, out float exit_distance, out vec3 normal, const bool rayCanStartInBox, const bool rayCanSecondHit, const in bool oriented, in vec3 _invRayDirection) {

    // Move to the box's reference frame. This is unavoidable and un-optimizable.
    ray.origin = box.rotation * (ray.origin - box.center);
    if (oriented) {
        ray.direction = ray.direction * box.rotation;
    }
    
    // This "rayCanStartInBox" branch is evaluated at compile time because `const` in GLSL
    // means compile-time constant. The multiplication by 1.0 will likewise be compiled out
    // when rayCanStartInBox = false.
    float winding;
    if (rayCanStartInBox) {
        // Winding direction: -1 if the ray starts inside of the box (i.e., and is leaving), +1 if it is starting outside of the box
        vec3 ray_box = abs(ray.origin) * box.invRadius;
        winding = (max(ray_box.x, max(ray_box.y, ray_box.z)) < 1.0) ? -1.0 : 1.0;
    } else {
        winding = 1.0;
    }

    // We'll use the negated sign of the ray direction in several places, so precompute it.
    // The sign() instruction is fast...but surprisingly not so fast that storing the result
    // temporarily isn't an advantage.
    vec3 sgn = -sign(ray.direction);

	// Ray-plane intersection. For each pair of planes, choose the one that is front-facing
    // to the ray and compute the distance to it.
    vec3 distanceToPlane = box.radius * winding * sgn - ray.origin;
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
    sgn = test.x ? vec3(sgn.x, 0.0, 0.0) : (test.y ? vec3(0.0, sgn.y, 0.0) : vec3(0.0, 0.0, test.z ? sgn.z : 0.0));   
        
    // At most one element of sgn is non-zero now. That element carries the negative sign of the 
    // ray direction as well. Notice that we were able to drop storage of the test vector from registers,
    // because it will never be used again.

    // Mask the distance by the non-zero axis
    // Dot product is faster than this CMOV chain, but doesn't work when distanceToPlane contains nans or infs. 
    //
    distance = (sgn.x != 0.0) ? distanceToPlane.x : ((sgn.y != 0.0) ? distanceToPlane.y : distanceToPlane.z);


    if(rayCanSecondHit) {
        // Starting outside of the box. Get the distance to the exit plane.
        if(winding > 0.0) {
            
            ray.origin += distance * ray.direction;

            vec3 exit_sgn = sign(ray.direction);

            // Compute the distance to the exit plane from the new origin which is inside the box
            distanceToPlane = box.radius * exit_sgn - ray.origin;
            if (oriented) {
                distanceToPlane /= ray.direction;
            } else {
                distanceToPlane *= _invRayDirection;
            }

            // Perform all three ray-box tests and cast to 0 or 1 on each axis.
            test = bvec3(TEST(x, yz), TEST(y, zx), TEST(z, xy));

            // CMOV chain that guarantees exactly one element of sgn is preserved and that the value has the right sign
            exit_sgn = test.x ? vec3(exit_sgn.x, 0.0, 0.0) : (test.y ? vec3(0.0, exit_sgn.y, 0.0) : vec3(0.0, 0.0, test.z ? exit_sgn.z : 0.0));

            // Same as above
            exit_distance = (exit_sgn.x != 0.0) ? distanceToPlane.x : ((exit_sgn.y != 0.0) ? distanceToPlane.y : distanceToPlane.z);

            exit_distance += distance;

        } else {
            // Starting inside of the box. The ray can't exit the box, so set the exit distance to infinity.
            exit_distance = 1 / 0;
        } 
    }
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


// Just determines whether the ray hits the axis-aligned box.
// invRayDirection is guaranteed to be finite for all elements.
bool ourHitAABox(vec3 boxCenter, vec3 boxRadius, vec3 rayOrigin, vec3 rayDirection, vec3 invRayDirection) {
    rayOrigin -= boxCenter;
    vec3 distanceToPlane = (-boxRadius * sign(rayDirection) - rayOrigin) * invRayDirection;    

#   define TEST(U, V,W)\
         (float(distanceToPlane.U >= 0.0) * \
          float(abs(rayOrigin.V + rayDirection.V * distanceToPlane.U) < boxRadius.V) *\
          float(abs(rayOrigin.W + rayDirection.W * distanceToPlane.U) < boxRadius.W))

    // If the ray is in the box or there is a hit along any axis, then there is a hit
    return bool(float(abs(rayOrigin.x) < boxRadius.x) * 
                float(abs(rayOrigin.y) < boxRadius.y) * 
                float(abs(rayOrigin.z) < boxRadius.z) + 
                TEST(x, y, z) + 
                TEST(y, z, x) + 
                TEST(z, x, y));
#   undef TEST
}


// There isn't really much application for ray-AABB where we don't check if the ray is in the box, so we
// just give a dummy implementation here to allow the test harness to compile.
bool ourOutsideHitAABox(vec3 boxCenter, vec3 boxRadius, vec3 rayOrigin, vec3 rayDirection, vec3 invRayDirection) {
    return ourHitAABox(boxCenter, boxRadius, rayOrigin, rayDirection, invRayDirection);
}

// Ray is always outside of the box
bool ourOutsideIntersectBox(Box box, Ray ray, out float distance, out float exit_distance, out vec3 normal, const in bool oriented, in vec3 _invRayDirection) {
    return ourIntersectBoxCommon(box, ray, distance, exit_distance, normal, false, true, oriented, _invRayDirection);
}

bool ourIntersectBox(Box box, Ray ray, out float distance, out float exit_distance, out vec3 normal, const in bool oriented, in vec3 _invRayDirection) {
    return ourIntersectBoxCommon(box, ray, distance, exit_distance, normal, true, false, oriented, _invRayDirection);
}

bool ourIntersectBoxTwoHits(Box box, Ray ray, out float distance, out float exit_distance, out vec3 normal, const in bool oriented, in vec3 _invRayDirection) {
    return ourIntersectBoxCommon(box, ray, distance, exit_distance, normal, true, true, oriented, _invRayDirection);
}


#endif // BOX_INTERSECTION_GLSL
