#if !defined INCLUDE_SKY_CLOUDS_COMMON
#define INCLUDE_SKY_CLOUDS_COMMON

#include "/include/sky/atmosphere.glsl"
#include "/include/sky/clouds/constants.glsl"
#include "/include/utility/color.glsl"
#include "/include/utility/fast_math.glsl"
#include "/include/utility/geometry.glsl"
#include "/include/utility/phase_functions.glsl"
#include "/include/utility/random.glsl"
#include "/include/utility/sampling.glsl"

uniform float day_factor;

// ----

struct CloudsResult {
    vec4 scattering; // w = ambient scattering, for lightning flashes
    float transmittance;
    float apparent_distance;
};

const CloudsResult clouds_not_hit = CloudsResult(vec4(0.0), 1.0, 1e5);

// ----

// from https://iquilezles.org/articles/gradientnoise/
vec2 perlin_gradient(vec2 coord) {
    vec2 i = floor(coord);
    vec2 f = fract(coord);

    vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    vec2 du = 30.0 * f * f * (f * (f - 2.0) + 1.0);

    vec2 g0 = hash2(i + vec2(0.0, 0.0));
    vec2 g1 = hash2(i + vec2(1.0, 0.0));
    vec2 g2 = hash2(i + vec2(0.0, 1.0));
    vec2 g3 = hash2(i + vec2(1.0, 1.0));

    float v0 = dot(g0, f - vec2(0.0, 0.0));
    float v1 = dot(g1, f - vec2(1.0, 0.0));
    float v2 = dot(g2, f - vec2(0.0, 1.0));
    float v3 = dot(g3, f - vec2(1.0, 1.0));

    return vec2(
        g0 + u.x * (g1 - g0) + u.y * (g2 - g0) + u.x * u.y * (g0 - g1 - g2 + g3)
        + // d/dx
        du * (u.yx * (v0 - v1 - v2 + v3) + vec2(v1, v2) - v0) // d/dy
    );
}

vec2 curl2D(vec2 coord) {
    vec2 gradient = perlin_gradient(coord);
    return vec2(gradient.y, -gradient.x);
}

float clouds_phase_single(float cos_theta) { // Single scattering phase function
    float forwards_a = klein_nishina_phase(
        cos_theta,
        2600.0
    ); // this gives a nice glow very close to the sun
    float forwards_b = henyey_greenstein_phase(cos_theta, 0.8);

    return 0.8
        * max(forwards_a,
              forwards_b) // forwards lobe (max'ing them is completely
                          // nonsensical but it looks nice)
        + 0.2 * henyey_greenstein_phase(cos_theta, -0.2); // backwards lobe
}

float clouds_phase_multi(
    float cos_theta,
    vec3 g
) { // Multiple scattering phase function
    return 0.65 * henyey_greenstein_phase(cos_theta, g.x) // forwards lobe
        + 0.10 * henyey_greenstein_phase(cos_theta, g.y) // forwards peak
        + 0.25 * henyey_greenstein_phase(cos_theta, -g.z); // backwards lobe
}

float clouds_powder_effect(float density, float cos_theta) {
    float powder = pi * density / (density + 0.15);
    powder = mix(powder, 1.0, 0.8 * sqr(cos_theta * 0.5 + 0.5));

    return powder;
}

vec3 clouds_aerial_perspective(
    vec3 clouds_scattering,
    float clouds_transmittance,
    vec3 ray_origin,
    vec3 ray_end,
    vec3 ray_dir,
    vec3 clear_sky
) {
#ifdef CLOUDS_IRIDESCENCE
    float sun_alignment = dot(ray_dir, sun_dir);
    float sun_angle = fast_acos(clamp(sun_alignment, -1.0, 1.0));
    float sun_fade = day_factor
        * smoothstep(2.0 * degree, 5.0 * degree, sun_angle)
        * exp(-0.5 * sqr((sun_angle - 11.0 * degree) / (8.0 * degree)))
        * (1.0 - smoothstep(24.0 * degree, 31.0 * degree, sun_angle));
    float cloud_opacity = 1.0 - clamp01(clouds_transmittance);
    float thin_cloud_fade
        = smoothstep(0.02, 0.12, cloud_opacity)
        * (1.0 - smoothstep(0.55, 0.95, cloud_opacity));
    const float iridescence_droplet_diameter = 4.0;
    const vec3 iridescence_wavelengths = vec3(0.65, 0.53, 0.45);
    const float iridescence_size_variation = 0.08;
    vec3 iridescence_phase
        = tau * iridescence_droplet_diameter * sin(sun_angle)
        / iridescence_wavelengths;
    vec3 interference = 0.5 + 0.5 * cos(iridescence_phase);
    float coherence = exp(
        -0.5
        * sqr(
              tau * iridescence_droplet_diameter * sin(sun_angle)
              * iridescence_size_variation / 0.53
          )
    );
    float interference_mean = dot(interference, vec3(0.3333333));
    vec3 iridescence_color = clamp(
        vec3(1.0)
            + 1.4 * coherence * (interference - vec3(interference_mean)),
        0.25,
        1.75
    );
    float iridescence_strength
        = 0.14 * CLOUDS_IRIDESCENCE_STRENGTH * sun_fade
        * thin_cloud_fade;

    clouds_scattering = mix(
        clouds_scattering,
        clouds_scattering * iridescence_color,
        clamp01(iridescence_strength)
    );
#endif

    vec3 air_transmittance;

#if CLOUDS_AERIAL_PERSPECTIVE_BOOST != 0
    ray_end
        = mix(ray_origin, ray_end, float(1 << CLOUDS_AERIAL_PERSPECTIVE_BOOST));
#endif

    if (length_squared(ray_origin) < length_squared(ray_end)) {
        vec3 trans_0 = atmosphere_transmittance(ray_origin, ray_dir);
        vec3 trans_1 = atmosphere_transmittance(ray_end, ray_dir);

        air_transmittance = clamp01(trans_0 / trans_1);
    } else {
        vec3 trans_0 = atmosphere_transmittance(ray_origin, -ray_dir);
        vec3 trans_1 = atmosphere_transmittance(ray_end, -ray_dir);

        air_transmittance = clamp01(trans_1 / trans_0);
    }

    // Blend to rain color during rain
    clear_sky = mix(
        clear_sky,
        sky_color * rcp(tau),
        rainStrength * mix(1.0, 0.9, time_sunrise + time_sunset)
    );
    air_transmittance
        = mix(air_transmittance, vec3(air_transmittance.x), 0.8 * rainStrength);

    return mix(
        (1.0 - clouds_transmittance) * clear_sky,
        clouds_scattering,
        air_transmittance
    );
}

CloudsResult blend_layers(CloudsResult old, CloudsResult new) {
    bool new_in_front = new.apparent_distance < old.apparent_distance;

    vec4 scattering_behind = new_in_front ? old.scattering : new.scattering;
    vec4 scattering_in_front = new_in_front ? new.scattering : old.scattering;
    float transmittance_in_front
        = new_in_front ? new.transmittance : old.transmittance;

    return CloudsResult(
        scattering_in_front + transmittance_in_front * scattering_behind,
        old.transmittance * new.transmittance,
        min(old.apparent_distance, new.apparent_distance)
    );
}

#endif
