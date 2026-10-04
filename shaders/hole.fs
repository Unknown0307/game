#version 330
out vec4 finalColor;

uniform vec2  center;   // framebuffer pixels (origin bottom-left)
uniform float horizon;  // event-horizon radius in pixels
uniform float time;
uniform float boost;    // 0 idle -> 1 feeding / spitting
uniform float fade;     // overall opacity
uniform vec3  hot;
uniform vec3  cool;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
// Noise that wraps seamlessly around the angle.
float ring_noise(float ang, float rad, float scale, float spin) {
    vec2 c = vec2(cos(ang + spin), sin(ang + spin)) * scale;
    return noise(c + vec2(rad, rad * 0.7));
}

vec3 disc(vec2 q, float R) {
    float lq = length(q);
    float rq = lq / R;
    float edge_in = smoothstep(1.35, 1.75, rq);
    float edge_out = 1.0 - smoothstep(3.0, 4.2, rq);
    float band = edge_in * edge_out;
    if (band <= 0.001) return vec3(0.0);
    float aq = atan(q.y, q.x);
    float spin = time * (1.6 + 1.6 * boost) / pow(rq, 1.4);
    float n1 = ring_noise(aq, rq * 2.2, 2.5, -spin);
    float n2 = ring_noise(aq, rq * 6.0, 5.0, -spin * 1.3);
    float streak = 0.45 + 0.9 * (0.65 * n1 + 0.35 * n2);
    float temp = 1.0 - smoothstep(1.4, 4.0, rq);
    vec3 col = mix(cool, hot, temp);
    col = mix(col, vec3(1.0, 0.96, 0.88), pow(temp, 4.0) * 0.8);
    float dop = 1.0 - 0.6 * (q.x / (lq + 0.001));
    float rings = 0.85 + 0.15 * sin(rq * 38.0 - time * 3.0);
    return col * band * streak * dop * rings * (1.3 + 1.2 * boost) * (0.4 + temp);
}

void main() {
    vec2 p = gl_FragCoord.xy - center;
    float R = horizon;
    if (R < 1.0) discard;
    float r = length(p);
    float rn = r / R;
    float ang = atan(p.y, p.x);

    // Gravitational haze
    float haze = exp(-max(rn - 1.0, 0.0) * 0.55) * (1.0 - smoothstep(4.0, 6.5, rn));
    vec3 L = cool * haze * (0.20 + 0.25 * boost);

    // Lensed halo: the far side of the disc bent over the top and bottom
    float hr = (rn - 1.34) / 0.20;
    float halo = exp(-hr * hr);
    float hn = 0.6 + 0.8 * ring_noise(ang, rn * 3.0, 2.0, -time * (1.5 + boost));
    float vert = 0.45 + 0.55 * abs(sin(ang));
    L += mix(cool, hot, 0.65) * halo * hn * vert * (1.4 + boost);

    // Photon ring
    float pr = (rn - 1.07) / 0.045;
    L += vec3(1.0, 0.95, 0.9) * exp(-pr * pr) * (1.2 + 0.8 * boost);
    float pg = (rn - 1.07) / 0.2;
    L += hot * exp(-pg * pg) * 0.35;

    // Jets while energised
    float ay = abs(p.y) / R;
    float jw = R * (0.22 + 0.05 * ay);
    float jet = exp(-(p.x * p.x) / (jw * jw)) * smoothstep(1.1, 1.5, ay) * (1.0 - smoothstep(2.5, 6.0, ay));
    jet *= (0.6 + 0.4 * sin(abs(p.y) * 0.25 - time * 14.0)) * boost;
    L += cool * jet * 1.5;

    // The horizon hides everything behind it
    float hz = 1.0 - smoothstep(R * 0.93, R, r);
    L *= (1.0 - hz);

    // Tilted accretion disc: the near (lower) half passes in front of the hole
    vec2 q = vec2(p.x, p.y / 0.2);
    vec3 D = disc(q, R);
    if (p.y > 0.0) D *= (1.0 - hz);
    L += D;

    L *= fade;
    finalColor = vec4(L, hz * fade);
}
