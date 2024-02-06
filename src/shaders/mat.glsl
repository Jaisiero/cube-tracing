// mat.glsl
#ifndef MATERIAL_GLSL
#define MATERIAL_GLSL
#include <daxa/daxa.inl>
#include "shared.inl"
#include "prng.glsl"


daxa_f32vec3 get_diffuse_BRDF(MATERIAL mat, daxa_f32vec3 normal, daxa_f32vec3 light_dir, daxa_f32vec3 view_dir) {
#if (COSINE_HEMISPHERE_SAMPLING == 1)
    daxa_f32 cos_theta = dot(normal, light_dir);
    return mat.diffuse * cos_theta * INV_DAXA_PI;
#else     
    return mat.diffuse * INV_DAXA_PI;
#endif
}


daxa_f32vec3 get_metal_BRDF(MATERIAL mat, daxa_f32vec3 normal, daxa_f32vec3 light_dir, daxa_f32vec3 view_dir) {
    daxa_f32vec3 half_dir = normalize(light_dir + view_dir);
    daxa_f32vec3 fresnel = min(mat.roughness, 1.0) + (daxa_f32vec3(1.0) - min(mat.roughness, 1.0)) * pow(1.0 - dot(light_dir, half_dir), 5.0);
    daxa_f32vec3 diffuse = (daxa_f32vec3(1.0) - fresnel) * (daxa_f32vec3(1.0) - mat.specular);
    daxa_f32vec3 specular = fresnel * mat.specular;
    return (diffuse + specular) * INV_DAXA_PI;
}

daxa_f32vec3 get_dialectric_BRDF(MATERIAL mat, daxa_f32vec3 normal, daxa_f32vec3 light_dir, daxa_f32vec3 view_dir) {
    // Coeficiente de Fresnel utilizando el modelo de Fresnel-Schlick
    daxa_f32vec3 fresnel = mat.roughness + (daxa_f32vec3(1.0) - mat.roughness) * pow(1.0 - dot(light_dir, view_dir), 5.0);

    // Término de reflexión especular
    daxa_f32vec3 specular = fresnel;

    // Término de reflexión difusa (Lambertian)
    daxa_f32vec3 diffuse = (daxa_f32vec3(1.0) - fresnel) * (mat.diffuse *  INV_DAXA_PI);

    // Suma ponderada de los términos difusos y especulares
    return diffuse + specular;
}


daxa_f32vec3 get_constant_medium_BRDF(MATERIAL mat, daxa_f32vec3 normal, daxa_f32vec3 light_dir, daxa_f32vec3 view_dir) {
    return mat.diffuse * INV_DAXA_4PI;
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

daxa_f32vec3 day_light_background_color(daxa_f32vec3 dir)
{
    daxa_f32vec3 unit_dir = normalize(dir);
    daxa_f32 t = 0.5 * (unit_dir.y + 1.0);
    return mix(daxa_f32vec3(1.0, 1.0, 1.0), daxa_f32vec3(0.5, 0.7, 1.0), t);
}

daxa_f32vec3 night_light_background_color(daxa_f32vec3 dir)
{
    daxa_f32vec3 unit_dir = normalize(dir);
    daxa_f32 t = 0.5 * (unit_dir.y + 1.0);
    return mix(daxa_f32vec3(0.0, 0.0, 0.0), daxa_f32vec3(0.2, 0.2, 0.5), t);
}

daxa_f32vec3 sunset_background_color(daxa_f32vec3 dir) {
    daxa_f32vec3 unit_dir = normalize(dir);
    daxa_f32 t = 0.5 * (unit_dir.y + 1.0);
    return mix(daxa_f32vec3(0.0, 0.0, 0.0), daxa_f32vec3(1.0, 0.4, 0.0), t);
}

daxa_f32vec3 sunrise_background_color(daxa_f32vec3 dir) {
    daxa_f32vec3 unit_dir = normalize(dir);
    daxa_f32 t = 0.5 * (unit_dir.y + 1.0);
    return mix(daxa_f32vec3(0.0, 0.0, 0.0), daxa_f32vec3(0.8, 0.4, 0.0), t);
}

vec3 calculate_sky_color(float time, daxa_b32 is_afternoon, daxa_f32vec3 dir) {
    float night_duration = 0.5;  // 0.5 
    float sunrise_duration = 0.10; // 0.10
    float full_daylight_transition = 0.10; // 0.10
    float full_night_transition = 0.10; // 0.10

    float sunrise_end = night_duration + sunrise_duration; // 0.60
    float sunrise_to_daylight = sunrise_end + full_daylight_transition; // 0.70
    float zenith_transition = 1.0 - sunrise_to_daylight; // 0.30

    // Full day light starts at 0.70 and ends at 0.70 (0.30 + 0.30 = 0.6)
    float daylight_end = 1.0 - zenith_transition; // 0.70
    float sunset_start = 1.0 - zenith_transition - sunrise_duration; // 0.55
    float sunset_end = 1.0 - zenith_transition - sunrise_duration - full_night_transition; // 0.50

    float t = time;

    if(is_afternoon) {
        // Night
        if (t < night_duration) {
            return night_light_background_color(dir);
        }
        // Sunrise to sunrise_end
        else if (t < sunrise_end) {
            // time transitioning from night_duration to sunrise_end clamp [0, 1]
            float transitionTime = (t - night_duration) / (sunrise_end - night_duration);
            return mix(night_light_background_color(dir), sunrise_background_color(dir), t);
        }
        // Sunrise to daylight
        else if (t < sunrise_to_daylight) {
            // time transitioning from sunrise_end to sunrise_to_daylight
            float transitionTime = (t - sunrise_end) / (sunrise_to_daylight - sunrise_end);
            return mix(sunrise_background_color(dir), sunset_background_color(dir), t);
        }
        // Full Daylight
        else {
            // time transitioning from sunrise_to_daylight to 1.0
            float transitionTime = (t - sunrise_to_daylight) / (1.0 - sunrise_to_daylight);
            return mix(sunset_background_color(dir), day_light_background_color(dir), t);
        }
    }
    else {
         // Full daylight
        if (t > daylight_end) {
            // time transitioning backwards from 1.0 to daylight_end
            float transitionTime = (t - daylight_end) / (1.0 - daylight_end);
            return mix(sunrise_background_color(dir), day_light_background_color(dir), t);
        }
        // daylight to sunset
        else if (t > sunset_start) {
            // time transitioning from daylight_end to sunset_start
            float transitionTime = (t - daylight_end) / (daylight_end - sunset_start);
            return mix(sunset_background_color(dir), sunrise_background_color(dir), t);
        }
        // sunset to night
        else if(t > sunset_end) {
            // time transitioning from sunset_start to sunset_end
            float transitionTime = (t - sunset_start) / (sunset_start - sunset_end);
            return mix(night_light_background_color(dir), sunset_background_color(dir), t);
        }
        // Night again
        else {
            return night_light_background_color(dir);
        }
    }
}

#if(DEBUG_NORMALS == 1)
daxa_f32vec3 normal_to_color(daxa_f32vec3 normal)
{
    return (normal + daxa_f32vec3(1.0)) * 0.5;
}
#endif



daxa_f32vec3 hit_get_world_hit(Ray ray, HIT_INFO hit) {
    return ray.origin + ray.direction * hit.hit_distance + (VOXEL_EXTENT * 0.5) * hit.world_nrm;
}

// Function to calculate transmittance for a constant medium
daxa_f32 calculateTransmittance(daxa_f32 dissolve, daxa_f32 distance) {
    return exp(-dissolve * distance);
}

// Function to determine hit inside or outside for a constant medium
daxa_b32 material_transmission(Ray ray, inout HIT_INFO hit, daxa_f32 dissolve, inout uint seed) {

    // Calculate the thickness of the medium (if hit inside the volume, thickness is the distance from ray origin to hit distance, otherwise it is the distance from hit distance to the exit distance)
    daxa_f32 thickness = hit.hit_distance != hit.exit_distance ?  hit.exit_distance - hit.hit_distance :
        length(hit.world_hit - ray.origin);
    // daxa_f32 thickness = 0.125f;
    

    // Fine-tune parameters for controlling the probability
    // daxa_f32 base = 0.1;   // Base value for the exponential function
    daxa_f32 exponentScale = 20.0f;  // Exponent value for the exponential function
    // exponentScale *= length(ray.origin - hit.world_hit);  // Scale exponent by distance from camera to hit point (further away = less likely to hit

    // Random value between [0, 1]
    daxa_f32 random_value = randomInRangeLCG(seed, 0.0, 1.0);

    // Calculate the probability of impact with an exponential relationship based on dissolve
    float probability = 1.0f - exp(-dissolve * thickness * exponentScale);

    // DEBUG
    // hit.primitive_center.x = thickness;
    // hit.primitive_center.y = probability;
    // hit.primitive_center.z = random_value;

    // Check if the random value is below the transmittance probability
    if (random_value < probability) {
        // Hit occurred inside the volume, set thit within the range [tmin, tmax]
        hit.hit_distance = hit.hit_distance + random_value * thickness;
        hit.world_hit = hit_get_world_hit(ray, hit);
        return true;
    } else {
        hit.hit_distance = -1.0f;  // No hit inside the volume
        return false;
    }
}

#endif // MATERIAL_GLSL