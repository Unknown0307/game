#version 330
out vec4 finalColor;

uniform vec2  center;     // framebuffer pixels (origin bottom-left)
uniform float radius;     // current front radius
uniform float maxRadius;  // full blast radius
uniform float progress;   // 0 -> 1
uniform vec3  tint;       // flame colour
uniform float seed;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * noise(p);
        p = p * 2.03 + vec2(13.0, 7.0);
        a *= 0.5;
    }
    return v;
}

void main() {
    vec2 v = gl_FragCoord.xy - center;
    float d = length(v);
    vec2 dir = v / max(d, 0.001);
    float ang = atan(v.y, v.x);
    float fade = 1.0 - progress;

    // Flame turbulence, drifting outward as the blast ages.
    vec2 q = dir * (d / maxRadius) * 3.0 + vec2(seed * 9.0, seed * 5.0);
    float turb  = fbm(q * 1.6 - dir * progress * 2.2);
    float turb2 = fbm(q * 4.2 + vec2(progress * 3.0, -progress * 2.0));

    float rn = d / max(radius, 1.0);                 // 1.0 on the front
    float rag = (turb - 0.5) * 0.45;                 // ragged edge
    float body = 1.0 - smoothstep(0.45 + rag, 1.0 + rag * 0.6, rn);
    float heat = body * (1.25 - 0.85 * rn) * (0.55 + 0.9 * turb2) * (1.0 - 0.7 * progress);

    // Flame palette: smoke red -> skill colour -> yellow -> white.
    vec3 col = mix(vec3(0.30, 0.03, 0.01), tint, smoothstep(0.05, 0.45, heat));
    col = mix(col, vec3(1.0, 0.86, 0.38), smoothstep(0.40, 0.90, heat));
    col = mix(col, vec3(1.0), smoothstep(0.90, 1.30, heat));

    // The initial flash.
    float fl = d / (maxRadius * (0.20 + 0.45 * progress));
    float flash = exp(-fl * fl) * pow(fade, 2.5);
    col = mix(col, vec3(1.0, 0.97, 0.88), clamp(flash, 0.0, 1.0));

    // Shock ring on the front.
    float rt = (d - radius) / (5.0 + 12.0 * fade);
    float ring = exp(-rt * rt);
    col += vec3(1.0, 0.88, 0.62) * ring * 0.9;

    // Embers: thin radial streaks just behind the front.
    float cellId = floor(ang * 7.639437);            // 48 rays around the circle
    float rh = hash(vec2(cellId, seed * 31.0));
    float rayOn = step(0.72, rh);
    float rayLen = radius * (0.25 + 0.4 * hash(vec2(cellId, 5.0 + seed)));
    float ray = rayOn * smoothstep(radius - rayLen, radius, d) * (1.0 - smoothstep(radius, radius + 10.0, d));
    ray *= 0.5 + 0.5 * hash(vec2(floor(ang * 120.0), floor(progress * 12.0)));
    col += vec3(1.0, 0.7, 0.3) * ray * 0.9;

    float a = clamp(body * (0.40 + 0.60 * heat) + ring * 0.9 + flash + ray * 0.8, 0.0, 1.0) * pow(fade, 0.7);
    finalColor = vec4(col, a);
}
