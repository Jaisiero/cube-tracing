#define DAXA_RAY_TRACING 1
#extension GL_EXT_ray_tracing : enable
#include <daxa/daxa.inl>

#include "shared.inl"
#include "mat.glsl"
#include "reservoir.glsl"

DAXA_DECL_PUSH_CONSTANT(PushConstant, p)

layout(location = 0) rayPayloadInEXT HIT_PAY_LOAD prd;
layout(location = 1) rayPayloadEXT bool is_shadowed;

layout(location = 3) callableDataEXT HIT_MAT_PAY_LOAD hit_call;
layout(location = 4) callableDataEXT HIT_SCATTER_PAY_LOAD call_scatter;
// #define DEBUG_NORMALS 1


// daxa_f32vec3 get_point_light_radiance(Ray ray, LIGHT light, _HIT_INFO hit) 
// {
//     vec3 L = vec3(0.0, 0.0, 0.0);
//     // Point light
//     if(light.type == 0)
//     {
//         vec3 lDir      = light.position - hit.world_hit;
//         light.distance  = length(lDir);
//         light.intensity = light.intensity / (light.distance * light.distance);
//         L              = normalize(lDir);
//     }
//     else  // Directional light
//     {
//         L = normalize(light.position);
//     }

//     daxa_f32vec3 radiance = daxa_f32vec3(0.0, 0.0, 0.0);
//     // TODO: Add light color to light struct
//     daxa_f32vec3 light_color = daxa_f32vec3(1.0, 1.0, 1.0);

//     radiance = light.intensity * dot(hit.world_nrm, L) * light_color;

//     return radiance;
// }

daxa_f32vec3 get_point_light_radiance(Ray ray, LIGHT light, _HIT_INFO hit)
{
    // 1. Get light parameters
    daxa_f32vec3 light_position = light.position;
    // TODO: Add light color to light struct
    daxa_f32vec3 light_color = daxa_f32vec3(1.0, 1.0, 1.0);
    daxa_f32 light_intensity = light.intensity;

    // 2. Get light direction
    daxa_f32vec3 light_direction = normalize(light_position - hit.world_hit);

    // 3. Get surface normal
    daxa_f32vec3 surface_normal = hit.world_nrm;

    // 3. Atenuation calculation
    daxa_f32 distance = length(light_position - hit.world_hit);
    daxa_f32 attenuation = 1.0 / (1.0 + 0.1 * distance + 0.01 * distance * distance);

    // 4. Radiance calculation
    daxa_f32vec3 light_radiance = light_color * light_intensity * attenuation / (4.0 * DAXA_PI * distance * distance) * max(0.0, dot(light_direction, surface_normal));


    return light_radiance;
} 

daxa_b32 is_light_visible(Ray ray, inout LIGHT light, _HIT_INFO hit) 
{

    vec3 L = vec3(0.0, 0.0, 0.0);
    // Point light
    if(light.type == 0)
    {
        vec3 lDir      = light.position - hit.world_hit;
        light.distance  = length(lDir);
        light.intensity = light.intensity / (light.distance * light.distance);
        L              = normalize(lDir);
    }
    else  // Directional light
    {
        L = normalize(light.position);
    }

    vec3 color = vec3(0.0, 0.0, 0.0);

    if(dot(hit.world_nrm, L) > 0) {
        daxa_f32 t_min   = 0.0001;
        daxa_f32 t_max   = light.distance;
        vec3  ray_origin = hit.world_hit;
        vec3  ray_dir = L;
        uint cull_mask = 0xff;
        uint  flags  = gl_RayFlagsTerminateOnFirstHitEXT | gl_RayFlagsOpaqueEXT | gl_RayFlagsSkipClosestHitShaderEXT;
        is_shadowed = true;

        traceRayEXT(
            daxa_accelerationStructureEXT(p.tlas),
            flags,  // rayFlags
            cull_mask,   // cullMask
            0,      // sbtRecordOffset
            0,      // sbtRecordStride
            1,      // missIndex
            ray_origin, // ray origin
            t_min,   // ray min range
            ray_dir, // ray direction
            t_max,   // ray max range
            1       // payload (location = 1)
        );
    }

    return !is_shadowed;
}

    // Use the reservoir to calculate the final radiance.
void calculate_reservoir_radiance(inout RESERVOIR reservoir, Ray ray, _HIT_INFO hit, inout daxa_f32 p_hat){

    if (is_reservoir_valid(reservoir))
    {
        LIGHT light = deref(p.light_buffer).lights[get_reservoir_light_index(reservoir)];
    
        // calculate the radiance of this light
        p_hat = is_light_visible(ray, light, hit) ? length(get_point_light_radiance(ray, light, hit)) : 0.0;
            
        // calculate the weight of this light
        reservoir.W_y = p_hat > 0.0 ? (reservoir.W_sum / reservoir.M) / p_hat : 0.0;
    }
}

void main()
{

    // Get world position from hit position
    vec3 world_pos = gl_WorldRayOriginEXT + gl_WorldRayDirectionEXT * gl_HitTEXT;

    // Get model matrix
    mat4 model = mat4(
        gl_ObjectToWorldEXT[0][0], gl_ObjectToWorldEXT[0][1], gl_ObjectToWorldEXT[0][2], 0,
        gl_ObjectToWorldEXT[0][1], gl_ObjectToWorldEXT[1][1], gl_ObjectToWorldEXT[1][2], 0,
        gl_ObjectToWorldEXT[2][0], gl_ObjectToWorldEXT[2][1], gl_ObjectToWorldEXT[2][2], 0,
        gl_ObjectToWorldEXT[3][0], gl_ObjectToWorldEXT[3][1], gl_ObjectToWorldEXT[3][2], 1.0);


    // Get first primitive index from instance id
    uint primitive_index = deref(p.instance_buffer).instances[gl_InstanceCustomIndexEXT].first_primitive_index;
    // Get actual primitive index from offset and primitive id
    uint actual_primitive_index = primitive_index + gl_PrimitiveID;

    // Get aabb from primitive
    Aabb aabb = deref(p.aabb_buffer).aabbs[actual_primitive_index];

    // Get center of aabb
    vec3 center = (aabb.minimum + aabb.maximum) * 0.5;

    // Transform center to world space
    center = (model * vec4(center, 1)).xyz;

    // Computing the normal at hit position
    vec3 world_nrm = normalize(world_pos - center);
    {
        vec3 absN = abs(world_nrm);
        daxa_f32 maxC = max(max(absN.x, absN.y), absN.z);
        world_nrm = (maxC == absN.x) ? vec3(sign(world_nrm.x), 0, 0) : (maxC == absN.y) ? vec3(0, sign(world_nrm.y), 0)
                                                                                        : vec3(0, 0, sign(world_nrm.z));
    }


    // Ray info 
    Ray ray = Ray(
        gl_WorldRayOriginEXT,
        gl_WorldRayDirectionEXT);

    
    // intersection info
    _HIT_INFO hit = _HIT_INFO(
        // NOTE: In order to avoid self intersection we need to offset the ray origin
        world_pos - world_nrm * AVOID_VOXEL_COLLAIDE, 
        world_nrm);

#if defined(DEBUG_NORMALS)
    prd.hit_value += world_nrm * 0.5 + 0.5;
#else
    // Get material index from primitive
    PRIMITIVE primitive = deref(p.primitives_buffer).primitives[actual_primitive_index];
    MATERIAL mat = deref(p.materials_buffer).materials[primitive.material_index];


    if(prd.depth > 1) {
        call_scatter.hit = hit.world_hit;
        call_scatter.nrm = hit.world_nrm;
        call_scatter.ray_dir = ray.direction;
        call_scatter.seed = prd.seed;
        call_scatter.scatter_dir = vec3(0.0);
        call_scatter.done = 0;
        call_scatter.mat_idx = primitive.material_index;

        // SCATTER
        switch (mat.type & MATERIAL_TYPE_MASK)
        {
        case MATERIAL_TYPE_METAL:
            executeCallableEXT(3, 4);
            break;
        case MATERIAL_TYPE_DIELECTRIC:
            executeCallableEXT(4, 4);
            break;
        case MATERIAL_TYPE_CONSTANT_MEDIUM:
            executeCallableEXT(5, 4);
            break;
        case MATERIAL_TYPE_LAMBERTIAN:
        default:
            executeCallableEXT(2, 4);
            break;
        }
        prd.seed = call_scatter.seed;
        
        if(call_scatter.done == 1) {
            prd.depth = 0;
        } else {
            prd.depth--;
            daxa_f32 t_min   = 0.0001;
            daxa_f32 t_max   = 100000.0;
            vec3  ray_origin = call_scatter.hit;
            vec3  ray_dir    = call_scatter.scatter_dir;
            uint cull_mask = 0xff;
            uint  flags  = gl_RayFlagsNoneEXT;

            traceRayEXT(
                daxa_accelerationStructureEXT(p.tlas),
                flags,         // rayFlags
                cull_mask,         // cullMask
                0,                 // sbtRecordOffset
                0,                 // sbtRecordStride
                0,                 // missIndex
                ray_origin,    // ray origin
                t_min,             // ray min range
                ray_dir, // ray direction
                t_max,             // ray max range
                0                  // payload (location = 0)
            );
        }
    }

    // // TEXTURES
    // {
    //     // NOTE: more texture types will be added later if they are needed
    //     if((mat.type & MATERIAL_TEXTURE_ON) != 0U) {
    //         hit_call.hit = (model * vec4(hit.world_hit, 1)).xyz;
    //         hit_call.nrm = hit.world_nrm;
    //         hit_call.texture_id = mat.texture_id;
    //         hit_call.sampler_id = mat.sampler_id;
    //         hit_call.hit_value = vec3(0.0);
    //         // executeCallableEXT(0, 3);
    //         out_color = hit_call.hit_value;
    //     } 
    //     else if((mat.type & MATERIAL_PERLIN_ON) != 0U) {
    //         hit_call.hit = (model * vec4(hit.world_hit, 1)).xyz;
    //         hit_call.nrm = hit.world_nrm;
    //         hit_call.texture_id = mat.texture_id;
    //         hit_call.sampler_id = mat.sampler_id;
    //         hit_call.hit_value = vec3(0.0);
    //         executeCallableEXT(1, 3);
    //         out_color = hit_call.hit_value;
    //     }
    // }

    // COLOR
    daxa_u32 light_count = deref(p.status_buffer).light_count;
    
    daxa_f32vec3 radiance = daxa_f32vec3(0.0);

#if RESERVOIR_ON == 1

    RESERVOIR reservoir;
    initialise_reservoir(reservoir);

    // TODO: M by parameter?
    const daxa_u32 M = 1;
    daxa_f32 p_hat = 0;

    daxa_f32 pdf = 1.0 / daxa_f32(light_count);

    for(daxa_u32 l = 0; l < M; l++) {
        daxa_u32 light_index = min(urnd_interval(prd.seed, 0, light_count), light_count - 1);

        LIGHT light = deref(p.light_buffer).lights[light_index];

        daxa_f32 w = 0.0f;

        if(light.intensity > 0.0) {
            p_hat = length(get_point_light_radiance(ray, light, hit));
            w = p_hat / pdf;
        }

        update_reservoir(reservoir, light_index, w, 1.0f, prd.seed);
    }

    calculate_reservoir_radiance(reservoir, ray, hit, p_hat);

    // Screen position
    daxa_u32 screen_pos = gl_LaunchIDEXT.x + gl_LaunchSizeEXT.x * gl_LaunchIDEXT.y;

    // Temporal reuse
    {

        RESERVOIR temporal_reservoir;
        initialise_reservoir(temporal_reservoir);

        daxa_f32vec2 uv = (daxa_f32vec2(gl_LaunchIDEXT.xy) + 0.5) / daxa_f32vec2(gl_LaunchSizeEXT.xy);
        
        //reproject using the motion vectors.
        daxa_i32vec2 screen_pos_previous_vec = daxa_i32vec2((uv - deref(p.velocity_buffer).velocities[screen_pos]) * gl_LaunchSizeEXT.xy);

        daxa_u32 screen_pos_previous = screen_pos_previous_vec.y * gl_LaunchSizeEXT.x + screen_pos_previous_vec.x;

        daxa_u32 max_screen_pos = gl_LaunchSizeEXT.x * gl_LaunchSizeEXT.y - 1;

        screen_pos_previous = min(max_screen_pos, screen_pos_previous);

        // daxa_u32 screen_pos_previous = screen_pos;
            
        // Normal from previous frame
        daxa_f32vec3 normal_previous = normalize(deref(p.previous_normal_buffer).normals[screen_pos_previous].xyz);
            
        // Reservoir from previous frame
        RESERVOIR reservoir_previous = deref(p.previous_reservoir_buffer).reservoirs[screen_pos_previous];
        
        //restrict influence from past samples.
        reservoir_previous.M = min(INFLUENCE_FROM_THE_PAST_THRESHOLD * reservoir.M, reservoir_previous.M);

        //some simple rejection based on normals' divergence, can be improved
        bool valid_history = dot(normal_previous, hit.world_nrm) >= 0.99;
        
        if (valid_history)
        {
            //add current reservoir sample
            update_reservoir(temporal_reservoir, get_reservoir_light_index(reservoir), p_hat * reservoir.W_y * reservoir.M, reservoir.M, prd.seed);

            daxa_f32 p_hat_prev = length(get_point_light_radiance(ray, deref(p.light_buffer).lights[get_reservoir_light_index(reservoir_previous)], hit)); 

            //add sample from previous frame
            update_reservoir(temporal_reservoir, get_reservoir_light_index(reservoir_previous), p_hat_prev * reservoir_previous.W_y * reservoir_previous.M, reservoir_previous.M, prd.seed);
        
            p_hat = is_reservoir_valid(temporal_reservoir) ?
                    length(get_point_light_radiance(ray, deref(p.light_buffer).lights[get_reservoir_light_index(temporal_reservoir)], hit)) : 0.0;
        
            //calculate weight of the selected lights                
            temporal_reservoir.W_y = p_hat > 0.0 ? (temporal_reservoir.W_sum / temporal_reservoir.M) / p_hat : 0.0;
        
            reservoir = temporal_reservoir;
        }


        // TODO: this is not correct, velocity should be calculated with reprojection
        // Store velocity
        // deref(p.velocity_buffer).velocities[screen_pos] = daxa_i32vec2(gl_LaunchIDEXT.xy - gl_LaunchSizeEXT.xy * gl_WorldRayDirectionEXT.xy);

        // Store normal
        deref(p.normal_buffer).normals[screen_pos] = daxa_f32vec4(hit.world_nrm, gl_HitTEXT);

        // Store the reservoir
        deref(p.reservoir_buffer).reservoirs[screen_pos] = reservoir;
    }

    // Spacial reuse
    {
        RESERVOIR spacial_reservoir;
        initialise_reservoir(spacial_reservoir);
        
        //add sample from previous frame
        update_reservoir(spacial_reservoir, get_reservoir_light_index(reservoir), p_hat * reservoir.W_y * reservoir.M, reservoir.M, prd.seed);
    
        daxa_f32 p_hat_temp = is_reservoir_valid(spacial_reservoir) ?
                length(get_point_light_radiance(ray, deref(p.light_buffer).lights[get_reservoir_light_index(spacial_reservoir)], hit)) : 0.0;
    
        //calculate weight of the selected lights                
        spacial_reservoir.W_y = p_hat_temp > 0.0 ? (spacial_reservoir.W_sum / spacial_reservoir.M) / p_hat : 0.0;

        RESERVOIR neighbor_reservoir;

        for (int i = 0; i < NUM_OF_NEIGHBORS; i++)
        { 
            daxa_f32vec2 offset = 2.0 * daxa_f32vec2(rnd(prd.seed), rnd(prd.seed)) - 1;
        
            offset.x = gl_LaunchIDEXT.x + int(offset.x * NEIGHBORS_RADIUS);
            offset.y = gl_LaunchIDEXT.y + int(offset.y * NEIGHBORS_RADIUS);
        
            offset.x = max(0, min(gl_LaunchSizeEXT.x - 1, offset.x));
            offset.y = max(0, min(gl_LaunchSizeEXT.y - 1, offset.y));

            daxa_u32vec2 offset_u32 = daxa_u32vec2(offset);

            daxa_u32 offset_u32_linear = offset_u32.y * gl_LaunchSizeEXT.x + offset_u32.x;
        
            // TODO: Should it be used depth buffer?
            // daxa_f32 neighbor_depth_linear = linearise_depth(deref(p.depth_buffer).depth[daxa_f32vec2(offset)].x);

            daxa_f32 neighbor_hit_dist = deref(p.previous_normal_buffer).normals[offset_u32_linear].w;
            
            // TODO: Adjust dist threshold dynamically
            if (  
                // (neighbor_depth_linear > 1.1f * depth_linear || neighbor_depth_linear < 0.9f * depth_linear)   ||
                (neighbor_hit_dist > VOXEL_EXTENT + gl_HitTEXT || neighbor_hit_dist < gl_HitTEXT - VOXEL_EXTENT)   ||
                dot(hit.world_nrm, deref(p.previous_normal_buffer).normals[offset_u32_linear].xyz) < 0.906)
            {
                // skip this neighbour sample if not suitable
                continue;
            }

        
            neighbor_reservoir = deref(p.previous_reservoir_buffer).reservoirs[offset_u32_linear];
        
            p_hat = is_reservoir_valid(neighbor_reservoir) ?
                    length(get_point_light_radiance(ray, deref(p.light_buffer).lights[get_reservoir_light_index(neighbor_reservoir)], hit)) : 0;
            
            update_reservoir(spacial_reservoir, get_reservoir_light_index(neighbor_reservoir), p_hat * neighbor_reservoir.W_y * neighbor_reservoir.M, neighbor_reservoir.M, prd.seed);
        }  
        
        p_hat = is_reservoir_valid(spacial_reservoir) ? length(get_point_light_radiance(ray, deref(p.light_buffer).lights[get_reservoir_light_index(spacial_reservoir)], hit)) : 0;
        
        spacial_reservoir.W_y = p_hat > 0.0 ? (spacial_reservoir.W_sum / spacial_reservoir.M) / p_hat : 0.0;  
        
        reservoir = spacial_reservoir;
    }

    // Get the light from the reservoir
    LIGHT light = deref(p.light_buffer).lights[get_reservoir_light_index(reservoir)];

    // Add light radiance
    radiance += get_point_light_radiance(ray, light, hit) * reservoir.W_y;

    // diffuse color   
    prd.hit_value += radiance * mat.diffuse;

    // Add emission
    // prd.hit_value += mat.emission;

#else

    for(daxa_u32 l = 0; l < light_count; l++) {

        LIGHT light = deref(p.light_buffer).lights[l];

        radiance += is_light_visible(ray, light, hit) ? get_point_light_radiance(ray, light, hit) : daxa_f32vec3(0.0);
    }

    prd.hit_value += radiance * mat.diffuse;


#endif // RESERVOIR_ON


#endif
}