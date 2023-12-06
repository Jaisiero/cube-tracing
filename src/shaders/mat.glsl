// mat.glsl
#include <daxa/daxa.inl>
#include "shared.inl"


// Credit: https://github.com/nvpro-samples/vk_raytracing_tutorial_KHR/blob/master/ray_tracing__before/shaders/wavefront.glsl
daxa_f32vec3 compute_diffuse(MATERIAL mat, daxa_f32vec3 light_dir, daxa_f32vec3 normal)
{
  // Lambertian
  daxa_f32 dot_nl = max(dot(normal, light_dir), 0.0);
  daxa_f32vec3  c     = mat.diffuse * dot_nl;
  if(mat.illum >= 1)
    c += mat.ambient;
  return c;
}

daxa_f32vec3 compute_specular(MATERIAL mat, daxa_f32vec3 view_dir, daxa_f32vec3 light_dir, daxa_f32vec3 normal)
{
  if (mat.illum < 2)
    return daxa_f32vec3(0);

  // Compute specular only if not in shadow
  const daxa_f32 k_pi = 3.14159265;
  const daxa_f32 k_shininess = max(mat.shininess, 4.0);

  // Specular
  const daxa_f32 k_energy_conservation = (2.0 + k_shininess) / (2.0 * k_pi);
  daxa_f32vec3 V = normalize(-view_dir);
  daxa_f32vec3 R = reflect(-light_dir, normal);
  daxa_f32 specular = k_energy_conservation * pow(max(dot(V, R), 0.0), k_shininess);

  return daxa_f32vec3(mat.specular * specular);
}

// Credit: https://gamedev.stackexchange.com/questions/92015/optimized-linear-to-srgb-glsl
daxa_f32vec4 fromLinear(daxa_f32vec4 linear_RGB)
{
    bvec4 cutoff = lessThan(linear_RGB, daxa_f32vec4(0.0031308));
    daxa_f32vec4 higher = daxa_f32vec4(1.055)*pow(linear_RGB, daxa_f32vec4(1.0/2.4)) - daxa_f32vec4(0.055);
    daxa_f32vec4 lower = linear_RGB * daxa_f32vec4(12.92);

    return mix(higher, lower, cutoff);
}


daxa_f32vec4 linear_to_gamma(daxa_f32vec4 linear_RGB)
{
    return pow(linear_RGB, daxa_f32vec4(1.0/2.2));
}

daxa_f32vec3 background_color(daxa_f32vec3 dir)
{
    daxa_f32vec3 unit_dir = normalize(dir);
    daxa_f32 t = 0.5 * (unit_dir.y + 1.0);
    return mix(daxa_f32vec3(1.0, 1.0, 1.0), daxa_f32vec3(0.5, 0.7, 1.0), t);
}


#if(DEBUG_NORMALS == 1)
daxa_f32vec3 normal_to_color(daxa_f32vec3 normal)
{
    return (normal + daxa_f32vec3(1.0)) * 0.5;
}
#endif