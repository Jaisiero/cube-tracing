#ifndef PERLIN_GLSL
#define PERLIN_GLSL

#define DAXA_RAY_TRACING 1
#include <daxa/daxa.inl>

#define ONE 0.00390625
#define ONEHALF 0.001953125

float get_perlin_noise_fade(float t) {
  //return t*t*(3.0-2.0*t); // Old fade
  return t*t*t*(t*(t*6.0-15.0)+10.0); // Improved fade
}
 
float get_perlin_noise(vec3 P, daxa_ImageViewId noise_texture, daxa_SamplerId noise_sampler)
{
  vec3 Pi = ONE*floor(P)+ONEHALF; 
                                 
  vec3 Pf = P-floor(P);
  
  // Noise contributions from (x=0, y=0), z=0 and z=1
  float perm00 = texture(daxa_sampler2D(noise_texture, noise_sampler), Pi.xy).a ;
  vec3  grad000 = texture(daxa_sampler2D(noise_texture, noise_sampler), vec2(perm00, Pi.z)).rgb * 4.0 - 1.0;
  float n000 = dot(grad000, Pf);
  vec3  grad001 = texture(daxa_sampler2D(noise_texture, noise_sampler), vec2(perm00, Pi.z + ONE)).rgb * 4.0 - 1.0;
  float n001 = dot(grad001, Pf - vec3(0.0, 0.0, 1.0));

  // Noise contributions from (x=0, y=1), z=0 and z=1
  float perm01 = texture(daxa_sampler2D(noise_texture, noise_sampler), Pi.xy + vec2(0.0, ONE)).a ;
  vec3  grad010 = texture(daxa_sampler2D(noise_texture, noise_sampler), vec2(perm01, Pi.z)).rgb * 4.0 - 1.0;
  float n010 = dot(grad010, Pf - vec3(0.0, 1.0, 0.0));
  vec3  grad011 = texture(daxa_sampler2D(noise_texture, noise_sampler), vec2(perm01, Pi.z + ONE)).rgb * 4.0 - 1.0;
  float n011 = dot(grad011, Pf - vec3(0.0, 1.0, 1.0));

  // Noise contributions from (x=1, y=0), z=0 and z=1
  float perm10 = texture(daxa_sampler2D(noise_texture, noise_sampler), Pi.xy + vec2(ONE, 0.0)).a ;
  vec3  grad100 = texture(daxa_sampler2D(noise_texture, noise_sampler), vec2(perm10, Pi.z)).rgb * 4.0 - 1.0;
  float n100 = dot(grad100, Pf - vec3(1.0, 0.0, 0.0));
  vec3  grad101 = texture(daxa_sampler2D(noise_texture, noise_sampler), vec2(perm10, Pi.z + ONE)).rgb * 4.0 - 1.0;
  float n101 = dot(grad101, Pf - vec3(1.0, 0.0, 1.0));

  // Noise contributions from (x=1, y=1), z=0 and z=1
  float perm11 = texture(daxa_sampler2D(noise_texture, noise_sampler), Pi.xy + vec2(ONE, ONE)).a ;
  vec3  grad110 = texture(daxa_sampler2D(noise_texture, noise_sampler), vec2(perm11, Pi.z)).rgb * 4.0 - 1.0;
  float n110 = dot(grad110, Pf - vec3(1.0, 1.0, 0.0));
  vec3  grad111 = texture(daxa_sampler2D(noise_texture, noise_sampler), vec2(perm11, Pi.z + ONE)).rgb * 4.0 - 1.0;
  float n111 = dot(grad111, Pf - vec3(1.0, 1.0, 1.0));

  // Blend contributions along x
  vec4 n_x = mix(vec4(n000, n001, n010, n011), vec4(n100, n101, n110, n111), get_perlin_noise_fade(Pf.x));

  // Blend contributions along y
  vec2 n_xy = mix(n_x.xy, n_x.zw, get_perlin_noise_fade(Pf.y));

  // Blend contributions along z
  float n_xyz = mix(n_xy.x, n_xy.y, get_perlin_noise_fade(Pf.z));
 
  return n_xyz;
}

float get_perlin_turbulence(vec3 P, int octaves, float lacunarity, float gain, daxa_ImageViewId noise_texture, daxa_SamplerId noise_sampler)
{	
  float sum = 0;
  float scale = 1;
  float totalgain = 1;
  for(int i=0;i<octaves;i++){
    sum += totalgain*get_perlin_noise(P*scale, noise_texture, noise_sampler);
    scale *= lacunarity;
    totalgain *= gain;
  }
  return abs(sum);
}


#endif // PERLIN_GLSL