#if !defined INCLUDE_MISC_END_FLASH
#define INCLUDE_MISC_END_FLASH

#if defined WORLD_END && defined IS_IRIS
uniform vec3 endFlashPosition;
uniform float endFlashIntensity;
#endif

float get_end_flash_fade() {
#if defined WORLD_END && defined IS_IRIS
    if (length(endFlashPosition) > eps) {
        float fade = smoothstep(0.1, 0.35, endFlashIntensity);
        return isnan(fade) || isinf(fade) ? 0.0 : fade;
    }
#endif

    return 0.0;
}

float get_end_flash_shadow_fade() {
#ifdef END_FLASH_SHADOWS
#if defined WORLD_END && defined IS_IRIS
    float fade = smoothstep(0.05, 0.28, endFlashIntensity);
    return isnan(fade) || isinf(fade) ? 0.0 : fade;
#else
    return 1.0;
#endif
#else
    return 1.0;
#endif
}

#endif
