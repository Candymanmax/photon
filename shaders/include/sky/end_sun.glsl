#if !defined INCLUDE_SKY_END_SUN
#define INCLUDE_SKY_END_SUN

#include "/include/misc/end_lighting_fix.glsl"

const float end_sun_angular_radius = SUN_ANGULAR_RADIUS * degree;
const float end_sun_solid_angle
    = tau * (1.0 - cos(end_sun_angular_radius));
const vec3 end_sun_color = vec3(END_SUN_R, END_SUN_G, END_SUN_B);
const float end_sun_flare_strength = 0.1;
const float end_sun_halo_strength = 1.0;
const float end_sun_halo_width = 1.0;

vec3 get_end_flash_direction() {
    vec3 direction = sun_dir;

#ifdef IS_IRIS
    float end_flash_position_length = length(endFlashPosition);

    if (end_flash_position_length > eps) {
        direction = mat3(gbufferModelViewInverse)
            * (endFlashPosition / end_flash_position_length);
    }
#endif

    float direction_length = length(direction);
    if (direction_length > eps
        && !isnan(direction_length)
        && !isinf(direction_length)) {
        direction /= direction_length;
    } else {
        direction = vec3(0.0, 1.0, 0.0);
    }

    return direction;
}

vec3 draw_end_sun_flare(vec3 ray_dir, vec3 sun_direction, float r) {
    vec3 tangent = abs(sun_direction.y) > 0.999
        ? vec3(1.0, 0.0, 0.0)
        : normalize(cross(vec3(0.0, 1.0, 0.0), sun_direction));
    vec3 bitangent = normalize(cross(tangent, sun_direction));
    mat3 rot = mat3(tangent, bitangent, sun_direction);
    vec2 q = ((ray_dir - sun_direction) * rot).xy;
    float q_length_squared = dot(q, q);
    float theta_angle = 0.0;

    if (q_length_squared > eps
        && !isnan(q_length_squared)
        && !isinf(q_length_squared)) {
        theta_angle = atan(q.y, q.x);
    }

    float theta = fract(
        linear_step(-pi, pi, theta_angle) + 0.015 * frameTimeCounter
        - 0.33 * r
    );

    float flare
        = texture(noisetex, vec2(theta, r - 0.025 * frameTimeCounter)).x;
    flare = clamp01(flare);
    flare = pow5(flare)
        * exp(-25.0 * max0(r - end_sun_angular_radius));

    return end_sun_color * rcp(end_sun_solid_angle)
        * end_sun_flare_strength * flare;
}

vec3 draw_end_sun_radiance(vec3 ray_dir, vec3 sun_direction) {
    float ray_length = length(ray_dir);
    if (ray_length <= eps || isnan(ray_length) || isinf(ray_length)) {
        return vec3(0.0);
    }
    ray_dir /= ray_length;

    float alignment = dot(ray_dir, sun_direction);
    if (isnan(alignment) || isinf(alignment)) {
        return vec3(0.0);
    }

    float r = fast_acos(clamp(alignment, -1.0, 1.0));
    if (isnan(r) || isinf(r)) {
        return vec3(0.0);
    }

    float halo = exp(
        -4.0 * sqr(r / (end_sun_angular_radius * end_sun_halo_width))
    );

    vec3 radiance = end_sun_color * rcp(end_sun_solid_angle)
        * end_sun_halo_strength * halo
        + draw_end_sun_flare(ray_dir, sun_direction, r);

    if (any(isnan(radiance)) || any(isinf(radiance))) {
        return vec3(0.0);
    }

    return max0(radiance);
}

vec3 draw_sun(vec3 ray_dir, vec3 sun_direction) {
    return draw_end_sun_radiance(ray_dir, sun_direction);
}

#endif
