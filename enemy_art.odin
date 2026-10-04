package main

import "core:fmt"
import "core:math"
import rl "vendor:raylib"

// =============================================================================
// enemy_art.odin - the look of every enemy. All shapes are built from triangles
// in "local units" (+x = the way the ship faces) scaled by the enemy radius, so
// hitboxes stay the circles gameplay already uses.
//
//   Normal -> Raider   (red dart fighter)
//   Runner -> Rocket   (small orange missile / drone)
//   Big    -> Cruiser  (heavy armoured gunship, size varies; shoots - see gunfire.odin)
//   Sticky -> Mine pod (spiked drone that arms and detonates)
//   Minion -> Baby whale (whale boss) or Drone (mothership boss)
//   Boss   -> Space whale OR Mothership (wraps around the screen edges like the players)
// =============================================================================

// Local -> world: `r` scales local units, `a` is the facing angle.
epoint :: proc(c: [2]f32, a, r, x, y: f32) -> [2]f32 {
	return c + rotate_vec({x * r, y * r}, a)
}

draw_quad_ccw :: proc(a, b, c, d: [2]f32, col: rl.Color) {
	draw_tri_ccw(a, b, c, col)
	draw_tri_ccw(a, c, d, col)
}

// Fills a star-shaped polygon as a fan around `center`.
draw_fan_ccw :: proc(center: [2]f32, pts: [][2]f32, col: rl.Color) {
	n := len(pts)
	for i in 0 ..< n {
		draw_tri_ccw(center, pts[i], pts[(i + 1) % n], col)
	}
}

draw_poly_outline :: proc(pts: [][2]f32, col: rl.Color) {
	n := len(pts)
	for i in 0 ..< n {
		rl.DrawLineV(pts[i], pts[(i + 1) % n], col)
	}
}

// Engine flame pointing backwards from local (x0, y0).
draw_exhaust :: proc(c: [2]f32, a, r: f32, x0, y0, width, length: f32, col: rl.Color) {
	rl.BeginBlendMode(.ADDITIVE)
	draw_tri_ccw(epoint(c, a, r, x0, y0 - width), epoint(c, a, r, x0, y0 + width), epoint(c, a, r, x0 - length, y0), rl.Fade(col, 0.7))
	draw_tri_ccw(epoint(c, a, r, x0, y0 - width * 0.45), epoint(c, a, r, x0, y0 + width * 0.45), epoint(c, a, r, x0 - length * 0.6, y0), rl.Fade(rl.WHITE, 0.85))
	rl.EndBlendMode()
}

tint_up :: proc(c: rl.Color, k: f32) -> rl.Color {
	return rl.Color{
		u8(f32(c.r) + (255 - f32(c.r)) * k),
		u8(f32(c.g) + (255 - f32(c.g)) * k),
		u8(f32(c.b) + (255 - f32(c.b)) * k),
		c.a,
	}
}

// --- Raider (Normal) ---

draw_raider :: proc(e: Enemy, col: rl.Color, t, ph: f32) {
	c, a, r := e.pos, e.angle, e.radius
	flick := 0.75 + 0.25 * math.sin(t * 34 + ph)
	draw_exhaust(c, a, r, -0.5, 0, 0.28, 0.9 * flick, rl.Color{255, 110, 40, 255})

	nose  := epoint(c, a, r, 1.4, 0)
	lw    := epoint(c, a, r, -0.9, -1.05)
	rw    := epoint(c, a, r, -0.9, 1.05)
	notch := epoint(c, a, r, -0.5, 0)
	draw_tri_ccw(nose, lw, notch, col)
	draw_tri_ccw(nose, notch, rw, col)
	draw_tri_ccw(epoint(c, a, r, 0.9, 0), epoint(c, a, r, -0.2, -0.42), epoint(c, a, r, -0.2, 0.42), shade(col, 0.5))

	edge := rl.Fade(rl.WHITE, 0.35)
	rl.DrawLineV(nose, lw, edge)
	rl.DrawLineV(lw, notch, edge)
	rl.DrawLineV(notch, rw, edge)
	rl.DrawLineV(rw, nose, edge)
	rl.DrawCircleV(epoint(c, a, r, 0.4, 0), r * 0.2, rl.Color{255, 235, 130, 255})
}

// --- Rocket / drone (Runner) ---

draw_rocket :: proc(e: Enemy, col: rl.Color, t, ph: f32) {
	c, a, r := e.pos, e.angle, e.radius
	draw_exhaust(c, a, r, -1.25, 0, 0.32, 1.3 + 0.5 * math.sin(t * 40 + ph), rl.Color{255, 150, 40, 255})

	// Fins, body, nose cone.
	for side in ([2]f32{-1, 1}) {
		draw_tri_ccw(epoint(c, a, r, -0.55, side * 0.34), epoint(c, a, r, -1.3, side * 1.05), epoint(c, a, r, -1.3, side * 0.34), shade(col, 0.7))
	}
	b0 := epoint(c, a, r, 0.85, -0.38)
	b1 := epoint(c, a, r, 0.85, 0.38)
	b2 := epoint(c, a, r, -1.3, 0.38)
	b3 := epoint(c, a, r, -1.3, -0.38)
	draw_quad_ccw(b0, b1, b2, b3, col)
	draw_quad_ccw(epoint(c, a, r, -0.2, -0.38), epoint(c, a, r, -0.2, 0.38), epoint(c, a, r, -0.6, 0.38), epoint(c, a, r, -0.6, -0.38), shade(col, 0.55))
	nose := epoint(c, a, r, 1.8, 0)
	draw_tri_ccw(nose, b0, b1, rl.Color{240, 240, 245, 255})

	edge := rl.Fade(rl.WHITE, 0.35)
	rl.DrawLineV(b0, b3, edge)
	rl.DrawLineV(b1, b2, edge)
	rl.DrawCircleV(epoint(c, a, r, 0.4, 0), r * 0.17, rl.Fade(rl.SKYBLUE, 0.95))
}

// --- Cruiser (Big) ---

CRUISER_HULL :: [9][2]f32{
	{1.3, 0}, {0.7, -0.5}, {0.1, -1.0}, {-0.7, -0.95}, {-1.0, -0.55},
	{-1.0, 0.55}, {-0.7, 0.95}, {0.1, 1.0}, {0.7, 0.5},
}

draw_cruiser :: proc(e: Enemy, col: rl.Color, t, ph: f32) {
	c, a, r := e.pos, e.angle, e.radius
	flick := 0.8 + 0.2 * math.sin(t * 22 + ph)
	for y in ([3]f32{-0.42, 0, 0.42}) {
		draw_exhaust(c, a, r, -1.0, y, 0.17, 0.75 * flick, rl.Color{255, 90, 60, 255})
	}

	local := CRUISER_HULL
	hull:  [9][2]f32
	inner: [9][2]f32
	for p, i in local {
		hull[i]  = epoint(c, a, r, p.x, p.y)
		inner[i] = epoint(c, a, r, p.x * 0.62, p.y * 0.62)
	}
	draw_fan_ccw(c, hull[:], col)
	draw_fan_ccw(c, inner[:], shade(col, 0.55))
	draw_poly_outline(hull[:], rl.Fade(rl.WHITE, 0.4))
	rl.DrawLineV(epoint(c, a, r, 1.3, 0), epoint(c, a, r, -1.0, 0), rl.Fade(rl.WHITE, 0.2))

	// Twin turrets and a lit bridge.
	barrel := rl.Color{30, 30, 40, 255}
	if e.laser do barrel = rl.Color{20, 50, 65, 255}
	for side in ([2]f32{-1, 1}) {
		base := epoint(c, a, r, 0.15, side * 0.55)
		rl.DrawLineEx(base, epoint(c, a, r, 0.85, side * 0.55), max(2.0, r * 0.1), barrel)
		rl.DrawCircleV(base, r * 0.19, rl.Color{30, 30, 40, 255})
		rl.DrawCircleLines(i32(base.x), i32(base.y), r * 0.19, rl.Fade(rl.WHITE, 0.45))
	}
	rl.DrawCircleV(epoint(c, a, r, -0.25, 0), r * 0.2, rl.Color{255, 200, 90, 255})

	if e.laser {
		// Nose emitter that charges up between beams.
		charge := 1.0 - clamp(f32(e.gun_ticks) / f32(LASER_COOLDOWN_TICKS), 0, 1)
		if e.laser_ticks > 0 do charge = 1
		lens := epoint(c, a, r, 1.1, 0)
		rl.BeginBlendMode(.ADDITIVE)
		draw_glow(lens, r * (0.22 + 0.38 * charge), LASER_COLOR, 0.35 + 0.65 * charge)
		rl.DrawCircleV(lens, r * (0.06 + 0.05 * charge), rl.Fade(rl.WHITE, 0.5 + 0.5 * charge))
		rl.EndBlendMode()
	} else if e.gun_ticks >= BIG_SHOOT_COOLDOWN_TICKS - 3 && e.gun_ticks <= BIG_SHOOT_COOLDOWN_TICKS {
		// Muzzle flash on the turret that just fired (gun_flip already points at the other one).
		last: f32 = -1 if e.gun_flip else 1
		rl.BeginBlendMode(.ADDITIVE)
		draw_glow(epoint(c, a, r, 0.9, last * 0.55), r * 0.35, rl.Color{255, 170, 90, 255}, 0.9)
		rl.EndBlendMode()
	}
}

// --- Mine pod (Sticky) ---

draw_mine :: proc(e: Enemy, col: rl.Color, t, ph: f32) {
	c, r := e.pos, e.radius
	fast: f32 = 1.0
	if e.stuck do fast = 3.5
	spin := t * 1.4 * fast + ph
	blink := 0.5 + 0.5 * math.sin(t * (7.0 * fast) + ph)

	for i in 0 ..< 8 {
		ang := spin + f32(i) * math.PI / 4
		tip := c + [2]f32{math.cos(ang), math.sin(ang)} * r * 1.55
		b1  := c + [2]f32{math.cos(ang - 0.24), math.sin(ang - 0.24)} * r * 0.9
		b2  := c + [2]f32{math.cos(ang + 0.24), math.sin(ang + 0.24)} * r * 0.9
		draw_tri_ccw(tip, b1, b2, shade(col, 0.7))
	}
	rl.DrawCircleV(c, r * 0.95, shade(col, 0.35))
	rl.DrawCircleLines(i32(c.x), i32(c.y), r * 0.95, rl.Fade(rl.WHITE, 0.5))
	for i in 0 ..< 4 {
		ang := -spin * 1.5 + f32(i) * math.PI / 2
		rl.DrawCircleV(c + [2]f32{math.cos(ang), math.sin(ang)} * r * 0.65, r * 0.1, rl.Fade(rl.WHITE, 0.8))
	}
	rl.BeginBlendMode(.ADDITIVE)
	rl.DrawCircleV(c, r * (0.38 + 0.14 * blink), rl.Fade(col, 0.95))
	rl.EndBlendMode()
}

// --- Whales (Minion + Boss) ---

WHALE_HULL :: [14][2]f32{
	{1.35, 0.05}, {1.1, -0.42}, {0.45, -0.78}, {-0.3, -0.72}, {-0.85, -0.4}, {-1.15, -0.16}, {-1.55, -0.72},
	{-1.3, 0.0}, {-1.55, 0.72}, {-1.15, 0.16}, {-0.85, 0.38}, {-0.3, 0.68}, {0.45, 0.72}, {1.1, 0.42},
}

// The tail half of the body swings side to side.
whale_pt :: proc(c: [2]f32, a, k, sway, x, y: f32) -> [2]f32 {
	yy := y
	if x < -0.9 do yy += sway * (-x - 0.9)
	return epoint(c, a, k, x, yy)
}

draw_whale :: proc(c: [2]f32, a, k: f32, body: rl.Color, t, ph: f32, boss: bool) {
	belly := tint_up(body, 0.55)
	back  := shade(body, 0.7)
	sway  := 0.32 * math.sin(t * 3.2 + ph)

	local := WHALE_HULL
	hull: [14][2]f32
	for p, i in local do hull[i] = whale_pt(c, a, k, sway, p.x, p.y)
	draw_fan_ccw(epoint(c, a, k, 0, 0), hull[:], body)

	// Darker back, pale belly.
	bo := [4][2]f32{{1.1, -0.42}, {0.45, -0.78}, {-0.3, -0.72}, {-0.85, -0.4}}
	bi := [4][2]f32{{1.0, -0.2}, {0.4, -0.38}, {-0.3, -0.34}, {-0.85, -0.2}}
	lo := [4][2]f32{{1.1, 0.42}, {0.45, 0.72}, {-0.3, 0.68}, {-0.85, 0.38}}
	li := [4][2]f32{{1.0, 0.12}, {0.4, 0.22}, {-0.3, 0.18}, {-0.85, 0.12}}
	for i in 0 ..< 3 {
		draw_quad_ccw(epoint(c, a, k, bo[i].x, bo[i].y), epoint(c, a, k, bo[i + 1].x, bo[i + 1].y), epoint(c, a, k, bi[i + 1].x, bi[i + 1].y), epoint(c, a, k, bi[i].x, bi[i].y), back)
		draw_quad_ccw(epoint(c, a, k, lo[i].x, lo[i].y), epoint(c, a, k, lo[i + 1].x, lo[i + 1].y), epoint(c, a, k, li[i + 1].x, li[i + 1].y), epoint(c, a, k, li[i].x, li[i].y), belly)
	}

	// Pectoral fin, eye, mouth line.
	flap := 0.12 * math.sin(t * 3.2 + ph + 1.2)
	draw_tri_ccw(epoint(c, a, k, 0.3, 0.5), epoint(c, a, k, -0.35, 1.0 + flap), epoint(c, a, k, -0.45, 0.4), shade(body, 0.6))
	draw_poly_outline(hull[:], rl.Fade(rl.WHITE, 0.3))
	rl.DrawLineV(epoint(c, a, k, 1.3, 0.14), epoint(c, a, k, 0.7, 0.22), rl.Fade(rl.BLACK, 0.6))
	eye := epoint(c, a, k, 0.85, -0.12)
	rl.DrawCircleV(eye, k * 0.1, rl.WHITE)
	rl.DrawCircleV(eye, k * 0.055, rl.Color{20, 10, 40, 255})

	if boss {
		// Bioluminescent runes along the back - the mothership glow.
		rl.BeginBlendMode(.ADDITIVE)
		for i in 0 ..< 5 {
			x := 0.75 - f32(i) * 0.4
			col := rl.Color{255, 90, 200, 255}
			if i % 2 == 1 do col = rl.Color{90, 220, 255, 255}
			pulse := 0.5 + 0.5 * math.sin(t * 4 + f32(i) * 1.3)
			rl.DrawCircleV(whale_pt(c, a, k, sway, x, -0.52), k * (0.07 + 0.04 * pulse), rl.Fade(col, 0.55 + 0.4 * pulse))
		}
		rl.EndBlendMode()
	}
}

// --- Mothership (Boss skin) + Drone (its Minion) ---

MOTHERSHIP_HULL :: [12][2]f32{
	{1.45, 0}, {1.15, -0.5}, {0.55, -0.88}, {-0.2, -1.0}, {-0.9, -0.85}, {-1.3, -0.45},
	{-1.4, 0}, {-1.3, 0.45}, {-0.9, 0.85}, {-0.2, 1.0}, {0.55, 0.88}, {1.15, 0.5},
}

draw_mothership :: proc(e: Enemy, k: f32, body: rl.Color, t, ph: f32) {
	c, a := e.pos, e.angle
	hot := e.enraged
	a1 := rl.Color{255, 90, 200, 255}
	a2 := rl.Color{90, 220, 255, 255}
	if hot {
		a1 = rl.Color{255, 70, 50, 255}
		a2 = rl.Color{255, 190, 70, 255}
	}

	// Three rear engines.
	flick := 0.75 + 0.25 * math.sin(t * 30 + ph)
	for y in ([3]f32{-0.55, 0, 0.55}) {
		draw_exhaust(c, a, k, -1.35, y, 0.2, (1.1 if y == 0 else 0.8) * flick, a2)
	}

	local := MOTHERSHIP_HULL
	hull:  [12][2]f32
	deck:  [12][2]f32
	for p, i in local {
		hull[i] = epoint(c, a, k, p.x, p.y)
		deck[i] = epoint(c, a, k, p.x * 0.7, p.y * 0.7)
	}
	draw_fan_ccw(c, hull[:], body)
	draw_fan_ccw(c, deck[:], shade(body, 0.5))
	draw_poly_outline(hull[:], rl.Fade(rl.WHITE, 0.4))
	draw_poly_outline(deck[:], rl.Fade(rl.WHITE, 0.15))

	// Twin gun pods on the front shoulders; the one that just fired flashes.
	for side in ([2]f32{-1, 1}) {
		base := epoint(c, a, k, 0.8, side * 0.6)
		tip  := epoint(c, a, k, 1.2, side * 0.6)
		rl.DrawLineEx(base, tip, max(2.0, k * 0.12), rl.Color{25, 25, 40, 255})
		rl.DrawCircleV(base, k * 0.15, rl.Color{25, 25, 40, 255})
		rl.DrawCircleLines(i32(base.x), i32(base.y), k * 0.15, rl.Fade(rl.WHITE, 0.45))
	}
	if e.gun_ticks >= MOTHERSHIP_BULLET_COOLDOWN_TICKS - 3 {
		last: f32 = -1 if e.gun_flip else 1
		rl.BeginBlendMode(.ADDITIVE)
		draw_glow(epoint(c, a, k, 1.2, last * 0.6), k * 0.3, rl.Color{255, 170, 90, 255}, 0.9)
		rl.EndBlendMode()
	}

	// Dome with a glint, and a ring of chasing lights around the rim.
	dome := epoint(c, a, k, -0.1, 0)
	rl.DrawCircleV(dome, k * 0.42, rl.Color{12, 14, 34, 255})
	rl.DrawCircleV(dome, k * 0.32, rl.Fade(a2, 0.55))
	rl.DrawCircleLines(i32(dome.x), i32(dome.y), k * 0.42, rl.Fade(rl.WHITE, 0.5))
	rl.DrawCircleV(epoint(c, a, k, -0.02, -0.12), k * 0.08, rl.Fade(rl.WHITE, 0.9))

	rl.BeginBlendMode(.ADDITIVE)
	for i in 0 ..< 10 {
		ang := f32(i) * (2.0 * math.PI / 10.0)
		pulse := 0.5 + 0.5 * math.sin(t * 6 - f32(i) * 0.9)
		lp := epoint(c, a, k, math.cos(ang) * 1.12, math.sin(ang) * 0.8)
		rl.DrawCircleV(lp, k * (0.05 + 0.03 * pulse), rl.Fade(a1 if i % 2 == 0 else a2, 0.45 + 0.5 * pulse))
	}

	// Front emitter: charges while the raygun aims, blazes while it fires.
	charge: f32 = 0
	if e.ray_charge > 0 do charge = 1.0 - f32(e.ray_charge) / f32(RAY_CHARGE_TICKS)
	if e.ray_ticks > 0 do charge = 1
	lens := epoint(c, a, k, 1.38, 0)
	draw_glow(lens, k * (0.16 + 0.42 * charge), RAYGUN_COLOR, 0.35 + 0.65 * charge)
	rl.DrawCircleV(lens, k * (0.06 + 0.06 * charge), rl.Fade(rl.WHITE, 0.55 + 0.45 * charge))
	rl.EndBlendMode()
}

draw_drone :: proc(e: Enemy, col: rl.Color, t, ph: f32) {
	c, a, r := e.pos, e.angle, e.radius
	flick := 0.75 + 0.25 * math.sin(t * 36 + ph)
	draw_exhaust(c, a, r, -1.0, 0, 0.3, 1.1 * flick, rl.Color{140, 200, 255, 255})

	// A little flying saucer: side fins, disc, glowing core.
	for side in ([2]f32{-1, 1}) {
		draw_tri_ccw(epoint(c, a, r, 0.1, side * 0.8), epoint(c, a, r, -0.9, side * 1.5), epoint(c, a, r, -0.9, side * 0.6), shade(col, 0.6))
	}
	disc := [8][2]f32{{1.35, 0}, {0.95, -0.72}, {0, -1.0}, {-0.95, -0.72}, {-1.2, 0}, {-0.95, 0.72}, {0, 1.0}, {0.95, 0.72}}
	pts: [8][2]f32
	for p, i in disc do pts[i] = epoint(c, a, r, p.x, p.y)
	draw_fan_ccw(c, pts[:], col)
	draw_poly_outline(pts[:], rl.Fade(rl.WHITE, 0.4))
	rl.DrawCircleV(epoint(c, a, r, 0.1, 0), r * 0.38, rl.Color{12, 14, 34, 255})
	blink := 0.5 + 0.5 * math.sin(t * 9 + ph)
	rl.BeginBlendMode(.ADDITIVE)
	rl.DrawCircleV(epoint(c, a, r, 0.1, 0), r * (0.2 + 0.1 * blink), rl.Fade(rl.WHITE, 0.9))
	rl.EndBlendMode()
}

// --- Dispatcher ---

// --- Asteroid ---

draw_asteroid :: proc(e: Enemy, col: rl.Color, ph: f32) {
	n :: 10
	pts: [n][2]f32
	for i in 0 ..< n {
		a := f32(i) / f32(n) * 2 * math.PI + e.angle
		k := 0.78 + 0.22 * math.sin(f32(i) * 2.3 + ph * 3.1) + 0.08 * math.sin(f32(i) * 5.1 + ph)
		pts[i] = e.pos + [2]f32{math.cos(a), math.sin(a)} * e.radius * k
	}
	draw_fan_ccw(e.pos, pts[:], shade(col, 0.75))
	// lit side + craters
	lit := e.pos + rotate_vec({-0.2, -0.25}, e.angle) * e.radius
	rl.DrawCircleV(lit, e.radius * 0.45, shade(col, 0.95))
	rl.DrawCircleV(e.pos + rotate_vec({0.35, 0.2}, e.angle) * e.radius, e.radius * 0.2, shade(col, 0.5))
	rl.DrawCircleV(e.pos + rotate_vec({-0.4, 0.4}, e.angle) * e.radius, e.radius * 0.14, shade(col, 0.55))
	draw_poly_outline(pts[:], rl.Fade(rl.WHITE, 0.3))
}

// Frozen enemies (Freeze skill) are drawn through the ice shader. Text must NOT be drawn inside it.
begin_ice :: proc(g: ^Game, on: bool) {
	if on do rl.BeginShaderMode(g.shaders.freeze.shader)
}

end_ice :: proc(on: bool) {
	if on do rl.EndShaderMode()
}

draw_enemies :: proc(g: ^Game) {
	frozen := g.freeze_ticks > 0
	t := g.time
	if frozen {
		t = g.freeze_time // frozen things stop animating (tails, flames, spinning mines)
		set_freeze_shader(g.shaders.freeze, g.time, freeze_amount(g))
	}
	for e, idx in g.enemies {
		if !e.active do continue
		ph := f32(idx) * 1.7
		col := e.color
		if e.flash > 0 do col = rl.WHITE

		switch e.kind {
		case .Normal:
			begin_ice(g, frozen)
			draw_raider(e, col, t, ph)
			end_ice(frozen)
		case .Asteroid:
			begin_ice(g, frozen)
			draw_asteroid(e, col, ph)
			end_ice(frozen)
		case .Runner:
			begin_ice(g, frozen)
			draw_rocket(e, col, t, ph)
			end_ice(frozen)
		case .Big:
			begin_ice(g, frozen)
			draw_cruiser(e, col, t, ph)
			end_ice(frozen)
		case .Sticky:
			begin_ice(g, frozen)
			draw_mine(e, col, t, ph)
			end_ice(frozen)
			ex, ey := i32(e.pos.x), i32(e.pos.y)
			if e.stuck {
				blink := 0.55 + 0.45 * math.sin(f32(e.stick_ticks) * 5.0)
				rl.DrawCircleLines(ex, ey, STICKY_EXPLOSION_RADIUS, rl.Fade(rl.Color{255, 90, 210, 255}, 0.35 + 0.25 * blink))
				rl.DrawText(fmt.ctprintf("%d", e.stick_ticks), ex - 4, ey - 6, 12, rl.WHITE)
			} else {
				rl.DrawCircleLines(ex, ey, e.radius * 1.9, rl.Fade(rl.Color{255, 210, 100, 255}, 0.55))
			}
		case .Minion:
			begin_ice(g, frozen)
			if e.skin == .Mothership {
				draw_drone(e, col, t, ph)
			} else {
				draw_whale(e.pos, e.angle, e.radius * 0.95, col, t, ph, false)
			}
			end_ice(frozen)
		case .Boss:
			// Draw every screen-wrapped copy that is visible, so the whale slides
			// seamlessly out of one edge and into the opposite one.
			margin := e.radius * 1.9
			for ox in ([3]f32{0, SCREEN_W, -SCREEN_W}) {
				for oy in ([3]f32{0, SCREEN_H, -SCREEN_H}) {
					ge := e
					ge.pos = e.pos + [2]f32{ox, oy}
					if ge.pos.x < -margin || ge.pos.x > SCREEN_W + margin do continue
					if ge.pos.y < -margin || ge.pos.y > SCREEN_H + margin do continue
					body := col
					if e.enraged && e.flash <= 0 do body = rl.Color{210, 50, 70, 255}
					begin_ice(g, frozen)
					if e.skin == .Mothership {
						draw_mothership(ge, e.radius * 0.9, body, t, ph)
					} else {
						draw_whale(ge.pos, ge.angle, e.radius * 0.85, body, t, ph, true)
					}
					end_ice(frozen)
					draw_boss_extras(g, ge)
				}
			}
		}
	}
}
