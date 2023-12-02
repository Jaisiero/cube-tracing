#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#extension GL_EXT_ray_query : enable
// TODO: Debugging
#extension GL_EXT_debug_printf : enable
#include <daxa/daxa.inl>

#include "shared.inl"
#include "mat.glsl"
#include "prng.glsl"

DAXA_DECL_PUSH_CONSTANT(PushConstant, p)

// Ray-AABB intersection
float hit_aabb(const Aabb aabb, const Ray r)
{
    // avoid division by 0
    vec3 inv_dir = 1.0 / (r.direction + 1e-6);
    vec3 tbot = inv_dir * (aabb.minimum - r.origin);
    vec3 ttop = inv_dir * (aabb.maximum - r.origin);
    vec3 tmin = min(ttop, tbot);
    vec3 tmax = max(ttop, tbot);
    float t0 = max(tmin.x, max(tmin.y, tmin.z));
    float t1 = min(tmax.x, min(tmax.y, tmax.z));
    return t1 > max(t0, 0.0) ? t0 : -1.0;
}

// const vec3 LIGHT_POSITION = vec3(5.0, 10.0, -5.0);
// Vector toward the light
// float light_intensity = 100.0;
// float light_distance  = 10.0;
// uint light_type      = 0;  // 0: point light, 1: directional light

daxa_b32 ray_color_hit(inout Ray ray, out float t_hit, int instance_id, int primitive_id, inout vec3 attenuation, inout vec3 out_color, light_info light, LCG lcg) {

    // float t_hit = -1.0f;
    vec3  L;

    mat4 transform = deref(p.instance_buffer).instances[instance_id].transform;
    transform = transpose(transform);

    mat4 inv_transform = inverse(transform);

    // Get first primitive index from instance id
    uint primitive_index = deref(p.instance_buffer).instances[instance_id].first_primitive_index;

    // Get actual primitive index from offset and primitive id
    uint actual_primitive_index = primitive_index + primitive_id;

    // Get center position from transform
    vec3 aabb_center = deref(p.primitives_buffer).primitives[actual_primitive_index].center;

    // get primitive material index
    daxa_u32 material_index = deref(p.primitives_buffer).primitives[actual_primitive_index].material_index;
    
    // get material
    MATERIAL mat = deref(p.materials_buffer).materials[material_index];

    // vec3 half_extent = get_half_extent(level_index);

    vec3 half_extent = vec3(HALF_EXTENT);

    // Get aabb from center_pos and transform
    Aabb aabb;
    aabb.minimum = aabb_center - half_extent;
    aabb.maximum =  aabb_center + half_extent;
    aabb.minimum = (transform * vec4(aabb.minimum, 1)).xyz;
    aabb.maximum = (transform * vec4(aabb.maximum, 1)).xyz;

    // Check if ray hits aabb
    t_hit = hit_aabb(aabb, ray);

    // TODO: Check if we can remove this
    if(t_hit < 0.0f) {
        // No hit
        // attenuation = out_color == vec3(0.0, 0.0, 0.0) ? vec3(1.0) : vec3(0.01); 
        out_color += background_color(ray.direction) * attenuation;
        // out_color = vec3(0.0, 0.0, 0.0);
        return false;
    }

    // hit point in world space
    vec3 world_pos = ray.origin + ray.direction * t_hit;

    // t += t_hit;
    
    // Get center position of the aabb in world space
    vec3 center_pos = (transform * vec4(aabb_center, 1)).xyz;

    // Computing the normal at hit position
    vec3 world_nrm = normalize(world_pos-center_pos);


    // TODO: This is kinda killing light reflection
// Credits: https://github.com/nvpro-samples/vk_raytracing_tutorial_KHR/blob/master/ray_tracing_intersection/shaders/raytrace2.rchit
    //Computing the normal for a cube
    {
        vec3  absN = abs(world_nrm);
        float maxC = max(max(absN.x, absN.y), absN.z);
        world_nrm = (maxC == absN.x) ? vec3(sign(world_nrm.x), 0, 0) :
            (maxC == absN.y) ? vec3(0, sign(world_nrm.y), 0) :
            (maxC == absN.z) ? vec3(0, 0, sign(world_nrm.z)) :
                                world_nrm;
    }

    // Point light
    if(light.type == 0)
    {
        vec3 lDir      = light.position - world_pos;
        light.distance  = length(lDir);
        light.intensity = light.intensity / (light.distance * light.distance);
        L              = normalize(lDir);
    }
    else  // Directional light
    {
        L = normalize(light.position);
    }

    // Diffuse
    vec3 diffuse = compute_diffuse(mat, L, world_nrm);
    vec3 specular = vec3(0.0, 0.0, 0.0);
    // Specular

    if(dot(world_nrm, L) > 0)
    {
        specular = compute_specular(mat, ray.direction, L, world_nrm);
    }

    // Apply the normal to the color
    out_color += vec3(light.intensity * attenuation * (diffuse + specular));


    // Attenuation based on specular
    attenuation *= mat.specular;

    vec3 scatter_direction;
    
    if(scatter(mat, ray.direction, world_nrm, lcg, scatter_direction) == false) {
        // out_color = vec3(0.0, 0.0, 0.0);
        // No scatter
        return false;
    }

    ray = Ray((world_pos + (DELTA_RAY * scatter_direction)) , scatter_direction);

    return true;
}

vec3 ray_color(Ray ray, int depth, ivec2 index, LCG lcg)
{
    vec3 out_color = vec3(0.0, 0.0, 0.0);
    if(depth <= 0) return out_color;

    // Ray query setup
    float t = 0.0f;
    float t_hit = -1.0f;
    uint cull_mask = 0xff;
    float t_min = 0.0001f;
    float t_max = 1000.0f;
    rayQueryEXT ray_query;

    // TODO: Configurable by buffer
    const vec3 LIGHT_POSITION = vec3(0.0, 10.0, -5.0);
    // Vector toward the light
    const float light_intensity = 100.0;
    const float light_distance  = 50.0;
    const uint light_type      = 0;  // 0: point light, 1: directional light

    light_info light;
    light.position = LIGHT_POSITION;
    light.intensity = light_intensity;
    light.distance = light_distance;
    light.type = light_type;
    
    // light setup
    vec3 attenuation = vec3(1.0);

    int instance_id = -1;
    int primitive_id = -1;

    for(int i = 0; i < depth; i++) {

        t_hit = -1.0f;

        rayQueryInitializeEXT(ray_query, daxa_accelerationStructureEXT(p.tlas),
                            gl_RayFlagsOpaqueEXT   | gl_RayFlagsTerminateOnFirstHitEXT,
                            // gl_RayFlagsTerminateOnFirstHitEXT,
                            // gl_RayFlagsOpaqueEXT,
                            cull_mask, ray.origin, t_min, ray.direction, t_max);
                            
        while(rayQueryProceedEXT(ray_query)) {
            uint type = rayQueryGetIntersectionTypeEXT(ray_query, false);
            if(type ==
                gl_RayQueryCandidateIntersectionAABBEXT) {
                rayQueryGenerateIntersectionEXT(ray_query, t);
                // rayQueryTerminateEXT(ray_query);
            }
        }

        uint type_commited = rayQueryGetIntersectionTypeEXT(ray_query, true);

        if(type_commited ==
            gl_RayQueryCommittedIntersectionGeneratedEXT)
        {
            
            // t_hit = rayQueryGetIntersectionTEXT(ray_query, true);

            // instance_id = -1;
            // primitive_id = -1;

            // Ray ray2 = ray;


            // NOTE: Debugging
            // write t_hit to hit_distance buffer element from index[x, y] in hit distance buffer
            // deref(p.hit_distance_buffer).hit_distances[index.x + index.y * p.size.x].distance = t_hit;            
            
            // get instance id
            instance_id = rayQueryGetIntersectionInstanceCustomIndexEXT(ray_query, true);

            // Get primitive id
            primitive_id = rayQueryGetIntersectionPrimitiveIndexEXT(ray_query, true);

            if(ray_color_hit(ray, t_hit, instance_id, primitive_id, attenuation, out_color, light, lcg) == false) {
                // No hit
                // attenuation = out_color == vec3(0.0, 0.0, 0.0) ? vec3(1.0) : vec3(0.01); 
                // out_color += background_color(ray.direction) * attenuation;
                return out_color;
            }
            
            // if(i == 1) {
            //     HIT_DISTANCE hit_distance = HIT_DISTANCE(t_hit, ray2.origin, ray2.direction, instance_id, primitive_id);
            //     deref(p.hit_distance_buffer).hit_distances[index.x + index.y * p.size.x] = hit_distance;
            // }

        } else {
            // No hit
            // if out_color is (0,0,0) then we are in the background primary ray otherwise we are in a shadow ray
            attenuation = out_color == vec3(0.0, 0.0, 0.0) ? vec3(1.0) : vec3(0.01);
            out_color += background_color(ray.direction) * attenuation;
            return out_color;
        }
    };

    return out_color;
}

layout(local_size_x = 8, local_size_y = 8) in;
void main()
{
    const ivec2 index = ivec2(gl_GlobalInvocationID.xy);
    if (index.x >= p.size.x || index.y >= p.size.y)
    {
        return;
    }
    uvec2 launch_size = gl_NumWorkGroups.xy * 8;

    // Color output
    vec3 out_color = vec3(0.0, 0.0, 0.0);

    // Ray setup
    Ray ray;

    // Camera setup
    daxa_f32mat4x4 inv_view = deref(p.camera_buffer).inv_view;
    daxa_f32mat4x4 inv_proj = deref(p.camera_buffer).inv_proj;
    // daxa_f32 LOD_distance = deref(p.camera_buffer).LOD_distance;

    const vec2 pixel_center = vec2(index) + vec2(0.5);
    const vec2 inv_UV = pixel_center / vec2(launch_size);
    vec2 d = inv_UV * 2.0 - 1.0;
    
    // DEBUGGING
    deref(p.hit_distance_buffer).hit_distances[index.x + index.y * p.size.x].distance = -1.0f;

    LCG lcg;
    daxa_u32 frame_number = deref(p.camera_buffer).frame_number;
    daxa_u32 seedX = index.x;
    daxa_u32 seedY = index.y;

    initLCG(lcg, frame_number, seedX, seedY);

    daxa_f32vec4 origin = inv_view * vec4(0,0,0,1);

#if SAMPLES_PER_PIXEL == 1

	vec4 target = inv_proj * vec4(d.x, d.y, 1, 1) ;
	vec4 direction = inv_view * vec4(normalize(target.xyz), 0) ;
    
    ray.origin = origin.xyz;
    ray.direction = direction.xyz;

    // 1 sample per pixel
    out_color = ray_color(ray, MAX_DEPTH, index, lcg);
#else

    // Multiple samples per pixel (anti-aliasing) 
    // Primary ray
    for(int i = 0; i < SAMPLES_PER_PIXEL; i++)
    {
        // Some random sampling for anti-aliasing
        vec2 df = d + vec2(randomInRangeLCG(lcg, 0.0f, SAMPLE_OFFSET), randomInRangeLCG(lcg, 0.0f, SAMPLE_OFFSET));
        vec4 target = inv_proj * vec4(df.x, df.y, 1, 1) ;
        vec4 direction = inv_view * vec4(normalize(target.xyz), 0) ;
        
        ray.origin = origin.xyz;
        ray.direction = direction.xyz;

        vec3 partial_out_color = ray_color(ray, MAX_DEPTH, index, lcg);

        out_color += partial_out_color / SAMPLES_PER_PIXEL;
    }
    clamp(out_color, 0.0, 0.99999999);

#endif

    // NOTE: We are not using gamma correction because we suspect that swapchain is already in sRGB    
    // imageStore(daxa_image2D(p.swapchain), index, fromLinear(vec4(out_color,1)));
    // imageStore(daxa_image2D(p.swapchain), index, linear_to_ gamma(vec4(out_color,1)));
    imageStore(daxa_image2D(p.swapchain), index, vec4(out_color,1));
}