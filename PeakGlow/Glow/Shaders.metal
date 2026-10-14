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
    float powerMix;
    float lightMix;
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
// lower corners are rounded. Power drives a monotone colour ramp (blue, cyan, green, yellow)
// with brightness and bloom width; orange and red are reserved for the temperature warning.
// The glow follows the hardware notch: its top merges with the screen edge and only the
// lower corners are rounded. Power drives a monotone colour ramp (blue, cyan, green, yellow)
// with brightness and bloom width; orange and red are reserved for the temperature warning.
// On bright wallpapers a deeper, more saturated version of the same ramp keeps its contrast.
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
    float t = clamp(u.powerMix, 0.0, 1.0);
    float sz = mix(0.65, 1.45, t);
    float bloom = exp(-d / (11.0 * k * widen * sz));        // tight bloom hugging the contour
    float haze = exp(-d / (32.0 * k * widen * sz));        // long soft tail

    // Colour encodes power along a single hue direction: blue, cyan, green, yellow.
    float along = p.x / max(u.notchSize.x, 1.0) + 0.35 * p.y / max(h, 1.0);
    float wave = 0.5 + 0.5 * sin(along * 3.4 + u.time * 0.30);
    float tc = clamp(t + (wave - 0.5) * 0.06, 0.0, 1.0);
    float3 c0 = float3(0.18, 0.36, 1.00);
    float3 c1 = float3(0.10, 0.78, 1.00);
    float3 c2 = float3(0.22, 0.92, 0.46);
    float3 c3 = float3(0.70, 0.93, 0.26);
    float3 c4 = float3(0.99, 0.88, 0.28);
    float3 color = mix(c0, c1, smoothstep(0.00, 0.25, tc));
    color = mix(color, c2, smoothstep(0.25, 0.50, tc));
    color = mix(color, c3, smoothstep(0.50, 0.75, tc));
    color = mix(color, c4, smoothstep(0.75, 1.00, tc));
    // For bright wallpapers the same ramp is deeper and more saturated so it keeps its contrast.
    float L = clamp(u.lightMix, 0.0, 1.0);
    float3 l0 = float3(0.12, 0.24, 0.88);   // deep blue
    float3 l1 = float3(0.00, 0.50, 0.90);   // azure
    float3 l2 = float3(0.02, 0.58, 0.34);   // green
    float3 l3 = float3(0.46, 0.56, 0.02);   // olive
    float3 l4 = float3(0.76, 0.56, 0.00);   // gold
    float3 lightColor = mix(l0, l1, smoothstep(0.00, 0.25, tc));
    lightColor = mix(lightColor, l2, smoothstep(0.25, 0.50, tc));
    lightColor = mix(lightColor, l3, smoothstep(0.50, 0.75, tc));
    lightColor = mix(lightColor, l4, smoothstep(0.75, 1.00, tc));
    color = mix(color, lightColor, L);
    float3 warm = mix(float3(1.0, 0.53, 0.22), float3(0.96, 0.28, 0.32), wave * 0.35);
    warm = mix(warm, float3(0.88, 0.32, 0.04), L);
    color = mix(color, warm, warning);
    color = mix(color, float3(0.86, 0.93, 1.0), rim * 0.34 * (1.0 - warning) * (1.0 - L));

    float envelope = (0.40 * rim + 0.95 * bloom + 0.26 * haze) * mix(0.55, 1.35, t);
    float alpha = envelope * mix(u.mediumAlpha, 0.72, u.modeMix) * u.intensity * outside;
    alpha *= mix(1.0, 0.90 + 0.10 * pulse, u.modeMix);
    alpha *= mix(1.0, 1.5, L);
    alpha = clamp(alpha, 0.0, mix(0.85, 0.92, L));
    float gain = 1.0 + (u.hdrBoost - 1.0) * mix(0.32, 0.64 + 0.12 * pulse, u.modeMix);
    gain = mix(gain, 1.0, L);
    gain = min(u.hdrBoost, gain * mix(1.0, clamp(u.redGain, 0.5, 2.0), warning));
    return float4(color * gain * alpha, alpha);
}
