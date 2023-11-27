#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#extension GL_EXT_ray_query : enable
#include <daxa/daxa.inl>

#include "shared.inl"

DAXA_DECL_PUSH_CONSTANT(PushConstant, p)

// Credit: https://gamedev.stackexchange.com/questions/92015/optimized-linear-to-srgb-glsl
vec4 fromLinear(vec4 linearRGB)
{
    bvec4 cutoff = lessThan(linearRGB, vec4(0.0031308));
    vec4 higher = vec4(1.055)*pow(linearRGB, vec4(1.0/2.4)) - vec4(0.055);
    vec4 lower = linearRGB * vec4(12.92);

    return mix(higher, lower, cutoff);
}

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

    rayQueryEXT ray_query;
    rayQueryInitializeEXT(ray_query, daxa_accelerationStructureEXT(p.tlas),
                        gl_RayFlagsOpaqueEXT,
                        cull_mask, origin.xyz, t_min, direction.xyz, t_max);

    while(rayQueryProceedEXT(ray_query)) {
        uint type = rayQueryGetIntersectionTypeEXT(ray_query, false);
        if(type ==
            gl_RayQueryCandidateIntersectionAABBEXT) {
            rayQueryGenerateIntersectionEXT(ray_query, t_max);
        }
    }

    vec3 out_colour = vec3(0.0, 0.0, 0.0);
    uint type = rayQueryGetIntersectionTypeEXT(ray_query, true);

    if(type ==
        gl_RayQueryCommittedIntersectionGeneratedEXT)
    {
        vec3 hit = origin.xyz + direction.xyz * t_max;

        // get instance id
        int instance_id = rayQueryGetIntersectionInstanceCustomIndexEXT(ray_query, true);

        // get instance colour
        out_colour = deref(p.instance_buffer).instances[instance_id].color;

        // interpolate colour
        // out_colour = vec3(
        //     (float(index.x) + 0.5f) / float(p.size.x),
        //     (float(index.y) + 0.5f) / float(p.size.y),
        //     abs(sin(float(index.x) * float(index.y)))
        // );

    }

    imageStore(daxa_image2D(p.swapchain), index, fromLinear(vec4(out_colour,1)));
}