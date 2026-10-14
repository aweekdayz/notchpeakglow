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

// The glow follows the hardware notch: its top merges with the screen edge and only the
// lower corners are rounded. A thin lit edge sits inside a tight bloom and a faint tail.
fragment float4 fragmentShader(FragmentInput in [[stage_in]],
                               constant Uniforms &u [[buffer(0)]]) {
    float2 p = in.position.xy - u.notchCenter;
    float k = max(0.5, u.glowScale);                 // pixels per design unit
    float h = u.notchSize.y;
    float rb = h * 0.28;                              // bottom corner radius of the hardware notch
    float ext = h * 3.0;                              // extend the body above the screen edge
    float sd = roundedBox(p - float2(0.0, -ext * 0.5), float2(u.notchSize.x * 0.5, h * 0.5 + ext * 0.5), rb);
    float outside = smoothstep(-0.5, 1.0, sd);
    float pulse = 0.5 + 0.5 * sin(6.283185 * u.pulseHz * u.time);
    float warning = clamp(u.warningMix, 0.0, 1.0);
    float widen = mix(1.0, clamp(u.redScale, 0.6, 1.8), warning);

    float d = max(sd, 0.0);
    float rim  = exp(-d / (0.9 * k));                 // thin lit edge
    float bloom = exp(-d / (11.0 * k * widen));        // tight bloom hugging the contour
    float haze = exp(-d / (32.0 * k * widen));        // long soft tail

    // Colour travels along the contour, slowly; same palette as before.
    float t = p.x / max(u.notchSize.x, 1.0) + 0.35 * p.y / max(h, 1.0);
    float wave = 0.5 + 0.5 * sin(t * 3.4 + u.time * 0.30);
    float ribbon = 0.5 + 0.5 * sin(t * 5.0 - u.time * 0.23 + 1.5);
    float3 cyan = float3(0.25, 0.78, 0.96);
    float3 violet = float3(0.55, 0.36, 0.92);
    float3 pink = float3(0.94, 0.42, 0.69);
    float3 aurora = mix(cyan, violet, smoothstep(0.1, 0.9, wave));
    aurora = mix(aurora, pink, pow(ribbon, 3.0) * 0.36);
    float3 ice = mix(float3(0.24, 0.48, 0.98), float3(0.48, 0.79, 1.0), wave * 0.45);
    float3 color = mix(aurora, ice, u.modeMix);
    float3 warm = mix(float3(1.0, 0.53, 0.22), float3(0.96, 0.28, 0.32), wave * 0.35);
    color = mix(color, warm, warning * 0.85);
    color = mix(color, float3(0.86, 0.93, 1.0), rim * 0.45 * (1.0 - warning));

    float envelope = 0.40 * rim + 0.95 * bloom + 0.26 * haze;
    float alpha = envelope * mix(u.mediumAlpha, 0.72, u.modeMix) * u.intensity * outside;
    alpha *= mix(1.0, 0.90 + 0.10 * pulse, u.modeMix);
    alpha = clamp(alpha, 0.0, 0.85);
    float gain = 1.0 + (u.hdrBoost - 1.0) * mix(0.32, 0.64 + 0.12 * pulse, u.modeMix);
    gain = min(u.hdrBoost, gain * mix(1.0, clamp(u.redGain, 0.5, 2.0), warning));
    return float4(color * gain * alpha, alpha);
}
