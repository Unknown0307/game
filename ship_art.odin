package main

import "core:math"
import rl "vendor:raylib"

// =============================================================================
// ship_art.odin - how the two player ships look. Both use the shared cartoon style
// (toon.odin): flat colour, dark outline, one glass gem, soft glowing trails.
//
//   P1 (Fighter)     "Spear": the tip of a spear - a leaf-shaped blade with swept barbs
//                    and a short socket. Blue, two-tone, one cockpit gem. One booster
//                    flame plus a layered ribbon and glowing puffs as its trail.
//   P2 (Interceptor) "Hauler": a triangular sci-fi cargo ship - a wedge hull, two stacked
//                    cargo crates on the back half, a cockpit gem and two engine pods
//                    with twin ribbons.
// =============================================================================

ship_pt :: proc(c: [2]f32, x, y, a: f32) -> [2]f32 {
	return rotate_ship_point(c, {x, y}, a)
}

// Local position in "ship units" (1 unit = u pixels), x = forward.
at :: proc(c: [2]f32, a, u, x, y: f32) -> [2]f32 {
	return ship_pt(c, x * u, y * u, a)
}

// Adds the current position to the ship's ribbon history (call once per frame).
push_trail :: proc(p: ^Player) {
	for i := len(p.trail) - 1; i > 0; i -= 1 {
		p.trail[i] = p.trail[i - 1]
	}
	p.trail[0] = player_center(p^)
	p.trail_n = min(p.trail_n + 1, len(p.trail))
}

// Soft additive ribbon that follows the ship's recent path and tapers away.
draw_ribbon :: proc(p: Player, side_off, width: f32, col: rl.Color, alpha: f32, max_n: int = PLAYER_TRAIL_LENGTH) {
	n := min(p.trail_n, max_n)
	if n < 2 do return
	rl.BeginBlendMode(.ADDITIVE)
	for i in 0 ..< n - 1 {
		a := p.trail[i]
		b := p.trail[i + 1]
		d := b - a
		l := math.sqrt(d.x * d.x + d.y * d.y)
		if l < 0.01 do continue
		nrm := [2]f32{-d.y, d.x} / l
		k0 := 1.0 - f32(i) / f32(n)
		k1 := 1.0 - f32(i + 1) / f32(n)
		a2 := a + nrm * side_off
		b2 := b + nrm * side_off
		draw_quad_ccw(a2 + nrm * width * k0, a2 - nrm * width * k0, b2 - nrm * width * k1, b2 + nrm * width * k1, rl.Fade(col, alpha * k0 * k0))
	}
	rl.EndBlendMode()
}

// Round glowing puffs left along the recent path (cartoon "smoke"), shrinking and fading.
draw_trail_puffs :: proc(p: Player, side_off, size: f32, col: rl.Color, alpha: f32, max_n: int = PLAYER_TRAIL_LENGTH) {
	n := min(p.trail_n, max_n)
	if n < 4 do return
	rl.BeginBlendMode(.ADDITIVE)
	for i := 2; i < n - 1; i += 3 {
		d := p.trail[i + 1] - p.trail[i - 1]
		l := math.sqrt(d.x * d.x + d.y * d.y)
		if l < 0.01 do continue
		nrm := [2]f32{-d.y, d.x} / l
		k := 1.0 - f32(i) / f32(n)
		pos := p.trail[i] + nrm * side_off
		rl.DrawCircleV(pos, size * (0.35 + 0.65 * k), rl.Fade(col, alpha * k))
		rl.DrawCircleV(pos, size * 0.4 * k, rl.Fade(rl.WHITE, alpha * 0.8 * k))
	}
	rl.EndBlendMode()
}

// Three stacked flame cones (outer colour, inner colour, white core) plus a
// bloom at the nozzle. x/y/width/length are local pixel offsets.
draw_plume :: proc(c: [2]f32, a, x, y, width, length: f32, outer, inner: rl.Color) {
	rl.BeginBlendMode(.ADDITIVE)
	draw_tri_ccw(ship_pt(c, x, y - width, a), ship_pt(c, x, y + width, a), ship_pt(c, x - length, y, a), rl.Fade(outer, 0.45))
	draw_tri_ccw(ship_pt(c, x, y - width * 0.6, a), ship_pt(c, x, y + width * 0.6, a), ship_pt(c, x - length * 0.72, y, a), rl.Fade(inner, 0.75))
	draw_tri_ccw(ship_pt(c, x, y - width * 0.28, a), ship_pt(c, x, y + width * 0.28, a), ship_pt(c, x - length * 0.42, y, a), rl.Fade(rl.WHITE, 0.95))
	rl.DrawCircleV(ship_pt(c, x, y, a), width * 1.5, rl.Fade(outer, 0.30))
	rl.DrawCircleV(ship_pt(c, x, y, a), width * 0.8, rl.Fade(rl.WHITE, 0.55))
	rl.EndBlendMode()
}

// -----------------------------------------------------------------------------
// P1 - Spear
// -----------------------------------------------------------------------------
SPEAR_GLOW :: rl.Color{90, 170, 255, 255}

// Local outline (x = forward, scaled by half-length; y scaled by half-width). The blade
// widens to two swept barbs, then narrows to a socket. Star-shaped around the origin.
SPEAR_HULL :: [9][2]f32{
	{2.1, 0}, {0.5, -0.55}, {-0.45, -0.7}, {-0.25, -0.22}, {-1.0, -0.22},
	{-1.0, 0.22}, {-0.25, 0.22}, {-0.45, 0.7}, {0.5, 0.55},
}

draw_ship_spear :: proc(g: ^Game, p: Player, col: rl.Color, s: f32) {
	t := g.time
	c := player_center(p)
	a := p.angle
	hw := p.size.x * 0.5 * s
	hh := p.size.y * 0.5 * s
	thr := p.thrust

	// The hurt flash (col == white) turns the whole ship white.
	flashing := col.r == 255 && col.g == 255 && col.b == 255
	light := tint_up(col, 0.5)
	dark  := shade(col, 0.72)
	if flashing {
		light = rl.WHITE
		dark = rl.WHITE
	}

	// 1. Trail: a layered ribbon (wide soft blue -> bright blue -> white core) and puffs.
	draw_ribbon(p, 0, hh * 0.85, rl.Color{50, 100, 255, 255}, 0.30)
	draw_ribbon(p, 0, hh * 0.50, SPEAR_GLOW, 0.38)
	draw_ribbon(p, 0, hh * 0.18, rl.WHITE, 0.55)
	draw_trail_puffs(p, 0, hh * 0.55, SPEAR_GLOW, 0.55)

	// 2. One booster flame out of the socket (the two thin wing jets are gone).
	flame := (26 + 90 * thr) * s
	draw_booster(g.shaders.booster, ship_pt(c, -hw * 0.95, 0, a), g.shake_off, a, flame, hh * (0.36 + 0.10 * thr), thr, t, 0.0)

	// 3. Blade: flat fill, darker lower half, a light glint, ink outline.
	local := SPEAR_HULL
	hull: [9][2]f32
	for q, i in local do hull[i] = ship_pt(c, q.x * hw, q.y * hh, a)
	draw_fan_ccw(c, hull[:], col)

	lower := [6][2]f32{hull[0], hull[8], hull[7], hull[6], hull[5], ship_pt(c, -hw, 0, a)}
	draw_fan_ccw(c, lower[:], dark)
	draw_tri_ccw(ship_pt(c, hw * 1.55, -hh * 0.04, a), ship_pt(c, hw * 0.45, -hh * 0.36, a), ship_pt(c, hw * 0.0, -hh * 0.06, a), light)
	toon_outline(hull[:])
	rl.DrawLineEx(ship_pt(c, -hw * 0.62, -hh * 0.22, a), ship_pt(c, -hw * 0.62, hh * 0.22, a), TOON_W, TOON_LINE) // socket band

	// 4. Gun nubs on the barbs' shoulders (muzzle matches muzzle_local), with a flash when firing.
	for si in 0 ..< 2 {
		side: f32 = -1 if si == 0 else 1
		muzzle := ship_pt(c, hw * 0.5, side * hh * 0.55, a)
		toon_disc(muzzle, hh * 0.17, dark if !flashing else rl.WHITE)
		if p.muzzle_flash[si] > 0 {
			k := p.muzzle_flash[si] / 0.09
			rl.BeginBlendMode(.ADDITIVE)
			draw_glow(muzzle, hh * (0.3 + 0.35 * k), SPEAR_GLOW, 0.9)
			rl.DrawCircleV(muzzle, hh * 0.14 * k, rl.WHITE)
			rl.EndBlendMode()
		}
	}

	// 5. Cockpit gem.
	toon_gem(ship_pt(c, hw * 0.3, 0, a), hh * 0.24, rl.Color{190, 240, 255, 255})

	// 6. A soft glint at the tip.
	pulse := 0.5 + 0.5 * math.sin(t * 6)
	rl.BeginBlendMode(.ADDITIVE)
	rl.DrawCircleV(hull[0], (1.4 + 0.8 * pulse) * s, rl.Fade(rl.WHITE, 0.7))
	rl.EndBlendMode()
}

// -----------------------------------------------------------------------------
// P2 - Hauler (triangular cargo ship)
// -----------------------------------------------------------------------------
draw_ship_hauler :: proc(g: ^Game, p: Player, col: rl.Color, s: f32) {
	t := g.time
	c := player_center(p)
	a := p.angle
	u := max(p.size.x, p.size.y) * 0.5 * s
	thr := p.thrust

	flashing := col.r == 255 && col.g == 255 && col.b == 255
	amber := rl.Color{255, 176, 40, 255}
	crate := rl.Color{255, 200, 80, 255}
	crate_dark := rl.Color{214, 140, 40, 255}
	steel := rl.Color{92, 108, 128, 255}
	dark := shade(col, 0.72)
	if flashing {
		crate = rl.WHITE
		crate_dark = rl.WHITE
		steel = rl.WHITE
		dark = rl.WHITE
	}

	// 1. Trail: a wide ribbon + puffs off each engine pod (green and amber).
	// (ribbon side offsets are mirrored: +offset lands on the ship's -y side, where the amber pod is)
	draw_ribbon(p, u * 0.55, u * 0.30, amber, 0.40, PLAYER2_TRAIL_LENGTH)
	draw_ribbon(p, -u * 0.55, u * 0.30, col, 0.40, PLAYER2_TRAIL_LENGTH)
	draw_ribbon(p, u * 0.55, u * 0.10, rl.WHITE, 0.45, PLAYER2_TRAIL_LENGTH)
	draw_ribbon(p, -u * 0.55, u * 0.10, rl.WHITE, 0.45, PLAYER2_TRAIL_LENGTH)
	draw_trail_puffs(p, u * 0.55, u * 0.38, amber, 0.5, PLAYER2_TRAIL_LENGTH)
	draw_trail_puffs(p, -u * 0.55, u * 0.38, col, 0.5, PLAYER2_TRAIL_LENGTH)

	// 2. Two engine flames (flat cones).
	flick := 0.85 + 0.15 * math.sin(t * 41) + 0.08 * math.sin(t * 67)
	flame := (10 + 36 * thr) * flick * s
	for side in ([2]f32{-1, 1}) {
		draw_plume(c, a, -u * 1.22, side * u * 0.55, u * 0.17, flame, amber if side < 0 else col, rl.Color{255, 240, 170, 255})
	}

	// 3. Engine pods behind the hull.
	for side in ([2]f32{-1, 1}) {
		toon_quad(at(c, a, u, -0.98, side * 0.55 - 0.2), at(c, a, u, -0.98, side * 0.55 + 0.2), at(c, a, u, -1.24, side * 0.55 + 0.15), at(c, a, u, -1.24, side * 0.55 - 0.15), steel)
	}

	// 4. Triangle hull: flat fill, darker lower half, outline.
	hull := [3][2]f32{at(c, a, u, 1.55, 0), at(c, a, u, -1.0, -1.0), at(c, a, u, -1.0, 1.0)}
	draw_fan_ccw(c, hull[:], col)
	draw_tri_ccw(hull[0], hull[2], at(c, a, u, -1.0, 0), dark)
	toon_outline(hull[:])

	// 5. Two stacked cargo crates on the back half.
	for side in ([2]f32{-1, 1}) {
		y0 := side * 0.06
		y1 := side * 0.60
		toon_quad(at(c, a, u, -0.90, y0), at(c, a, u, -0.90, y1), at(c, a, u, -0.30, y1), at(c, a, u, -0.30, y0), crate)
		toon_quad(at(c, a, u, -0.90, y0), at(c, a, u, -0.90, y1), at(c, a, u, -0.62, y1), at(c, a, u, -0.62, y0), crate_dark)
	}

	// 6. Guns on the nose edges (muzzle matches muzzle_local), with a flash when firing.
	for si in 0 ..< 2 {
		side: f32 = -1 if si == 0 else 1
		root   := at(c, a, u, 0.35, side * 0.30)
		muzzle := at(c, a, u, 0.95, side * 0.30)
		toon_stroke(root, muzzle, max(2.0, u * 0.13), steel)
		if p.muzzle_flash[si] > 0 {
			k := p.muzzle_flash[si] / 0.09
			rl.BeginBlendMode(.ADDITIVE)
			draw_glow(muzzle, u * (0.35 + 0.4 * k), amber, 0.9)
			rl.DrawCircleV(muzzle, u * 0.16 * k, rl.WHITE)
			rl.EndBlendMode()
		}
	}

	// 7. Cockpit gem.
	toon_gem(at(c, a, u, 0.62, 0), u * 0.22, rl.Color{190, 240, 255, 255})
}
