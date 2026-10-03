package main

import "core:math"
import rl "vendor:raylib"

// =============================================================================
// backdrop.odin - the moving space scenery behind the arena.
//
// Every level gets 1-3 celestial bodies generated from its number: a rocky
// planet, a ringed gas giant, a sun, or a pulsar. They are sized relative to the
// map (a planet is 11-26% of the map height, a sun up to 26%, a pulsar's beams
// sweep the whole map), drift slowly across it and wrap around once they are
// fully off-screen. Some planets / suns / pulsars carry an asteroid belt: while
// a belt is on the map the asteroid spawn rate is high (see update_spawners).
// Everything here is purely visual except the belt's effect on asteroid spawns.
// =============================================================================

BODY_DIM :: 0.62 // scenery is dimmed so bullets and ships always read clearly

// Deterministic random stream: every call advances `i`.
seeded :: proc(seed: u32, i: ^u32) -> f32 {
	i^ += 1
	return star_rand(seed + i^ * 7919)
}

mix_color :: proc(a, b: rl.Color, k: f32) -> rl.Color {
	return rl.Color{
		u8(f32(a.r) + (f32(b.r) - f32(a.r)) * k),
		u8(f32(a.g) + (f32(b.g) - f32(a.g)) * k),
		u8(f32(a.b) + (f32(b.b) - f32(a.b)) * k),
		255,
	}
}

// How far the body (with rings, corona or belt) reaches from its centre.
body_extent :: proc(b: CelestialBody) -> f32 {
	if b.kind == .Pulsar {
		reach: f32 = 0
		if b.belt do reach = b.radius * b.belt_scale * 1.1
		return max(120.0, reach)
	}
	r := b.radius
	if b.kind == .Sun do r *= 2.0
	if b.kind == .GasGiant do r *= 2.0
	if b.belt do r = max(r, b.radius * b.belt_scale * 1.1)
	return r + 10
}

// Position at `age`: a straight drift that wraps once the body is fully off the map.
body_pos :: proc(b: CelestialBody, age: f32) -> [2]f32 {
	m := body_extent(b)
	w := f32(SCREEN_W) + 2 * m
	h := f32(SCREEN_H) + 2 * m
	x := math.mod(b.origin.x + m + b.vel.x * age, w)
	y := math.mod(b.origin.y + m + b.vel.y * age, h)
	if x < 0 do x += w
	if y < 0 do y += h
	return {x - m, y - m}
}

make_backdrop :: proc(level: i32) -> Backdrop {
	bd: Backdrop
	st := level_style(level)
	seed := u32(level) * 104729 + 31
	i: u32 = 0

	bd.count = 1
	if seeded(seed, &i) < 0.65 do bd.count += 1
	if seeded(seed, &i) < 0.25 do bd.count += 1
	bd.count = min(bd.count, MAX_BODIES)

	planet_tones := [5]rl.Color{{176, 96, 62, 255}, {52, 112, 204, 255}, {150, 202, 232, 255}, {72, 172, 122, 255}, {134, 92, 192, 255}}
	giant_tones  := [4]rl.Color{{214, 168, 110, 255}, {226, 130, 84, 255}, {232, 214, 176, 255}, {120, 156, 214, 255}}
	sun_tones    := [3]rl.Color{{255, 196, 96, 255}, {255, 124, 74, 255}, {176, 206, 255, 255}}

	for n in 0 ..< bd.count {
		b: CelestialBody
		b.seed  = seed + u32(n) * 977
		b.phase = seeded(seed, &i) * 2 * math.PI
		H := f32(SCREEN_H)
		W := f32(SCREEN_W)
		secondary := n > 0

		// What is it?
		roll := seeded(seed, &i)
		if secondary {
			b.kind = BodyKind.Planet if roll < 0.7 else BodyKind.GasGiant
		} else if roll < 0.32 {
			b.kind = .Planet
		} else if roll < 0.50 {
			b.kind = .GasGiant
		} else if roll < 0.74 {
			b.kind = .Sun
		} else {
			b.kind = .Pulsar
		}

		// Size, scaled to the map.
		k := seeded(seed, &i)
		switch b.kind {
		case .Planet:
			b.radius = H * (0.11 + 0.15 * k)
			b.color_a = planet_tones[int(seeded(seed, &i) * 4.99)]
			b.color_b = mix_color(b.color_a, st.accent, 0.55)
		case .GasGiant:
			b.radius = H * (0.09 + 0.09 * k)
			b.color_a = giant_tones[int(seeded(seed, &i) * 3.99)]
			b.color_b = mix_color(b.color_a, st.accent2, 0.5)
		case .Sun:
			b.radius = H * (0.14 + 0.12 * k)
			b.color_a = sun_tones[int(seeded(seed, &i) * 2.99)]
			b.color_b = mix_color(b.color_a, rl.WHITE, 0.4)
			b.spin = 0.12 + 0.1 * seeded(seed, &i)
		case .Pulsar:
			b.radius = H * 0.022
			b.color_a = rl.Color{170, 214, 255, 255}
			b.color_b = st.accent2
			b.spin = 1.1 + 0.8 * seeded(seed, &i)
		}
		if secondary {
			b.radius *= 0.45 // small, distant
			if b.kind == .GasGiant do b.radius = max(b.radius, H * 0.05)
		}

		// Placement (secondary bodies sit on the other side of the map).
		px := 0.12 + 0.76 * seeded(seed, &i)
		py := 0.20 + 0.65 * seeded(seed, &i)
		if secondary {
			px = math.mod(px + 0.5, 1.0)
		}
		b.origin = {px * W, py * H}

		// Slow drift, mostly sideways; distant bodies are slower (parallax).
		ang := (seeded(seed, &i) - 0.5) * 1.0
		if seeded(seed, &i) < 0.5 do ang += math.PI
		spd := BODY_DRIFT_MIN + (BODY_DRIFT_MAX - BODY_DRIFT_MIN) * seeded(seed, &i)
		if secondary do spd *= 0.6
		b.vel = {math.cos(ang), math.sin(ang)} * spd

		// Asteroid belt (not on ringed giants or on the small distant bodies).
		belt_roll := seeded(seed, &i)
		chance: f32 = BODY_BELT_CHANCE
		if b.kind == .Pulsar do chance = 0.30
		if b.kind != .GasGiant && !secondary && belt_roll < chance {
			b.belt = true
			switch b.kind {
			case .Planet:   b.belt_scale = 1.7
			case .Sun:      b.belt_scale = 2.15
			case .Pulsar:   b.belt_scale = 9.0
			case .GasGiant: b.belt_scale = 1.7
			}
			dir: f32 = 1 if seeded(seed, &i) < 0.5 else -1
			b.belt_speed = (0.08 + 0.12 * seeded(seed, &i)) * dir
		}
		bd.bodies[n] = b
	}
	return bd
}

// --- Asteroid belt query (used by the spawner) ---

// Distance from `p` to the map rectangle (0 when inside) and to its farthest corner.
map_distances :: proc(p: [2]f32) -> (near, far: f32) {
	dx := max(0 - p.x, 0, p.x - f32(SCREEN_W))
	dy := max(0 - p.y, 0, p.y - f32(SCREEN_H))
	near = math.sqrt(dx * dx + dy * dy)
	fx := max(abs(p.x), abs(p.x - f32(SCREEN_W)))
	fy := max(abs(p.y), abs(p.y - f32(SCREEN_H)))
	far = math.sqrt(fx * fx + fy * fy)
	return
}

// Is a belt ring currently crossing the map? Returns its centre and ring radius.
active_belt :: proc(g: ^Game) -> (pos: [2]f32, ring: f32, found: bool) {
	for n in 0 ..< g.backdrop.count {
		b := g.backdrop.bodies[n]
		if !b.belt do continue
		p := body_pos(b, g.backdrop.age)
		r := b.radius * b.belt_scale
		near, far := map_distances(p)
		if near <= r && r <= far do return p, r, true
	}
	return {}, 0, false
}

// --- Drawing ---

draw_ellipse_arc :: proc(c: [2]f32, rx, ry, tilt, a0, a1, th: f32, col: rl.Color) {
	n :: 28
	prev := c + rotate_vec({math.cos(a0) * rx, math.sin(a0) * ry}, tilt)
	for i in 1 ..= n {
		a := a0 + (a1 - a0) * f32(i) / f32(n)
		p := c + rotate_vec({math.cos(a) * rx, math.sin(a) * ry}, tilt)
		rl.DrawLineEx(prev, p, th, col)
		prev = p
	}
}

draw_planet_body :: proc(pos: [2]f32, r: f32, col, atmo: rl.Color, banded: bool, t: f32) {
	light := [2]f32{-0.55, -0.6}
	steps :: 8
	for i in 0 ..< steps {
		k := f32(i) / f32(steps - 1)
		c := mix_color(shade(col, 0.20), tint_up(col, 0.22), k)
		rl.DrawCircleV(pos + light * (r * 0.075 * f32(i)), r * (1.0 - 0.115 * f32(i)), c)
	}
	if banded {
		for j in 0 ..< 6 {
			dy := r * (-0.7 + 0.28 * f32(j)) + math.sin(t * 0.4 + f32(j)) * r * 0.02
			hh := r * 0.05 * (1.0 + f32(j % 2))
			w := math.sqrt(max(r * r - (abs(dy) + hh) * (abs(dy) + hh), 0))
			rl.DrawRectangleV({pos.x - w, pos.y + dy - hh}, {w * 2, hh * 2}, rl.Fade(atmo, 0.35))
		}
	}
	rl.BeginBlendMode(.ADDITIVE)
	draw_glow(pos, r * 1.25, atmo, 0.14)
	rl.DrawCircleLines(i32(pos.x), i32(pos.y), r, rl.Fade(atmo, 0.5))
	rl.DrawCircleLines(i32(pos.x), i32(pos.y), r + 1.5, rl.Fade(atmo, 0.22))
	rl.EndBlendMode()
}

draw_sun_body :: proc(pos: [2]f32, r: f32, b: CelestialBody, t: f32) {
	pulse := 0.5 + 0.5 * math.sin(t * 1.3 + b.phase)
	ca := shade(b.color_a, BODY_DIM)
	cb := shade(b.color_b, BODY_DIM)

	rl.BeginBlendMode(.ADDITIVE)
	draw_glow(pos, r * (2.0 + 0.1 * pulse), ca, 0.20)
	draw_glow(pos, r * 1.45, ca, 0.30)
	rays :: 14
	for i in 0 ..< rays {
		a := b.phase + t * b.spin + f32(i) * 2 * math.PI / f32(rays)
		d := [2]f32{math.cos(a), math.sin(a)}
		perp := [2]f32{-d.y, d.x}
		reach := r * (1.5 + 0.35 * math.sin(f32(i) * 1.7 + t * 1.1))
		draw_tri_ccw(pos + d * r * 0.9 + perp * r * 0.07, pos + d * r * 0.9 - perp * r * 0.07, pos + d * reach, rl.Fade(cb, 0.22))
	}
	rl.EndBlendMode()

	rl.DrawCircleV(pos, r, ca)
	rl.DrawCircleV(pos, r * 0.82, mix_color(ca, cb, 0.5))
	rl.DrawCircleV(pos, r * 0.55, mix_color(cb, rl.WHITE, 0.45 * BODY_DIM))
}

draw_pulsar_body :: proc(pos: [2]f32, b: CelestialBody, t: f32) {
	near, _ := map_distances(pos)
	vis := 1.0 - clamp(near / 120.0, 0, 1) // beams fade out before the pulsar wraps
	ca := shade(b.color_a, BODY_DIM + 0.2)
	cb := shade(b.color_b, BODY_DIM + 0.2)
	pulse := 0.5 + 0.5 * math.sin(t * b.spin * 6.0 + b.phase)

	rl.BeginBlendMode(.ADDITIVE)
	ang := b.phase + t * b.spin
	for s in 0 ..< 2 {
		a := ang + f32(s) * math.PI
		d := [2]f32{math.cos(a), math.sin(a)}
		perp := [2]f32{-d.y, d.x}
		tip := pos + d * MAP_DIAGONAL
		draw_quad_ccw(pos + perp * 5, pos - perp * 5, tip - perp * 46, tip + perp * 46, rl.Fade(ca, 0.09 * vis))
		draw_quad_ccw(pos + perp * 2, pos - perp * 2, tip - perp * 16, tip + perp * 16, rl.Fade(ca, 0.15 * vis))
	}
	draw_glow(pos, 46 + 14 * pulse, ca, 0.5)
	k := math.mod(t * 0.45 + b.phase, 1.0)
	rl.DrawCircleLines(i32(pos.x), i32(pos.y), 18 + k * 150, rl.Fade(cb, (1.0 - k) * 0.35))
	rl.EndBlendMode()
	rl.DrawCircleV(pos, b.radius, rl.Fade(rl.WHITE, 0.9))
}

draw_belt :: proc(pos: [2]f32, b: CelestialBody, age: f32) {
	R := b.radius * b.belt_scale
	count :: 64
	for i in 0 ..< count {
		h1 := star_rand(b.seed + u32(i) * 3 + 1)
		h2 := star_rand(b.seed + u32(i) * 3 + 2)
		h3 := star_rand(b.seed + u32(i) * 3 + 3)
		a := f32(i) / f32(count) * 2 * math.PI + h1 * 0.09 + age * b.belt_speed * (0.8 + 0.4 * h2)
		rr := R * (1.0 + (h2 - 0.5) * 0.24)
		p := pos + [2]f32{math.cos(a), math.sin(a)} * rr
		size := 1.5 + 3.0 * h3
		g := u8(110 + 70 * h1)
		rl.DrawCircleV(p, size, rl.Color{g, u8(f32(g) * 0.92), u8(f32(g) * 0.82), 255})
	}
}

draw_body :: proc(g: ^Game, b: CelestialBody) {
	pos := body_pos(b, g.backdrop.age)
	ext := body_extent(b)
	if pos.x < -ext || pos.x > SCREEN_W + ext || pos.y < -ext || pos.y > SCREEN_H + ext do return
	t := g.time
	tilt := math.sin(b.phase) * 0.4

	switch b.kind {
	case .Planet:
		draw_planet_body(pos, b.radius, shade(b.color_a, BODY_DIM), shade(b.color_b, BODY_DIM), false, t)
	case .GasGiant:
		col := shade(b.color_a, BODY_DIM)
		atmo := shade(b.color_b, BODY_DIM)
		radii := [3]f32{1.45, 1.65, 1.88}
		widths := [3]f32{0.07, 0.11, 0.05}
		for j in 0 ..< 3 { // back half of the rings (behind the planet)
			draw_ellipse_arc(pos, b.radius * radii[j], b.radius * radii[j] * 0.28, tilt, math.PI, 2 * math.PI, b.radius * widths[j], rl.Fade(mix_color(col, atmo, 0.4), 0.55))
		}
		draw_planet_body(pos, b.radius, col, atmo, true, t)
		for j in 0 ..< 3 { // front half
			draw_ellipse_arc(pos, b.radius * radii[j], b.radius * radii[j] * 0.28, tilt, 0, math.PI, b.radius * widths[j], rl.Fade(mix_color(col, atmo, 0.4), 0.75))
		}
	case .Sun:
		draw_sun_body(pos, b.radius, b, t)
	case .Pulsar:
		draw_pulsar_body(pos, b, t)
	}
	if b.belt do draw_belt(pos, b, g.backdrop.age)
}

// A comet crosses the map every 8 seconds, in a different direction each time.
draw_comet :: proc(g: ^Game) {
	period :: 8.0
	span   :: 0.32 // fraction of the period it is visible
	slot := u32(g.time / period)
	u := math.mod(g.time / period, 1.0)
	if u > span do return
	u /= span

	seed := slot * 131 + u32(g.level) * 17
	a := star_rand(seed + 1) * 2 * math.PI
	d := [2]f32{math.cos(a), math.sin(a)}
	off := (star_rand(seed + 2) - 0.5) * 360
	c := [2]f32{f32(SCREEN_W) * 0.5, f32(SCREEN_H) * 0.5} + [2]f32{-d.y, d.x} * off
	head := c + d * ((u - 0.5) * 1300)

	rl.BeginBlendMode(.ADDITIVE)
	for i in 0 ..< 8 {
		k := f32(i) / 8.0
		rl.DrawLineEx(head - d * (k * 110), head - d * ((k + 0.125) * 110), 3.0 * (1.0 - k) + 0.5, rl.Fade(g.style.accent2, 0.55 * (1.0 - k)))
	}
	draw_glow(head, 9, rl.WHITE, 0.6)
	rl.EndBlendMode()
}

draw_backdrop :: proc(g: ^Game) {
	// Farthest (smallest, slowest) first so nearer bodies cover them.
	for n := g.backdrop.count - 1; n >= 0; n -= 1 {
		draw_body(g, g.backdrop.bodies[n])
	}
	draw_comet(g)
}
