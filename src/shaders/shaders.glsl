#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#extension GL_EXT_ray_query : enable
#include <daxa/daxa.inl>

#include "shared.inl"

DAXA_DECL_PUSH_CONSTANT(PushConstant, p)

struct Aabb
{
  vec3 minimum;
  vec3 maximum;
};

struct Ray
{
  vec3 origin;
  vec3 direction;
};


// Ray-AABB intersection
float hit_aabb(const Aabb aabb, const Ray r)
{
  vec3  invDir = 1.0 / r.direction;
  vec3  tbot   = invDir * (aabb.minimum - r.origin);
  vec3  ttop   = invDir * (aabb.maximum - r.origin);
  vec3  tmin   = min(ttop, tbot);
  vec3  tmax   = max(ttop, tbot);
  float t0     = max(tmin.x, max(tmin.y, tmin.z));
  float t1     = min(tmax.x, min(tmax.y, tmax.z));
  return t1 > max(t0, 0.0) ? t0 : -1.0;
}

// Credit: https://github.com/nvpro-samples/vk_raytracing_tutorial_KHR/blob/master/ray_tracing__before/shaders/wavefront.glsl
vec3 compute_diffuse(vec3 ambient_color, vec3 mat_diffuse, vec3 light_dir, vec3 normal)
{
  // Lambertian
  float dot_nl = max(dot(normal, light_dir), 0.0);
  vec3  c     = mat_diffuse * dot_nl;
//   if(mat.illum >= 1)
    c += ambient_color;
  return c;
}

vec3 compute_specular(vec3 specular_color, float shininess, vec3 viewDir, vec3 lightDir, vec3 normal)
{
//   if(mat.illum < 2)
//     return vec3(0);

  // Compute specular only if not in shadow
  const float kPi        = 3.14159265;
  const float kShininess = max(shininess, 4.0);

  // Specular
  const float kEnergyConservation = (2.0 + kShininess) / (2.0 * kPi);
  vec3        V                   = normalize(-viewDir);
  vec3        R                   = reflect(-lightDir, normal);
  float       specular            = kEnergyConservation * pow(max(dot(V, R), 0.0), kShininess);

  return vec3(specular_color * specular);
}


// Credit: https://gamedev.stackexchange.com/questions/92015/optimized-linear-to-srgb-glsl
vec4 fromLinear(vec4 linearRGB)
{
    bvec4 cutoff = lessThan(linearRGB, vec4(0.0031308));
    vec4 higher = vec4(1.055)*pow(linearRGB, vec4(1.0/2.4)) - vec4(0.055);
    vec4 lower = linearRGB * vec4(12.92);

    return mix(higher, lower, cutoff);
}

const vec3 LIGHT_POSITION = vec3(0.0, 0.0, 1.0);

layout(local_size_x = 8, local_size_y = 8) in;
void main()
{
    const ivec2 index = ivec2(gl_GlobalInvocationID.xy);
    if (index.x >= p.size.x || index.y >= p.size.y)
    {
        return;
    }

    uint cull_mask = 0xff;
    float t_min = 0.0f;
    float t_max = 1000.0f;
    
    uvec2 launch_size = gl_NumWorkGroups.xy * 8;

	const vec2 pixel_center = vec2(index) + vec2(0.5);
	const vec2 inv_UV = pixel_center/vec2(launch_size);
	vec2 d = inv_UV * 2.0 - 1.0;

    daxa_f32mat4x4 inv_view = deref(p.camera_buffer).inv_view;
    daxa_f32mat4x4 inv_proj = deref(p.camera_buffer).inv_proj;

    vec4 origin = inv_view * vec4(0,0,0,1);
	vec4 target = inv_proj * vec4(d.x, d.y, 1, 1) ;
	vec4 direction = inv_view * vec4(normalize(target.xyz), 0) ;

    Ray ray;
    ray.origin = origin.xyz;
    ray.direction = direction.xyz;

    float t = 0.0f;

    rayQueryEXT ray_query;
    rayQueryInitializeEXT(ray_query, daxa_accelerationStructureEXT(p.tlas),
                        gl_RayFlagsOpaqueEXT,
                        cull_mask, ray.origin, t_min, ray.direction, t_max);

    while(rayQueryProceedEXT(ray_query)) {
        uint type = rayQueryGetIntersectionTypeEXT(ray_query, false);
        if(type ==
            gl_RayQueryCandidateIntersectionAABBEXT) {
            rayQueryGenerateIntersectionEXT(ray_query, t);
        }
    }

    vec3 out_colour = vec3(0.0, 0.0, 0.0);
    uint type = rayQueryGetIntersectionTypeEXT(ray_query, true);

    if(type ==
        gl_RayQueryCommittedIntersectionGeneratedEXT)
    {

        // get instance id
        int instance_id = rayQueryGetIntersectionInstanceCustomIndexEXT(ray_query, true);

        // get instance colour
        out_colour = deref(p.instance_buffer).instances[instance_id].color;

        mat4 transform = deref(p.instance_buffer).instances[instance_id].transform;
        // mat4 inv_transform = inverse(transform);

        // Get center position from transform
        vec3 aabb_center = vec3(0, 0, 0);

        // Get aabb from center_pos and transform
        Aabb aabb;
        aabb.minimum = aabb_center - vec3(0.15, 0.15, 0.15);
        aabb.maximum =  aabb_center + vec3(0.15, 0.15, 0.15);
        aabb.minimum = (transform * vec4(aabb.minimum, 1)).xyz;
        aabb.maximum = (transform * vec4(aabb.maximum, 1)).xyz;
        
        t = hit_aabb(aabb, ray);

        vec3 world_pos = ray.origin + ray.direction * t;
        
        vec3 center_pos = (transform * vec4(aabb_center, 1)).xyz;
        // Computing the normal at hit position
        vec3 world_nrm = normalize(-center_pos);

// Credits: https://github.com/nvpro-samples/vk_raytracing_tutorial_KHR/blob/master/ray_tracing_intersection/shaders/raytrace2.rchit
        // Computing the normal for a cube
        {
            vec3  absN = abs(world_nrm);
            float maxC = max(max(absN.x, absN.y), absN.z);
            world_nrm   = (maxC == absN.x) ? vec3(sign(world_nrm.x), 0, 0) :
                        (maxC == absN.y) ? vec3(0, sign(world_nrm.y), 0) :
                                            vec3(0, 0, sign(world_nrm.z));
        }

        // Vector toward the light
        vec3  L;
        float light_intensity = 1000.0;
        float light_distance  = 100.0;
        uint lightType      = 0;
        // Point light
        if(lightType == 0)
        {
            vec3 lDir      = LIGHT_POSITION - world_pos;
            light_distance  = length(lDir);
            light_intensity = light_intensity / (light_distance * light_distance);
            L              = normalize(lDir);
        }
        else  // Directional light
        {
            L = normalize(LIGHT_POSITION);
        }

        // Diffuse
        vec3  diffuse     = compute_diffuse(out_colour, vec3(0.5, 0.5, 0.5), L, world_nrm);
        vec3 specular = vec3(0.0, 0.0, 0.0);
        float attenuation = 1.0;
        // Specular

        if(dot(world_nrm, L) > 0)
        {
            specular    = compute_specular(vec3(0.1, 0.1, 0.1), 4, ray.direction, L, world_nrm);
        }
        // Apply the normal to the color
        out_colour = vec3(light_intensity * attenuation * (diffuse + specular));

    }

    imageStore(daxa_image2D(p.swapchain), index, vec4(out_colour,1));
}