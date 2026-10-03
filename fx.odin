package main

import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

// =============================================================================
// fx.odin - particles, floating text, screen shake.
// =============================================================================

add_shake :: proc(g: ^Game, amount: f32) {
	g.fx.shake = min(max(g.fx.shake, amount), 20)
}

spawn_particle :: proc(g: ^Game, pos, vel: [2]f32, color: rl.Color, life, size: f32) {
	fx := &g.fx
	fx.particles[fx.particle_next] = Particle{pos = pos, vel = vel, life = life, max_life = life, size = size, color = color}
	fx.particle_next = (fx.particle_next + 1) % MAX_PARTICLES
}

// Radial burst of sparks
spawn_burst :: proc(g: ^Game, pos: [2]f32, color: rl.Color, count: int, speed: f32, size: f32 = 3.0) {
	for _ in 0 ..< count {
		ang := rand.float32_range(0, 2 * math.PI)
		spd := rand.float32_range(0.3, 1.0) * speed
		vel := [2]f32{math.cos(ang), math.sin(ang)} * spd
		spawn_particle(g, pos, vel, color, rand.float32_range(0.3, 0.7), rand.float32_range(size * 0.6, size * 1.4))
	}
}

// Ring of evenly spaced sparks (used by blast / repel waves)
spawn_ring :: proc(g: ^Game, center: [2]f32, color: rl.Color, count: int, speed, life, size: f32) {
	for i in 0 ..< count {
		ang := f32(i) / f32(count) * 2 * math.PI
		spawn_particle(g, center, [2]f32{math.cos(ang), math.sin(ang)} * speed, color, life, size)
	}
}

add_float :: proc(g: ^Game, pos: [2]f32, value: i32, kind: FloatKind) {
	fx := &g.fx
	p := [2]f32{clamp(pos.x, 20, SCREEN_W - 20), clamp(pos.y, 20, SCREEN_H - 20)}
	life: f32 = 1.0
	if kind == .Boss do life = 2.0
	fx.floaters[fx.float_next] = FloatText{pos = p, life = life, value = value, kind = kind}
	fx.float_next = (fx.float_next + 1) % MAX_FLOATS
}

update_fx :: proc(g: ^Game, dt: f32) {
	fx := &g.fx
	for &p in fx.particles {
		if p.life > 0 {
			p.life -= dt
			p.pos += p.vel * dt
			p.vel *= max(0, 1 - 2.5 * dt)
		}
	}
	for &f in fx.floaters {
		if f.life > 0 {
			f.life -= dt
			f.pos.y -= 45 * dt
		}
	}
	fx.shake = max(0, fx.shake - 35 * dt)
}

clear_fx :: proc(g: ^Game) {
	g.fx = Fx{}
}

// Soft additive glow built from a few stacked translucent circles.
// Call inside additive blend mode.
draw_glow :: proc(pos: [2]f32, radius: f32, color: rl.Color, intensity: f32) {
	for i in 0 ..< 4 {
		k := f32(i) / 4.0
		rl.DrawCircleV(pos, radius * (1.0 - k * 0.75), rl.Fade(color, intensity * 0.25))
	}
}

rand_signed :: proc() -> f32 {
	return rand.float32_range(-1, 1)
}
