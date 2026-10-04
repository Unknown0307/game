package main

import rl "vendor:raylib"

// =============================================================================
// toon.odin - the shared "cartoon" look used by every skin in the game
// (ships, enemies, bosses, minions, pickups).
//
// The rules, so everything matches:
//   * flat fills (no gradients, no shader detail) with a slightly darker second tone
//   * one dark ink outline, always TOON_W thick, with rounded corners
//   * one round glass/gem "eye" (with a white glint) as the only fine detail
//   * glows and flames stay soft and additive; they are the only non-flat parts
// =============================================================================

TOON_LINE :: rl.Color{16, 14, 34, 255}
TOON_W    :: 2.0

// Dark ink outline around a closed polygon; discs on the corners round the joints.
toon_outline :: proc(pts: [][2]f32, th: f32 = TOON_W) {
	n := len(pts)
	for i in 0 ..< n {
		rl.DrawLineEx(pts[i], pts[(i + 1) % n], th, TOON_LINE)
		rl.DrawCircleV(pts[i], th * 0.5, TOON_LINE)
	}
}

// Filled star-shaped polygon (fan around `center`) plus its outline.
toon_poly :: proc(center: [2]f32, pts: [][2]f32, col: rl.Color) {
	draw_fan_ccw(center, pts, col)
	toon_outline(pts)
}

// Flat disc with an ink rim.
toon_disc :: proc(c: [2]f32, r: f32, col: rl.Color) {
	rl.DrawCircleV(c, r, TOON_LINE)
	rl.DrawCircleV(c, max(r - TOON_W * 0.8, 0.5), col)
}

// Disc with a small white glint: the one "eye" detail every skin gets.
toon_gem :: proc(c: [2]f32, r: f32, col: rl.Color) {
	toon_disc(c, r, col)
	rl.DrawCircleV(c + [2]f32{-r * 0.3, -r * 0.3}, max(r * 0.28, 0.8), rl.Fade(rl.WHITE, 0.95))
}

// Thick ink-edged stroke (gun barrels, fins, bars).
toon_stroke :: proc(a, b: [2]f32, th: f32, col: rl.Color) {
	rl.DrawLineEx(a, b, th + TOON_W * 1.2, TOON_LINE)
	rl.DrawCircleV(a, (th + TOON_W * 1.2) * 0.5, TOON_LINE)
	rl.DrawCircleV(b, (th + TOON_W * 1.2) * 0.5, TOON_LINE)
	rl.DrawLineEx(a, b, th, col)
	rl.DrawCircleV(a, th * 0.5, col)
	rl.DrawCircleV(b, th * 0.5, col)
}

// Flat quad with an ink outline.
toon_quad :: proc(a, b, c, d: [2]f32, col: rl.Color) {
	draw_quad_ccw(a, b, c, d, col)
	pts := [4][2]f32{a, b, c, d}
	toon_outline(pts[:])
}

// Second tone / highlight tone for a flat fill. A hurt-flash (pure white) stays pure white.
toon_dark :: proc(c: rl.Color) -> rl.Color {
	if c.r == 255 && c.g == 255 && c.b == 255 do return c
	return shade(c, 0.72)
}

toon_light :: proc(c: rl.Color) -> rl.Color {
	if c.r == 255 && c.g == 255 && c.b == 255 do return c
	return tint_up(c, 0.45)
}
