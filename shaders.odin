package main

import rl "vendor:raylib"

// =============================================================================
// shaders.odin - GLSL sources and their loaders.
// =============================================================================

// Glowing ring at the wave front plus a rippling glow inside. Used for the
// player blast AND the boss repel wave (just a different radius and tint).
BLAST_FS: cstring : `#version 330
out vec4 finalColor;

uniform vec2  center;     // blast centre in framebuffer pixels (origin bottom-left)
uniform float radius;     // current wave radius
uniform float maxRadius;  // full blast radius
uniform float progress;   // 0 -> 1 over the blast duration
uniform vec3  tint;       // wave colour

void main() {
    float d = distance(gl_FragCoord.xy, center);
    float fade = 1.0 - progress;

    float edge   = 1.0 - smoothstep(0.0, 12.0, abs(d - radius));
    float inner  = (1.0 - smoothstep(0.0, maxRadius, d)) * step(d, radius);
    float ripple = 0.5 + 0.5 * sin(d * 0.35 - progress * 40.0);

    float a = clamp(edge * 1.2 + inner * (0.25 + 0.2 * ripple), 0.0, 1.0) * fade;
    vec3 col = mix(tint, vec3(1.0), edge * 0.6);
    finalColor = vec4(col, a);
}
`

SHIP_FS: cstring : `#version 330
in vec4 fragColor;
uniform float time;
uniform vec3 tint;
out vec4 finalColor;
void main() {
    float pulse = 0.5 + 0.5 * sin(time * 8.0);
    float scan = 0.5 + 0.5 * sin(gl_FragCoord.y * 0.16 - time * 10.0);
    vec3 base = mix(fragColor.rgb, tint, 0.45);
    vec3 energy = mix(base, vec3(1.0), 0.18 + 0.12 * pulse + 0.10 * scan);
    finalColor = vec4(energy, fragColor.a);
}
`

// Deep-space backdrop: a very dark, slowly drifting nebula tinted by the level palette.
NEBULA_FS: cstring : `#version 330
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
    vec2 p = uv * vec2(2.6, 2.0) + seed;
    float drift = time * 0.012;
    float n = fbm(p + vec2(drift, -drift * 0.6));
    float m = fbm(p * 1.7 + vec2(5.2, 1.3) - vec2(drift * 1.4, 0.0));
    float cloudA = smoothstep(0.45, 0.85, n);
    float cloudB = smoothstep(0.50, 0.90, m);
    vec3 col = base + colA * cloudA * 0.20 + colB * cloudB * 0.14;
    float vig = 1.0 - smoothstep(0.35, 1.05, length(uv - vec2(0.5)) * 1.25);
    finalColor = vec4(col * (0.55 + 0.45 * vig), 1.0);
}
`

// Black hole: horizon, photon ring, lensed halo, tilted accretion disc with
// doppler beaming and differential rotation, plus energy jets while it feeds.
// Output is PREMULTIPLIED alpha: rgb = emitted light, a = how much it blocks
// what is behind it (the pitch-black horizon).
HOLE_FS: cstring : `#version 330
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
`

BlastShader :: struct {
	shader:     rl.Shader,
	center_loc: i32,
	radius_loc: i32,
	max_loc:    i32,
	prog_loc:   i32,
	tint_loc:   i32,
}

NebulaShader :: struct {
	shader:   rl.Shader,
	time_loc: i32,
	seed_loc: i32,
	base_loc: i32,
	a_loc:    i32,
	b_loc:    i32,
}

HoleShader :: struct {
	shader:      rl.Shader,
	center_loc:  i32,
	horizon_loc: i32,
	time_loc:    i32,
	boost_loc:   i32,
	fade_loc:    i32,
	hot_loc:     i32,
	cool_loc:    i32,
}

ShipShader :: struct {
	shader:   rl.Shader,
	time_loc: i32,
	tint_loc: i32,
}

Shaders :: struct {
	blast: BlastShader,
	ship:  ShipShader,
	nebula: NebulaShader,
	hole:   HoleShader,
}

load_shaders :: proc() -> Shaders {
	bs := rl.LoadShaderFromMemory(nil, BLAST_FS)
	ss := rl.LoadShaderFromMemory(nil, SHIP_FS)
	ns := rl.LoadShaderFromMemory(nil, NEBULA_FS)
	hs := rl.LoadShaderFromMemory(nil, HOLE_FS)
	return Shaders{
		blast = BlastShader{
			shader     = bs,
			center_loc = rl.GetShaderLocation(bs, "center"),
			radius_loc = rl.GetShaderLocation(bs, "radius"),
			max_loc    = rl.GetShaderLocation(bs, "maxRadius"),
			prog_loc   = rl.GetShaderLocation(bs, "progress"),
			tint_loc   = rl.GetShaderLocation(bs, "tint"),
		},
		ship = ShipShader{
			shader   = ss,
			time_loc = rl.GetShaderLocation(ss, "time"),
			tint_loc = rl.GetShaderLocation(ss, "tint"),
		},
		nebula = NebulaShader{
			shader   = ns,
			time_loc = rl.GetShaderLocation(ns, "time"),
			seed_loc = rl.GetShaderLocation(ns, "seed"),
			base_loc = rl.GetShaderLocation(ns, "base"),
			a_loc    = rl.GetShaderLocation(ns, "colA"),
			b_loc    = rl.GetShaderLocation(ns, "colB"),
		},
		hole = HoleShader{
			shader      = hs,
			center_loc  = rl.GetShaderLocation(hs, "center"),
			horizon_loc = rl.GetShaderLocation(hs, "horizon"),
			time_loc    = rl.GetShaderLocation(hs, "time"),
			boost_loc   = rl.GetShaderLocation(hs, "boost"),
			fade_loc    = rl.GetShaderLocation(hs, "fade"),
			hot_loc     = rl.GetShaderLocation(hs, "hot"),
			cool_loc    = rl.GetShaderLocation(hs, "cool"),
		},
	}
}

unload_shaders :: proc(s: Shaders) {
	rl.UnloadShader(s.blast.shader)
	rl.UnloadShader(s.ship.shader)
	rl.UnloadShader(s.nebula.shader)
	rl.UnloadShader(s.hole.shader)
}

// progress: 0 at the moment of the blast, 1 when it has finished.
draw_blast :: proc(b: BlastShader, center: [2]f32, progress, max_radius: f32, tint: [3]f32) {
	c := [2]f32{center.x, f32(SCREEN_H) - center.y} // gl_FragCoord has a bottom-left origin
	radius := progress * max_radius
	max_r := max_radius
	p := progress
	t := tint

	rl.SetShaderValue(b.shader, b.center_loc, &c, .VEC2)
	rl.SetShaderValue(b.shader, b.radius_loc, &radius, .FLOAT)
	rl.SetShaderValue(b.shader, b.max_loc, &max_r, .FLOAT)
	rl.SetShaderValue(b.shader, b.prog_loc, &p, .FLOAT)
	rl.SetShaderValue(b.shader, b.tint_loc, &t, .VEC3)

	extent := i32(max_radius) + 40
	rl.BeginBlendMode(.ADDITIVE)
	rl.BeginShaderMode(b.shader)
	rl.DrawRectangle(i32(center.x) - extent, i32(center.y) - extent, extent * 2, extent * 2, rl.WHITE)
	rl.EndShaderMode()
	rl.EndBlendMode()
}

// Full-screen nebula backdrop (opaque).
draw_nebula :: proc(n: NebulaShader, t: f32, seed: [2]f32, base, col_a, col_b: [3]f32) {
	tt, sd, bs, ca, cb := t, seed, base, col_a, col_b
	rl.SetShaderValue(n.shader, n.time_loc, &tt, .FLOAT)
	rl.SetShaderValue(n.shader, n.seed_loc, &sd, .VEC2)
	rl.SetShaderValue(n.shader, n.base_loc, &bs, .VEC3)
	rl.SetShaderValue(n.shader, n.a_loc, &ca, .VEC3)
	rl.SetShaderValue(n.shader, n.b_loc, &cb, .VEC3)
	rl.BeginShaderMode(n.shader)
	rl.DrawRectangle(0, 0, SCREEN_W, SCREEN_H, rl.WHITE)
	rl.EndShaderMode()
}

// `center` is in canvas pixels (origin top-left, inside the shaken camera);
// `shake_off` is the camera offset so the shader (which works in framebuffer
// pixels) lines up with the shaken picture.
draw_hole_shader :: proc(h: HoleShader, center, shake_off: [2]f32, horizon, t, boost, fade: f32, hot, cool: [3]f32) {
	c := [2]f32{center.x + shake_off.x, f32(SCREEN_H) - (center.y + shake_off.y)}
	hz, tt, bo, fd, ht, cl := horizon, t, boost, fade, hot, cool
	rl.SetShaderValue(h.shader, h.center_loc, &c, .VEC2)
	rl.SetShaderValue(h.shader, h.horizon_loc, &hz, .FLOAT)
	rl.SetShaderValue(h.shader, h.time_loc, &tt, .FLOAT)
	rl.SetShaderValue(h.shader, h.boost_loc, &bo, .FLOAT)
	rl.SetShaderValue(h.shader, h.fade_loc, &fd, .FLOAT)
	rl.SetShaderValue(h.shader, h.hot_loc, &ht, .VEC3)
	rl.SetShaderValue(h.shader, h.cool_loc, &cl, .VEC3)

	extent := i32(horizon * 7.0)
	rl.BeginBlendMode(.ALPHA_PREMULTIPLY)
	rl.BeginShaderMode(h.shader)
	rl.DrawRectangle(i32(center.x) - extent, i32(center.y) - extent, extent * 2, extent * 2, rl.WHITE)
	rl.EndShaderMode()
	rl.EndBlendMode()
}
