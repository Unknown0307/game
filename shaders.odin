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

BlastShader :: struct {
	shader:     rl.Shader,
	center_loc: i32,
	radius_loc: i32,
	max_loc:    i32,
	prog_loc:   i32,
	tint_loc:   i32,
}

ShipShader :: struct {
	shader:   rl.Shader,
	time_loc: i32,
	tint_loc: i32,
}

Shaders :: struct {
	blast: BlastShader,
	ship:  ShipShader,
}

load_shaders :: proc() -> Shaders {
	bs := rl.LoadShaderFromMemory(nil, BLAST_FS)
	ss := rl.LoadShaderFromMemory(nil, SHIP_FS)
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
	}
}

unload_shaders :: proc(s: Shaders) {
	rl.UnloadShader(s.blast.shader)
	rl.UnloadShader(s.ship.shader)
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
