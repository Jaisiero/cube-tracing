#ifndef BOX_GLSL
#define BOX_GLSL

// Credits: https://jcgt.org/published/0007/03/04/

#define Quat vec4

mat3 quat2mat(vec4 q) {
    q *= 1.41421356; //sqrt(2)
    return mat3(1.0 - q.y*q.y - q.z*q.z,  q.x*q.y + q.w*q.z,         q.x*q.z - q.w*q.y,
                q.x*q.y - q.w*q.z,        1.0 - q.x*q.x - q.z*q.z,   q.y*q.z + q.w*q.x,
                q.x*q.z + q.w*q.y,        q.y*q.z - q.w*q.x,         1.0 - q.x*q.x - q.y*q.y);
}

struct Box {
    vec3      center;
    vec3     radius;
    vec3     invRadius;
    mat3     rotation;
};

float safeInverse(float x) { return (x == 0.0) ? 1e12 : (1.0 / x); }
vec3 safeInverse(vec3 v) { return vec3(safeInverse(v.x), safeInverse(v.y), safeInverse(v.z)); }



//Computing the normal for a cube
// Credits: https://github.com/nvpro-samples/vk_raytracing_tutorial_KHR/blob/master/ray_tracing_intersection/shaders/raytrace2.rchit
daxa_f32vec3 transform_to_cube_normal(daxa_f32vec3 normal)
{
    vec3  abs_n = abs(normal);
    float max_c = max(max(abs_n.x, abs_n.y), abs_n.z);
    normal = (max_c == abs_n.x) ? vec3(sign(normal.x), 0, 0) :
        (max_c == abs_n.y) ? vec3(0, sign(normal.y), 0) :
        (max_c == abs_n.z) ? vec3(0, 0, sign(normal.z)) :
                            normal;
    return normal;
}


#endif // BOX_GLSL
