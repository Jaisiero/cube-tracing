// prgn.glsl
#ifndef PRNG_GLSL
#define PRNG_GLSL
#include <daxa/daxa.inl>
#include "shared.inl"
// #include "Box.glsl"
#include "random.glsl"

struct LCG {
    daxa_u32 state;
    daxa_u32 a;
    daxa_u32 c;
    daxa_u32 m;
};

// Credits: https://raytracing.github.io/books/RayTracingInOneWeekend.html#metal/modelinglightscatterandreflectance
daxa_b32 normal_near_zero(daxa_f32vec3 v)
{
    const daxa_f32 s = 1e-8;
    return (abs(v.x) < s) && (abs(v.y) < s) && (abs(v.z) < s);
}

daxa_f32 length_square(daxa_f32vec3 v) {
    return v.x * v.x + v.y * v.y + v.z * v.z;
}

daxa_i32 randomIntLCG(inout daxa_u32 seed) {
    return daxa_i32(urnd(seed));
}

daxa_i32 randomIntInRangeLCG(inout daxa_u32 seed, daxa_i32 min, daxa_i32 max) {
    daxa_i32 random_value = randomIntLCG(seed);
    return min + random_value % (max - min);
}

daxa_u32 randomUIntLCG(inout daxa_u32 seed) {
    return urnd(seed);
}

daxa_u32 randomUIntInRangeLCG(inout daxa_u32 seed, daxa_u32 min, daxa_u32 max) {
    daxa_u32 random_value = randomUIntLCG(seed);
    return min + random_value % (max - min);
}

daxa_f32 randomLCG(inout daxa_u32 seed) {
    return rnd(seed);
}

daxa_f32 randomInRangeLCG(inout daxa_u32 seed, daxa_f32 min, daxa_f32 max) {
    daxa_f32 random_value = rnd(seed);
    return min + random_value * (max - min);
}

daxa_f32vec3 randomVec3LCG(inout daxa_u32 seed) {
    return daxa_f32vec3(rnd(seed), rnd(seed), rnd(seed));
}

daxa_f32vec3 randomVec3InRangeLCG(inout daxa_u32 seed, daxa_f32 min, daxa_f32 max) {
    return daxa_f32vec3(randomInRangeLCG(seed, min, max), randomInRangeLCG(seed, min, max), randomInRangeLCG(seed, min, max));
}



daxa_f32vec3 random_in_unit_sphere(inout daxa_u32 seed) {
    while (true) {
        daxa_f32vec3 p = randomVec3InRangeLCG(seed, -1.0f, 1.0f);
        if (length_square(p) >= 1.0f) continue;
        return p;
    }
}

daxa_f32vec3 random_unit_vector(inout daxa_u32 seed) {
    return normalize(random_in_unit_sphere(seed));
}

daxa_f32vec3 random_on_hemisphere(inout daxa_u32 seed, daxa_f32vec3 normal) {
    daxa_f32vec3 on_unit_sphere = random_unit_vector(seed);
    if (dot(on_unit_sphere, normal) > 0.0) // In the same hemisphere as the normal
        return on_unit_sphere;
    else
        return -on_unit_sphere;
}

daxa_f32vec3 random_cosine_direction(inout uint seed, daxa_f32vec3 normal) {
    daxa_f32 r1 = randomLCG(seed);
    daxa_f32 r2 = randomLCG(seed);
    daxa_f32 z = sqrt(1.0f - r2);

    daxa_f32 phi = 2.0f * DAXA_PI * r1;
    daxa_f32 x = cos(phi) * sqrt(r2);
    daxa_f32 y = sin(phi) * sqrt(r2);


    daxa_f32vec3 u, v;

    if (abs(normal.x) > 0.1f) {
        u = daxa_f32vec3(0.0f, 1.0f, 0.0f);
    } else {
        u = daxa_f32vec3(1.0f, 0.0f, 0.0f);
    }

    u = normalize(cross(normal, u));

    v = cross(normal, u);

    return x * u + y * v + z * normal;
}


daxa_f32vec3 random_in_unit_disk(inout daxa_u32 seed) {
    while (true) {
        daxa_f32vec3 p = daxa_f32vec3(randomInRangeLCG(seed, -1.0f, 1.0f), randomInRangeLCG(seed, -1.0f, 1.0f), 0);
        if (length_square(p) < 1)
            return p;
    }
}

// Get a random unit vector of one of the six faces of a cube
daxa_f32vec3 random_cube_normal(inout daxa_u32 seed) {
    daxa_u32 face = min(urnd_interval(seed, 0, CUBE_FACE_COUNT), CUBE_FACE_COUNT-1);
    switch (face) {
    case 0:
        return daxa_f32vec3(-1, 0, 0);
    case 1:
        return daxa_f32vec3(1, 0, 0);
    case 2:
        return daxa_f32vec3(0, -1, 0);
    case 3:
        return daxa_f32vec3(0, 1, 0);
    case 4:
        return daxa_f32vec3(0, 0, -1);
    case 5:
        return daxa_f32vec3(0, 0, 1);
    }
    return daxa_f32vec3(-1, 0, 0);
}

void calculate_orthonormal_basis(daxa_f32vec3 normal, inout daxa_f32vec3 tangent1, inout daxa_f32vec3 tangent2) {
    if (abs(normal.x) > abs(normal.y)) {
        tangent1 = normalize(daxa_f32vec3(-normal.z, 0.0, normal.x));
    } else {
        tangent1 = normalize(daxa_f32vec3(0.0, normal.z, -normal.y));
    }
    tangent2 = normalize(cross(normal, tangent1));
}

/**
    * @brief Get a random point in a quad wich can be oriented in any direction
    * 
    * @param n Normal of the quad
    * @param p Origin of the quad
    * @param s Half size of the quad
    * @param seed Random seed
    * @return daxa_f32vec3 Random point in the quad
    */
daxa_f32vec3 random_quad(daxa_f32vec3 n, daxa_f32vec3 p, daxa_f32vec2 s, inout daxa_u32 seed) {
    // 1. Generar dos números aleatorios en el rango [0, 1)
    daxa_f32 u = rnd(seed);
    daxa_f32 v = rnd(seed);

    // 2. Calcular un punto aleatorio en el plano del cuadrado unitario en el espacio local del cuadrado
    daxa_f32vec2 q = daxa_f32vec2(u, v);

    // 3. Escalar q por el tamaño del cuadrado
    q *= s;

    // 4. Transformar q al espacio del mundo utilizando la orientación proporcionada por la normal n y el punto p
    daxa_f32vec3 x_axis, y_axis;
    calculate_orthonormal_basis(n, x_axis, y_axis);
    daxa_f32vec3 qWorld = p + x_axis * q.x + y_axis * q.y;

    return qWorld;
}

daxa_f32vec3 random_in_unit_rectangle(daxa_f32vec3 normal, daxa_f32vec3 origin, daxa_f32vec2 dimensions, inout daxa_u32 seed) {
    // Calcula dos vectores ortogonales al vector normal
    daxa_f32vec3 tangent1, tangent2;
    calculate_orthonormal_basis(normal, tangent1, tangent2);
    
    daxa_f32vec3 p;
    while (true) {
        // Genera coordenadas aleatorias en el rango [-1, 1]
        daxa_f32 x = randomInRangeLCG(seed, -1.0f, 1.0f);
        daxa_f32 y = randomInRangeLCG(seed, -1.0f, 1.0f);
        
        // Escala las coordenadas para que estén en el rango de las dimensiones del rectángulo
        daxa_f32vec3 point_on_plane = origin + tangent1 * (dimensions.x * x) + tangent2 * (dimensions.y * y);
        
        // Verifica si el punto está dentro del rectángulo proyectado
        daxa_f32vec3 to_point = point_on_plane - origin;
        daxa_f32 projected_length = dot(to_point, normal);
        if (projected_length > 0 && projected_length < length(normal)) {
            p = point_on_plane;
            break;
        }
    }
    return p;
}


daxa_f32vec3 defocus_disk_sample(daxa_f32vec3 origin, daxa_f32vec2 defocus_disk, inout daxa_u32 seed) {
    // Returns a random point in the camera defocus disk.
    daxa_f32vec3 p = random_in_unit_disk(seed);
    return origin + (p.x * defocus_disk.x) + (p.y * defocus_disk.y);
}



daxa_f32vec3 reflection(daxa_f32vec3 v, daxa_f32vec3 n) {
    return v - 2*dot(v,n)*n;
}


daxa_f32 reflectance(daxa_f32 cosine, daxa_f32 ref_idx) {
    daxa_f32 r0 = (1.0f - ref_idx) / (1.0f + ref_idx);
    r0 = r0 * r0;
    return r0 + (1.0f - r0) * pow((1.0f - cosine), 5.0f);
}

daxa_f32vec3 refraction(daxa_f32vec3 uv, daxa_f32vec3 n, daxa_f32 etai_over_etat) {
    daxa_f32 cos_theta = min(dot(-uv, n), 1.0f);
    daxa_f32vec3 r_out_perp =  etai_over_etat * (uv + cos_theta*n);
    daxa_f32vec3 r_out_parallel = -sqrt(abs(1.0 - length_square(r_out_perp))) * n;
    return r_out_parallel + r_out_perp;
}



daxa_b32 scatter(MATERIAL m, daxa_f32vec3 direction, daxa_f32vec3 world_nrm, inout uint seed, out daxa_f32vec3 scatter_direction) {
    switch (m.type & MATERIAL_TYPE_MASK)
    {
    case MATERIAL_TYPE_METAL:
        daxa_f32vec3 reflected = reflection(direction, world_nrm);
        scatter_direction = reflected + min(m.roughness, 1.0) * random_cosine_direction(seed, reflected);
        return dot(scatter_direction, world_nrm) > 0.0f;
    case MATERIAL_TYPE_DIELECTRIC:
        daxa_f32 etai_over_etat = m.ior;
        if (dot(direction, world_nrm) > 0.0f) {
            world_nrm = -world_nrm;
            etai_over_etat = 1.0f / etai_over_etat;
        }

        daxa_f32 cos_theta = min(dot(-direction, world_nrm), 1.0);
        daxa_f32 sin_theta = sqrt(1.0 - cos_theta*cos_theta);

        daxa_b32 cannot_refract = etai_over_etat * sin_theta > 1.0;

        if (cannot_refract || reflectance(cos_theta, etai_over_etat) > randomInRangeLCG(seed, 0.0f, 1.0f))
            scatter_direction = reflection(direction, world_nrm);
        else
            scatter_direction = refraction(direction, world_nrm, etai_over_etat);
        return true;
    case MATERIAL_TYPE_CONSTANT_MEDIUM:
        scatter_direction = random_unit_vector(seed);
        // Catch degenerate scatter direction
        if (normal_near_zero(scatter_direction))
            scatter_direction = world_nrm;
        return true;
    case MATERIAL_TYPE_LAMBERTIAN:
    default:
        scatter_direction = random_cosine_direction(seed, world_nrm);
        // Catch degenerate scatter direction
        if (normal_near_zero(scatter_direction))
            scatter_direction = world_nrm;

        return true;
    }
    return false;
}


daxa_i32vec2 get_next_neighbor_pixel(daxa_u32 start_index, daxa_i32vec2 pixel, daxa_i32 i, daxa_i32 small_window_radius, inout daxa_u32 seed) {
    daxa_i32vec2 neighbor_pixel = daxa_i32vec2(0.f);

    // daxa_i32 small_window_diameter = 2 * small_window_radius + 1;
    // neighbor_pixel =
    //     pixel + daxa_i32vec2(-small_window_radius + (i % small_window_diameter),
    //                          -small_window_radius + (i / small_window_diameter));
    // if (all(equal(neighbor_pixel, pixel)))
    //   neighbor_pixel = daxa_i32vec2(-1);


    daxa_f32vec2 offset = 2.0 * daxa_f32vec2(rnd(seed), rnd(seed)) - 1;

    // Scale offset
    offset.x = pixel.x + daxa_i32(offset.x * small_window_radius);
    offset.y = pixel.y + daxa_i32(offset.y * small_window_radius);

    neighbor_pixel = daxa_i32vec2(offset);

    if (all(equal(neighbor_pixel, pixel)))
      neighbor_pixel = daxa_i32vec2(-1);

    return neighbor_pixel;
}

#endif // PRNG_GLSL