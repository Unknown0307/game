package main

import "core:strings"
import rl "vendor:raylib"

// =============================================================================
// shaders.odin - shader loaders and draw helpers. The GLSL itself lives in shaders/*.fs
// and is embedded at compile time with #load (see ARCHITECTURE.md: "Add a shader").
// =============================================================================

// Glowing ring at the wave front plus a rippling glow inside. Used for the
// player blast AND the boss repel wave (just a different radius and tint).
BLAST_FS :: #load("shaders/blast.fs", string)

SHIP_FS :: #load("shaders/ship.fs", string)

// Freeze skill: everything that is frozen is drawn through this. The original colours are
// pushed toward an icy palette, with a frosty crystal pattern, twinkling glints and a cold
// shimmer band. `amount` (0..1) fades the ice out when the freeze is about to end.
FREEZE_FS :: #load("shaders/freeze.fs", string)


// Player 1's booster trail: a long ion flame drawn on a quad behind each nozzle. It lives in
// NOZZLE-LOCAL space (x = forward, so the flame streams to -x): a white-hot core fading through
// electric blue and navy into violet smoke, ragged turbulent edges, shock diamonds and bright
// ion streaks racing down the flame. Drawn additively (rgb is added, weighted by alpha).
BOOSTER_FS :: #load("shaders/booster.fs", string)

// Explosion skill: a fireball. A white flash at the centre, billowing flame (turbulent noise
// pushed outward) that cools from white through yellow and the skill's orange to dark red, a
// bright shock ring at the front and streaking embers. Output is for ADDITIVE blending.
EXPLOSION_FS :: #load("shaders/explosion.fs", string)

// Deep-space backdrop: a very dark, slowly drifting nebula tinted by the level palette.
NEBULA_FS :: #load("shaders/nebula.fs", string)

// Black hole: horizon, photon ring, lensed halo, tilted accretion disc with
// doppler beaming and differential rotation, plus energy jets while it feeds.
// Output is PREMULTIPLIED alpha: rgb = emitted light, a = how much it blocks
// what is behind it (the pitch-black horizon).
HOLE_FS :: #load("shaders/hole.fs", string)

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

FreezeShader :: struct {
	shader:     rl.Shader,
	time_loc:   i32,
	amount_loc: i32,
}

BoosterShader :: struct {
	shader:     rl.Shader,
	time_loc:   i32,
	center_loc: i32,
	angle_loc:  i32,
	length_loc: i32,
	width_loc:  i32,
	thrust_loc: i32,
	seed_loc:   i32,
}

ExplosionShader :: struct {
	shader:     rl.Shader,
	center_loc: i32,
	radius_loc: i32,
	max_loc:    i32,
	prog_loc:   i32,
	tint_loc:   i32,
	seed_loc:   i32,
}

Shaders :: struct {
	blast:     BlastShader,
	ship:      ShipShader,
	nebula:    NebulaShader,
	hole:      HoleShader,
	freeze:    FreezeShader,
	booster:   BoosterShader,
	explosion: ExplosionShader,
}

// Compiles a fragment shader (the default vertex shader is used).
// GLSL lives in shaders/*.fs and is embedded into the executable at compile time.
load_fragment :: proc(src: string) -> rl.Shader {
	return rl.LoadShaderFromMemory(nil, strings.clone_to_cstring(src, context.temp_allocator))
}

load_shaders :: proc() -> Shaders {
	bs := load_fragment(BLAST_FS)
	ss := load_fragment(SHIP_FS)
	ns := load_fragment(NEBULA_FS)
	hs := load_fragment(HOLE_FS)
	fs := load_fragment(FREEZE_FS)
	au := load_fragment(BOOSTER_FS)
	es := load_fragment(EXPLOSION_FS)
	return Shaders {
		freeze = FreezeShader {
			shader = fs,
			time_loc = rl.GetShaderLocation(fs, "time"),
			amount_loc = rl.GetShaderLocation(fs, "amount"),
		},
		booster = BoosterShader {
			shader = au,
			time_loc = rl.GetShaderLocation(au, "time"),
			center_loc = rl.GetShaderLocation(au, "center"),
			angle_loc = rl.GetShaderLocation(au, "angle"),
			length_loc = rl.GetShaderLocation(au, "flameLen"),
			width_loc = rl.GetShaderLocation(au, "width"),
			thrust_loc = rl.GetShaderLocation(au, "thrust"),
			seed_loc = rl.GetShaderLocation(au, "seed"),
		},
		explosion = ExplosionShader {
			shader = es,
			center_loc = rl.GetShaderLocation(es, "center"),
			radius_loc = rl.GetShaderLocation(es, "radius"),
			max_loc = rl.GetShaderLocation(es, "maxRadius"),
			prog_loc = rl.GetShaderLocation(es, "progress"),
			tint_loc = rl.GetShaderLocation(es, "tint"),
			seed_loc = rl.GetShaderLocation(es, "seed"),
		},
		blast = BlastShader {
			shader = bs,
			center_loc = rl.GetShaderLocation(bs, "center"),
			radius_loc = rl.GetShaderLocation(bs, "radius"),
			max_loc = rl.GetShaderLocation(bs, "maxRadius"),
			prog_loc = rl.GetShaderLocation(bs, "progress"),
			tint_loc = rl.GetShaderLocation(bs, "tint"),
		},
		ship = ShipShader {
			shader = ss,
			time_loc = rl.GetShaderLocation(ss, "time"),
			tint_loc = rl.GetShaderLocation(ss, "tint"),
		},
		nebula = NebulaShader {
			shader = ns,
			time_loc = rl.GetShaderLocation(ns, "time"),
			seed_loc = rl.GetShaderLocation(ns, "seed"),
			base_loc = rl.GetShaderLocation(ns, "base"),
			a_loc = rl.GetShaderLocation(ns, "colA"),
			b_loc = rl.GetShaderLocation(ns, "colB"),
		},
		hole = HoleShader {
			shader = hs,
			center_loc = rl.GetShaderLocation(hs, "center"),
			horizon_loc = rl.GetShaderLocation(hs, "horizon"),
			time_loc = rl.GetShaderLocation(hs, "time"),
			boost_loc = rl.GetShaderLocation(hs, "boost"),
			fade_loc = rl.GetShaderLocation(hs, "fade"),
			hot_loc = rl.GetShaderLocation(hs, "hot"),
			cool_loc = rl.GetShaderLocation(hs, "cool"),
		},
	}
}

unload_shaders :: proc(s: Shaders) {
	rl.UnloadShader(s.blast.shader)
	rl.UnloadShader(s.ship.shader)
	rl.UnloadShader(s.nebula.shader)
	rl.UnloadShader(s.hole.shader)
	rl.UnloadShader(s.freeze.shader)
	rl.UnloadShader(s.booster.shader)
	rl.UnloadShader(s.explosion.shader)
}

// Sets the ice shader's uniforms (call once, then BeginShaderMode(freeze.shader) around the draws).
set_freeze_shader :: proc(s: FreezeShader, t, amount: f32) {
	tt, am := t, amount
	rl.SetShaderValue(s.shader, s.time_loc, &tt, .FLOAT)
	rl.SetShaderValue(s.shader, s.amount_loc, &am, .FLOAT)
}

// One booster flame: a quad around the nozzle drawn additively through BOOSTER_FS.
// `nozzle` is in canvas pixels (inside the shaken camera); `shake_off` is that camera offset.
draw_booster :: proc(
	b: BoosterShader,
	nozzle, shake_off: [2]f32,
	angle, length, width, thrust, t, seed: f32,
) {
	c := [2]f32{nozzle.x + shake_off.x, f32(SCREEN_H) - (nozzle.y + shake_off.y)}
	an, ln, wd, th, tt, sd := angle, length, width, thrust, t, seed
	rl.SetShaderValue(b.shader, b.center_loc, &c, .VEC2)
	rl.SetShaderValue(b.shader, b.angle_loc, &an, .FLOAT)
	rl.SetShaderValue(b.shader, b.length_loc, &ln, .FLOAT)
	rl.SetShaderValue(b.shader, b.width_loc, &wd, .FLOAT)
	rl.SetShaderValue(b.shader, b.thrust_loc, &th, .FLOAT)
	rl.SetShaderValue(b.shader, b.time_loc, &tt, .FLOAT)
	rl.SetShaderValue(b.shader, b.seed_loc, &sd, .FLOAT)

	extent := i32(length + width * 3 + 16) // the flame points away from the ship, but the bloom is round
	rl.BeginBlendMode(.ADDITIVE)
	rl.BeginShaderMode(b.shader)
	rl.DrawRectangle(
		i32(nozzle.x) - extent,
		i32(nozzle.y) - extent,
		extent * 2,
		extent * 2,
		rl.WHITE,
	)
	rl.EndShaderMode()
	rl.EndBlendMode()
}

// The Explosion skill's fireball. progress: 0 at the blast, 1 when it has finished. The front
// races out fast and slows down (ease-out), like a real blast wave.
draw_explosion :: proc(
	e: ExplosionShader,
	center: [2]f32,
	progress, max_radius: f32,
	tint: [3]f32,
) {
	c := [2]f32{center.x, f32(SCREEN_H) - center.y}
	inv := 1.0 - progress
	radius := max_radius * (1.0 - inv * inv * inv)
	max_r := max_radius
	p := progress
	t := tint
	sd := f32(int(center.x * 0.37 + center.y * 0.61) % 97) / 97.0

	rl.SetShaderValue(e.shader, e.center_loc, &c, .VEC2)
	rl.SetShaderValue(e.shader, e.radius_loc, &radius, .FLOAT)
	rl.SetShaderValue(e.shader, e.max_loc, &max_r, .FLOAT)
	rl.SetShaderValue(e.shader, e.prog_loc, &p, .FLOAT)
	rl.SetShaderValue(e.shader, e.tint_loc, &t, .VEC3)
	rl.SetShaderValue(e.shader, e.seed_loc, &sd, .FLOAT)

	extent := i32(max_radius) + 40
	rl.BeginBlendMode(.ADDITIVE)
	rl.BeginShaderMode(e.shader)
	rl.DrawRectangle(
		i32(center.x) - extent,
		i32(center.y) - extent,
		extent * 2,
		extent * 2,
		rl.WHITE,
	)
	rl.EndShaderMode()
	rl.EndBlendMode()
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
	rl.DrawRectangle(
		i32(center.x) - extent,
		i32(center.y) - extent,
		extent * 2,
		extent * 2,
		rl.WHITE,
	)
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
draw_hole_shader :: proc(
	h: HoleShader,
	center, shake_off: [2]f32,
	horizon, t, boost, fade: f32,
	hot, cool: [3]f32,
) {
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
	rl.DrawRectangle(
		i32(center.x) - extent,
		i32(center.y) - extent,
		extent * 2,
		extent * 2,
		rl.WHITE,
	)
	rl.EndShaderMode()
	rl.EndBlendMode()
}
