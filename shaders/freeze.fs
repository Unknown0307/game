#version 330
in vec4 fragColor;
uniform float time;
uniform float amount;
out vec4 finalColor;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void main() {
    vec3 base = fragColor.rgb;
    float lum = dot(base, vec3(0.299, 0.587, 0.114));

    // Icy palette keyed on the original brightness: dark parts deep blue, bright parts frosty white.
    vec3 ice = mix(vec3(0.30, 0.55, 0.95), vec3(0.88, 0.97, 1.0), clamp(lum * 1.3, 0.0, 1.0));
    vec3 col = mix(base, ice, 0.85 * amount);

    // Frost crystals (screen-space noise) and a faint white rime.
    vec2 p = gl_FragCoord.xy * 0.22;
    float n = 0.65 * noise(p) + 0.35 * noise(p * 2.7 + 11.0);
    float frost = smoothstep(0.55, 0.85, n);
    col += vec3(0.50, 0.78, 1.0) * frost * 0.30 * amount;
    col = mix(col, vec3(1.0), frost * 0.20 * amount);

    // Twinkling glints.
    vec2 cell = floor(gl_FragCoord.xy * 0.35);
    float h = hash(cell);
    float tw = pow(max(0.0, sin(time * 5.0 + h * 6.2831)), 12.0);
    col += vec3(1.0) * step(0.93, h) * tw * 0.9 * amount;

    // Slow cold shimmer sweeping across.
    float band = 0.5 + 0.5 * sin(gl_FragCoord.x * 0.12 + gl_FragCoord.y * 0.09 - time * 2.0);
    col += vec3(0.08, 0.18, 0.34) * band * 0.30 * amount;

    finalColor = vec4(col, fragColor.a);
}
