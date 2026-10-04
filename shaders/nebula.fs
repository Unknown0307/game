#version 330
out vec4 finalColor;

uniform float time;
uniform vec2  seed;
uniform vec3  base;
uniform vec3  colA;
uniform vec3  colB;

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
        p = p * 2.03 + vec2(17.0, 9.0);
        a *= 0.5;
    }
    return v;
}

void main() {
    vec2 uv = gl_FragCoord.xy / vec2(800.0, 600.0);
    vec2 p = uv * vec2(2.6, 2.0) + seed + vec2(sin(time * 0.05) * 0.18, cos(time * 0.04) * 0.12);
    float drift = time * 0.035;
    float n = fbm(p + vec2(drift, -drift * 0.6));
    float m = fbm(p * 1.7 + vec2(5.2, 1.3) - vec2(drift * 1.4, 0.0));
    float cloudA = smoothstep(0.45, 0.85, n);
    float cloudB = smoothstep(0.50, 0.90, m);
    vec3 col = base + colA * cloudA * 0.30 + colB * cloudB * 0.22;
    float vig = 1.0 - smoothstep(0.35, 1.05, length(uv - vec2(0.5)) * 1.25);
    finalColor = vec4(col * (0.55 + 0.45 * vig), 1.0);
}
