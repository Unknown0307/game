#version 330
in vec4 fragColor;
uniform float time;
uniform vec2  center;   // the nozzle in framebuffer pixels (origin bottom-left)
uniform float angle;    // ship heading (radians, y-down world)
uniform float flameLen; // flame length in pixels
uniform float width;    // flame half-width at the nozzle in pixels
uniform float thrust;   // 0..1
uniform float seed;     // decorrelates the three flames
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
    vec2 v = gl_FragCoord.xy - center;
    vec2 w = vec2(v.x, -v.y);
    float ca = cos(angle);
    float sa = sin(angle);
    vec2 l = vec2(w.x * ca + w.y * sa, -w.x * sa + w.y * ca);

    float d = -l.x / max(flameLen, 1.0);              // 0 at the nozzle, 1 at the flame tip
    if (d < -0.12 || d > 1.0) discard;

    // Bell-shaped width: a quick flare right behind the nozzle, then a long taper.
    float flare = 0.75 + 0.45 * smoothstep(0.0, 0.10, d);
    float taper = pow(clamp(1.0 - d, 0.0, 1.0), 0.75);
    float wd = width * flare * taper;

    // Turbulence streaming tail-ward; the flame whips sideways more toward the tip.
    float speed = 11.0 + 9.0 * thrust;
    float n  = noise(vec2(d * 7.0 - time * speed * 0.35 + seed, l.y * 0.22 + seed * 3.0));
    float n2 = noise(vec2(d * 17.0 - time * speed * 0.8 + seed * 2.0, l.y * 0.5 - time * 0.5));
    float wob = (n - 0.5) * wd * 0.9 * smoothstep(0.1, 0.9, d);
    float a = abs(l.y + wob) / max(wd, 0.001);       // 0 on the axis, 1 at the flame edge

    float body = (1.0 - smoothstep(0.35, 1.05, a + (n2 - 0.5) * 0.35)) * (1.0 - smoothstep(0.55, 1.0, d + (n - 0.5) * 0.22));
    float core = (1.0 - smoothstep(0.0, 0.55, a)) * (1.0 - smoothstep(0.0, 0.50, d));
    float hot  = (1.0 - smoothstep(0.0, 0.22, a)) * (1.0 - smoothstep(0.0, 0.28, d));

    // Colour ramp: white-hot -> electric blue -> navy -> violet smoke at the tip.
    vec3 navy   = vec3(0.06, 0.14, 0.55);
    vec3 blue   = vec3(0.15, 0.50, 1.00);
    vec3 violet = vec3(0.42, 0.18, 0.85);
    vec3 col = mix(blue, navy, smoothstep(0.15, 0.75, d + a * 0.4));
    col = mix(col, violet, smoothstep(0.55, 1.0, d) * 0.7);
    col = mix(col, vec3(0.75, 0.93, 1.0), core * 0.85);
    col = mix(col, vec3(1.0), hot);

    // Shock diamonds along the axis.
    float dia = pow(max(0.0, sin(d * 21.0 * (0.6 + 0.4 * flameLen / 90.0) - time * 6.0)), 6.0);
    float diamonds = dia * (1.0 - smoothstep(0.0, 0.40, a)) * (1.0 - smoothstep(0.05, 0.75, d));

    // Bright ion streaks racing down the flame.
    float st = noise(vec2(l.y * 0.9 + seed * 5.0, 3.0));
    float streak = pow(0.5 + 0.5 * sin(d * 34.0 - time * 26.0 + st * 6.28), 10.0)
                 * step(0.55, st) * (1.0 - smoothstep(0.0, 0.8, a)) * (1.0 - d);

    // A soft glow bleeding past the flame edge, and a bloom right at the nozzle.
    float halo  = exp(-a * a * 1.6) * (1.0 - d) * 0.35;
    float bz = (d * flameLen) / (width * 2.4);
    float bloom = exp(-bz * bz) * exp(-a * a * 0.7) * 0.6;

    float alpha = body * (0.80 + 0.2 * n) + diamonds * 0.55 + streak * 0.6 + halo + bloom;
    float power = 0.45 + 0.55 * thrust;              // an idling engine glows, a thrusting one blazes
    alpha = clamp(alpha * power * (0.92 + 0.08 * sin(time * 40.0 + seed)), 0.0, 1.0);

    col += vec3(0.5, 0.75, 1.0) * (diamonds * 0.7 + streak * 0.8);
    finalColor = vec4(col, alpha);
}
