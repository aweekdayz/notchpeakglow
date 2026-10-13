#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float2 resolution;
    float2 notchCenter;
    float2 notchSize;
    float time;
    float intensity;
    float modeMix;
    float hdrBoost;
    float pulseHz;
    float glowScale;
    float mediumAlpha;
    float warningMix;
    float redGain;
    float redScale;
};

struct FragmentInput { float4 position [[position]]; };

vertex FragmentInput vertexShader(uint vid [[vertex_id]]) {
    float2 pos[6] = {
        float2(-1,-1), float2(1,-1), float2(1,1),
        float2(-1,-1), float2(1,1), float2(-1,1)
    };
    FragmentInput out;
    out.position = float4(pos[vid], 0, 1);
    return out;
}

// The actual notch silhouette anchors the light. Window size never stretches it.
float roundedBox(float2 p, float2 halfSize, float radius) {
    float2 q = abs(p) - halfSize + radius;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

fragment float4 fragmentShader(FragmentInput in [[stage_in]],
                               constant Uniforms &u [[buffer(0)]]) {
    float2 p = in.position.xy - u.notchCenter;
    float radius = min(u.notchSize.y * 0.40, 18.0);
    float sd = roundedBox(p, u.notchSize * 0.5, radius);
    float outside = smoothstep(-0.5, 1.0, sd);
    float scale = max(0.5, u.glowScale);
    float pulse = 0.5 + 0.5 * sin(6.283185 * u.pulseHz * u.time);
    float warning = clamp(u.warningMix, 0.0, 1.0);
    float spread = 19.0 * scale * mix(1.0, clamp(u.redScale, 0.6, 1.8), warning);

    // A fine illuminated edge sits within two wider, softer light layers.
    float distance = max(sd, 0.0);
    float rim = exp(-distance * distance / (2.0 * pow(2.2 * scale, 2.0)));
    float halo = exp(-distance * distance / (2.0 * spread * spread));
    float atmosphere = exp(-distance * distance / (2.0 * pow(spread * 1.9, 2.0)));

    // Slow traveling ribbons in a curated palette; no hue wheel or rotating rainbow.
    float x = p.x / max(u.notchSize.x, 1.0);
    float wave = 0.5 + 0.5 * sin(x * 4.2 + u.time * 0.30
                               + sin(p.y / 48.0 - u.time * 0.19) * 0.6);
    float ribbon = 0.5 + 0.5 * sin(x * 6.0 - u.time * 0.23 + 1.5);
    float3 cyan = float3(0.25, 0.78, 0.96);
    float3 violet = float3(0.55, 0.36, 0.92);
    float3 pink = float3(0.94, 0.42, 0.69);
    float3 aurora = mix(cyan, violet, smoothstep(0.1, 0.9, wave));
    aurora = mix(aurora, pink, pow(ribbon, 3.0) * 0.36);
    float3 ice = mix(float3(0.24, 0.48, 0.98), float3(0.48, 0.79, 1.0), wave * 0.45);
    float3 color = mix(aurora, ice, u.modeMix);

    // Temperature is a calm, persistent warm tint, not random red flashes.
    float3 warm = mix(float3(1.0, 0.53, 0.22), float3(0.96, 0.28, 0.32), wave * 0.35);
    color = mix(color, warm, warning * 0.85);
    color = mix(color, float3(0.82, 0.90, 1.0), rim * 0.22 * (1.0 - warning));

    float envelope = 0.18 * rim + 0.55 * halo + 0.12 * atmosphere;
    float alpha = envelope * mix(u.mediumAlpha, 0.72, u.modeMix)
                  * u.intensity * outside;
    alpha *= mix(1.0, 0.90 + 0.10 * pulse, u.modeMix);
    alpha = clamp(alpha, 0.0, 0.85);
    float gain = 1.0 + (u.hdrBoost - 1.0) * mix(0.32, 0.64 + 0.12 * pulse, u.modeMix);
    gain = min(u.hdrBoost, gain * mix(1.0, clamp(u.redGain, 0.5, 2.0), warning));
    return float4(color * gain * alpha, alpha);
}

