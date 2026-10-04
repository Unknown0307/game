package main

import "core:fmt"
import "core:math"
import rl "vendor:raylib"

// =============================================================================
// enemy_art.odin - the look of every enemy, in the shared cartoon style (toon.odin). All shapes are built from triangles
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

	// A simple arrowhead: flat fill, darker lower half, a light glint, ink outline, one gem.
	hull := [4][2]f32{epoint(c, a, r, 1.4, 0), epoint(c, a, r, -0.9, -1.05), epoint(c, a, r, -0.5, 0), epoint(c, a, r, -0.9, 1.05)}
	draw_fan_ccw(c, hull[:], col)
	draw_tri_ccw(hull[0], hull[3], hull[2], toon_dark(col))
	draw_tri_ccw(epoint(c, a, r, 1.0, -0.05), epoint(c, a, r, -0.3, -0.55), epoint(c, a, r, -0.2, -0.05), toon_light(col))
	toon_outline(hull[:])
	toon_gem(epoint(c, a, r, 0.3, 0), r * 0.22, rl.Color{255, 235, 130, 255})
}

// --- Rocket / drone (Runner) ---

draw_rocket :: proc(e: Enemy, col: rl.Color, t, ph: f32) {
	c, a, r := e.pos, e.angle, e.radius
	draw_exhaust(c, a, r, -1.25, 0, 0.32, 1.3 + 0.5 * math.sin(t * 40 + ph), rl.Color{255, 150, 40, 255})

	// Two fins, a rounded body with a dark band, a pale nose cone and a porthole.
	for side in ([2]f32{-1, 1}) {
		fin := [3][2]f32{epoint(c, a, r, -0.55, side * 0.34), epoint(c, a, r, -1.3, side * 1.05), epoint(c, a, r, -1.3, side * 0.34)}
		draw_tri_ccw(fin[0], fin[1], fin[2], toon_dark(col))
		toon_outline(fin[:])
	}
	toon_quad(epoint(c, a, r, 0.85, -0.38), epoint(c, a, r, 0.85, 0.38), epoint(c, a, r, -1.3, 0.38), epoint(c, a, r, -1.3, -0.38), col)
	toon_quad(epoint(c, a, r, -0.5, -0.38), epoint(c, a, r, -0.5, 0.38), epoint(c, a, r, -0.9, 0.38), epoint(c, a, r, -0.9, -0.38), toon_dark(col))
	nose := [3][2]f32{epoint(c, a, r, 1.8, 0), epoint(c, a, r, 0.85, -0.38), epoint(c, a, r, 0.85, 0.38)}
	draw_tri_ccw(nose[0], nose[1], nose[2], rl.Color{240, 240, 245, 255})
	toon_outline(nose[:])
	toon_gem(epoint(c, a, r, 0.3, 0), r * 0.2, rl.SKYBLUE)
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
		inner[i] = epoint(c, a, r, p.x * 0.6, p.y * 0.6)
	}
	draw_fan_ccw(c, hull[:], col)
	draw_fan_ccw(c, inner[:], toon_dark(col)) // flat darker deck
	toon_outline(hull[:])

	// Twin turrets and a lit bridge.
	barrel := rl.Color{58, 62, 82, 255}
	if e.laser do barrel = rl.Color{30, 90, 120, 255}
	for side in ([2]f32{-1, 1}) {
		base := epoint(c, a, r, 0.15, side * 0.55)
		toon_stroke(base, epoint(c, a, r, 0.85, side * 0.55), max(2.0, r * 0.1), barrel)
		toon_disc(base, r * 0.19, barrel)
	}
	toon_gem(epoint(c, a, r, -0.25, 0), r * 0.2, rl.Color{255, 200, 90, 255})

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

	// Six stubby spikes, a round body and one blinking core.
	for i in 0 ..< 6 {
		ang := spin + f32(i) * math.PI / 3
		spike := [3][2]f32{
			c + [2]f32{math.cos(ang), math.sin(ang)} * r * 1.5,
			c + [2]f32{math.cos(ang - 0.3), math.sin(ang - 0.3)} * r * 0.9,
			c + [2]f32{math.cos(ang + 0.3), math.sin(ang + 0.3)} * r * 0.9,
		}
		draw_tri_ccw(spike[0], spike[1], spike[2], toon_dark(col))
		toon_outline(spike[:])
	}
	toon_disc(c, r * 0.95, col)
	rl.BeginBlendMode(.ADDITIVE)
	rl.DrawCircleV(c, r * (0.34 + 0.12 * blink), rl.Fade(rl.WHITE, 0.55))
	rl.DrawCircleV(c, r * (0.5 + 0.12 * blink), rl.Fade(col, 0.55))
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
	sway  := 0.32 * math.sin(t * 3.2 + ph)

	local := WHALE_HULL
	hull: [14][2]f32
	for p, i in local do hull[i] = whale_pt(c, a, k, sway, p.x, p.y)
	draw_fan_ccw(epoint(c, a, k, 0, 0), hull[:], body)

	// One pale belly patch (flat), a pectoral fin, an ink outline.
	bo := [4][2]f32{{1.1, 0.42}, {0.45, 0.72}, {-0.3, 0.68}, {-0.85, 0.38}}
	bi := [4][2]f32{{1.0, 0.12}, {0.4, 0.22}, {-0.3, 0.18}, {-0.85, 0.12}}
	for i in 0 ..< 3 {
		draw_quad_ccw(epoint(c, a, k, bo[i].x, bo[i].y), epoint(c, a, k, bo[i + 1].x, bo[i + 1].y), epoint(c, a, k, bi[i + 1].x, bi[i + 1].y), epoint(c, a, k, bi[i].x, bi[i].y), belly)
	}
	flap := 0.12 * math.sin(t * 3.2 + ph + 1.2)
	fin := [3][2]f32{epoint(c, a, k, 0.3, 0.5), epoint(c, a, k, -0.35, 1.0 + flap), epoint(c, a, k, -0.45, 0.4)}
	draw_tri_ccw(fin[0], fin[1], fin[2], toon_dark(body))
	toon_outline(fin[:])
	toon_outline(hull[:])

	// Big friendly cartoon eye and a short smile line.
	rl.DrawLineEx(epoint(c, a, k, 1.28, 0.16), epoint(c, a, k, 0.75, 0.24), TOON_W, TOON_LINE)
	eye := epoint(c, a, k, 0.85, -0.14)
	toon_disc(eye, k * 0.15, rl.WHITE)
	rl.DrawCircleV(eye + rotate_vec({k * 0.03, 0}, a), k * 0.065, TOON_LINE)

	if boss {
		// Bioluminescent spots along the back - the mothership glow.
		rl.BeginBlendMode(.ADDITIVE)
		for i in 0 ..< 5 {
			x := 0.75 - f32(i) * 0.4
			col := rl.Color{255, 90, 200, 255}
			if i % 2 == 1 do col = rl.Color{90, 220, 255, 255}
			pulse := 0.5 + 0.5 * math.sin(t * 4 + f32(i) * 1.3)
			rl.DrawCircleV(whale_pt(c, a, k, sway, x, -0.5), k * (0.07 + 0.04 * pulse), rl.Fade(col, 0.55 + 0.4 * pulse))
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
		deck[i] = epoint(c, a, k, p.x * 0.68, p.y * 0.68)
	}
	draw_fan_ccw(c, hull[:], body)
	draw_fan_ccw(c, deck[:], toon_dark(body)) // flat darker deck
	toon_outline(hull[:])

	// Twin gun pods on the front shoulders; the one that just fired flashes.
	pod := rl.Color{58, 62, 82, 255}
	for side in ([2]f32{-1, 1}) {
		base := epoint(c, a, k, 0.8, side * 0.6)
		tip  := epoint(c, a, k, 1.2, side * 0.6)
		toon_stroke(base, tip, max(2.0, k * 0.12), pod)
		toon_disc(base, k * 0.15, pod)
	}
	if e.gun_ticks >= MOTHERSHIP_BULLET_COOLDOWN_TICKS - 3 {
		last: f32 = -1 if e.gun_flip else 1
		rl.BeginBlendMode(.ADDITIVE)
		draw_glow(epoint(c, a, k, 1.2, last * 0.6), k * 0.3, rl.Color{255, 170, 90, 255}, 0.9)
		rl.EndBlendMode()
	}

	// One big dome gem, and six soft rim lights.
	toon_gem(epoint(c, a, k, -0.1, 0), k * 0.4, a2)

	rl.BeginBlendMode(.ADDITIVE)
	for i in 0 ..< 6 {
		ang := f32(i) * (2.0 * math.PI / 6.0) + 0.5
		pulse := 0.5 + 0.5 * math.sin(t * 6 - f32(i) * 1.2)
		lp := epoint(c, a, k, math.cos(ang) * 1.1, math.sin(ang) * 0.8)
		rl.DrawCircleV(lp, k * (0.06 + 0.03 * pulse), rl.Fade(a1 if i % 2 == 0 else a2, 0.5 + 0.45 * pulse))
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

	// A little flying saucer: two fins, a rounded disc, one gem.
	for side in ([2]f32{-1, 1}) {
		fin := [3][2]f32{epoint(c, a, r, 0.1, side * 0.8), epoint(c, a, r, -0.9, side * 1.5), epoint(c, a, r, -0.9, side * 0.6)}
		draw_tri_ccw(fin[0], fin[1], fin[2], toon_dark(col))
		toon_outline(fin[:])
	}
	disc := [8][2]f32{{1.35, 0}, {0.95, -0.72}, {0, -1.0}, {-0.95, -0.72}, {-1.2, 0}, {-0.95, 0.72}, {0, 1.0}, {0.95, 0.72}}
	pts: [8][2]f32
	for p, i in disc do pts[i] = epoint(c, a, r, p.x, p.y)
	draw_fan_ccw(c, pts[:], col)
	toon_outline(pts[:])
	blink := 0.5 + 0.5 * math.sin(t * 9 + ph)
	toon_gem(epoint(c, a, r, 0.1, 0), r * (0.34 + 0.06 * blink), rl.Color{190, 240, 255, 255})
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
	draw_fan_ccw(e.pos, pts[:], shade(col, 0.8))
	// Flat lit patch and two round craters, then the ink outline.
	rl.DrawCircleV(e.pos + rotate_vec({-0.22, -0.25}, e.angle) * e.radius, e.radius * 0.38, toon_light(shade(col, 0.8)))
	rl.DrawCircleV(e.pos + rotate_vec({0.35, 0.2}, e.angle) * e.radius, e.radius * 0.2, shade(col, 0.5))
	rl.DrawCircleV(e.pos + rotate_vec({-0.4, 0.4}, e.angle) * e.radius, e.radius * 0.14, shade(col, 0.5))
	toon_outline(pts[:])
}

// Frozen enemies (Freeze skill) are drawn through the ice shader. Text must NOT be drawn inside it.
begin_ice :: proc(g: ^Game, on: bool) {
	if on do rl.BeginShaderMode(g.shaders.freeze.shader)
}

end_ice :: proc(on: bool) {
	if on do rl.EndShaderMode()
}

// --- Per-type draw hooks (referenced from enemy_def in enemy_defs.odin) ---
// Each one draws its enemy through the ice shader while frozen (text must NOT be drawn inside it).

draw_normal :: proc(g: ^Game, e: Enemy, col: rl.Color, t, ph: f32, frozen: bool) {
	begin_ice(g, frozen)
	draw_raider(e, col, t, ph)
	end_ice(frozen)
}

draw_runner_enemy :: proc(g: ^Game, e: Enemy, col: rl.Color, t, ph: f32, frozen: bool) {
	begin_ice(g, frozen)
	draw_rocket(e, col, t, ph)
	end_ice(frozen)
}

draw_big :: proc(g: ^Game, e: Enemy, col: rl.Color, t, ph: f32, frozen: bool) {
	begin_ice(g, frozen)
	draw_cruiser(e, col, t, ph)
	end_ice(frozen)
}

draw_asteroid_enemy :: proc(g: ^Game, e: Enemy, col: rl.Color, t, ph: f32, frozen: bool) {
	begin_ice(g, frozen)
	draw_asteroid(e, col, ph)
	end_ice(frozen)
}

draw_sticky :: proc(g: ^Game, e: Enemy, col: rl.Color, t, ph: f32, frozen: bool) {
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
}

draw_minion :: proc(g: ^Game, e: Enemy, col: rl.Color, t, ph: f32, frozen: bool) {
	begin_ice(g, frozen)
	if e.skin == .Mothership {
		draw_drone(e, col, t, ph)
	} else {
		draw_whale(e.pos, e.angle, e.radius * 0.95, col, t, ph, false)
	}
	end_ice(frozen)
}

draw_boss :: proc(g: ^Game, e: Enemy, col: rl.Color, t, ph: f32, frozen: bool) {
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

// --- Per-type glow hooks (additive blend is already on) ---

glow_big :: proc(g: ^Game, e: Enemy, t: f32) {
	gcol := rl.RED
	if e.laser do gcol = LASER_COLOR
	draw_glow(e.pos, e.radius * 1.6, gcol, 0.2)
}

glow_sticky :: proc(g: ^Game, e: Enemy, t: f32) {
	scale: f32 = 1.3
	if e.stuck do scale = 1.8
	draw_glow(e.pos, e.radius * scale, rl.Color{255, 80, 210, 255}, 0.28)
}

glow_minion :: proc(g: ^Game, e: Enemy, t: f32) {
	draw_glow(e.pos, e.radius * 1.8, rl.Color{200, 120, 255, 255}, 0.18)
}

glow_boss :: proc(g: ^Game, e: Enemy, t: f32) {
	pulse := 0.5 + 0.5 * math.sin(t * (14 if e.enraged else 8))
	gcol := rl.Color{255, 60, 200, 255}
	if e.enraged do gcol = rl.Color{255, 50, 40, 255}
	draw_glow(e.pos, e.radius * (2.4 if e.enraged else 2.0) + pulse * 10, gcol, 0.55 if e.enraged else 0.45)
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

		draw := enemy_def(e.kind).draw
		if draw != nil do draw(g, e, col, t, ph, frozen)
	}
}
