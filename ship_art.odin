package main

import "core:math"
import rl "vendor:raylib"

// =============================================================================
// ship_art.odin - how the two player ships look.
//
//   P1 (Fighter)     "Dart": one clean arrow hull, deliberately simple. The
//                    detail goes into the effects: a LONG fading ribbon trail,
//                    two short gun nozzles in the wings,
//                    a layered flickering plume with shock diamonds, vapour
//                    streaks off the wing tips and a pulsing energy edge.
//   P2 (Interceptor) "Bulwark": a twin-boom armoured gunship. Heavy plating,
//                    amber warning stripes, forward gun booms, a spinning
//                    radar dish and a reactor core with orbiting lights.
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
// P1 - Dart
// -----------------------------------------------------------------------------
draw_ship_dart :: proc(g: ^Game, p: Player, col: rl.Color, s: f32) {
	t := g.time
	c := player_center(p)
	a := p.angle
	hw := p.size.x * 0.5 * s
	hh := p.size.y * 0.5 * s
	thr := p.thrust

	ice := rl.Color{130, 215, 255, 255}

	nose  := ship_pt(c, hw * 1.45, 0, a)
	tip_l := ship_pt(c, -hw * 0.95, -hh * 1.05, a)
	tip_r := ship_pt(c, -hw * 0.95, hh * 1.05, a)
	notch := ship_pt(c, -hw * 0.55, 0, a)
	sh_l  := ship_pt(c, hw * 0.05, -hh * 0.30, a)
	sh_r  := ship_pt(c, hw * 0.05, hh * 0.30, a)

	// 1. Long ribbon trail (underneath everything): a wide soft one, a thin bright
	//    core and a faint twin streak off each wing. All of it fades toward the tail.
	draw_ribbon(p, 0, hh * 0.75, ice, 0.30)
	draw_ribbon(p, 0, hh * 0.28, rl.WHITE, 0.30)
	draw_ribbon(p, -hh * 0.62, hh * 0.12, ice, 0.22)
	draw_ribbon(p, hh * 0.62, hh * 0.12, ice, 0.22)

	// 2. Plume: length follows the throttle and flickers.
	flick := 0.8 + 0.2 * math.sin(t * 47) + 0.1 * math.sin(t * 73)
	plume := (7 + 36 * thr) * flick * s
	draw_plume(c, a, -hw * 0.5, 0, hh * (0.26 + 0.1 * thr), plume, ice, rl.Color{120, 170, 255, 255})

	// Shock diamonds along the plume when under power.
	if thr > 0.15 {
		rl.BeginBlendMode(.ADDITIVE)
		for i in 0 ..< 3 {
			fi := f32(i)
			pos := ship_pt(c, -hw * 0.5 - plume * (0.28 + 0.24 * fi), 0, a)
			pulse := 0.5 + 0.5 * math.sin(t * 30 - fi * 1.7)
			rl.DrawCircleV(pos, hh * (0.16 - 0.035 * fi) * (0.7 + 0.5 * pulse), rl.Fade(rl.WHITE, thr * (0.55 - 0.12 * fi)))
		}
		rl.EndBlendMode()
	}

	// 2b. Energy aura (shader): a pulsing halo with two rings of rotating arcs around the ship.
	draw_ship_aura(g.shaders.aura, c, g.shake_off, hh * 2.1, t, thr, color_vec(ice))

	// 3. Hull: two triangles through Player 1's plasma shader (DART_FS: iridescent energy that
	//    flows from nose to tail, glowing veins, sparkles - it follows the ship's heading).
	set_dart_shader(g.shaders.dart, c, g.shake_off, a, thr, t, color_vec(col))
	rl.BeginShaderMode(g.shaders.dart.shader)
	draw_tri_ccw(nose, tip_l, notch, col)
	draw_tri_ccw(nose, notch, tip_r, col)
	rl.EndShaderMode()

	// 4. Shading: dark lower wings and a bright spine.
	draw_tri_ccw(sh_l, tip_l, notch, rl.Fade(shade(col, 0.35), 0.55))
	draw_tri_ccw(sh_r, tip_r, notch, rl.Fade(shade(col, 0.35), 0.55))
	draw_tri_ccw(nose, sh_l, sh_r, rl.Fade(rl.WHITE, 0.14))
	rl.DrawLineEx(nose, notch, 1.3 * s, rl.Fade(rl.WHITE, 0.5))

	// 5. Outline + pulsing energy edge on the leading edges.
	edge := rl.Fade(rl.WHITE, 0.7)
	rl.DrawLineV(nose, tip_l, edge)
	rl.DrawLineV(tip_l, notch, edge)
	rl.DrawLineV(notch, tip_r, edge)
	rl.DrawLineV(tip_r, nose, edge)
	pulse := 0.5 + 0.5 * math.sin(t * 7)
	rl.BeginBlendMode(.ADDITIVE)
	rl.DrawLineEx(nose, tip_l, 2.6 * s, rl.Fade(ice, 0.25 + 0.30 * pulse))
	rl.DrawLineEx(nose, tip_r, 2.6 * s, rl.Fade(ice, 0.25 + 0.30 * pulse))

	// 6. Vapour streaks peeling off the wing tips.
	if thr > 0.1 {
		streak := (10 + 26 * thr) * s
		rl.DrawLineEx(tip_l, ship_pt(c, -hw * 0.95 - streak, -hh * 1.05, a), 1.6 * s, rl.Fade(rl.WHITE, 0.55 * thr))
		rl.DrawLineEx(tip_r, ship_pt(c, -hw * 0.95 - streak, hh * 1.05, a), 1.6 * s, rl.Fade(rl.WHITE, 0.55 * thr))
	}
	rl.DrawCircleV(tip_l, 2.2 * s, rl.Fade(ice, 0.8))
	rl.DrawCircleV(tip_r, 2.2 * s, rl.Fade(ice, 0.8))
	rl.EndBlendMode()

	// 6b. Two short gun nozzles in the wings, with a flash when they fire.
	for si in 0 ..< 2 {
		side: f32 = -1 if si == 0 else 1
		root := ship_pt(c, -hw * 0.30, side * hh * 0.62, a)
		muzzle := ship_pt(c, hw * 0.42, side * hh * 0.62, a)
		rl.DrawLineEx(root, muzzle, 3.2 * s, rl.Color{20, 28, 46, 255})
		rl.DrawLineEx(root, muzzle, 1.2 * s, rl.Fade(ice, 0.8))
		rl.DrawCircleV(muzzle, 1.8 * s, rl.Fade(rl.WHITE, 0.9))
		if p.muzzle_flash[si] > 0 {
			k := p.muzzle_flash[si] / 0.09
			rl.BeginBlendMode(.ADDITIVE)
			draw_glow(muzzle, hh * (0.3 + 0.35 * k), ice, 0.9)
			rl.DrawCircleV(muzzle, hh * 0.14 * k, rl.WHITE)
			rl.EndBlendMode()
		}
	}

	// 7. Canopy with a glint.
	canopy := ship_pt(c, hw * 0.32, 0, a)
	rl.DrawCircleV(canopy, hh * 0.24, rl.Color{8, 16, 40, 255})
	rl.DrawCircleV(canopy, hh * 0.15, rl.Fade(ice, 0.9))
	rl.DrawCircleV(ship_pt(c, hw * 0.38, -hh * 0.06, a), hh * 0.06, rl.Fade(rl.WHITE, 0.95))
}

// -----------------------------------------------------------------------------
// P2 - Bulwark
// -----------------------------------------------------------------------------
draw_ship_bulwark :: proc(g: ^Game, p: Player, col: rl.Color, s: f32) {
	t := g.time
	c := player_center(p)
	a := p.angle
	u := max(p.size.x, p.size.y) * 0.5 * s
	thr := p.thrust

	amber := rl.Color{255, 176, 40, 255}
	steel := rl.Color{34, 42, 48, 255}

	// 1. Twin ribbons from the engine nacelles.
	draw_ribbon(p, -u * 0.72, u * 0.14, amber, 0.32, PLAYER2_TRAIL_LENGTH)
	draw_ribbon(p, u * 0.72, u * 0.14, col, 0.32, PLAYER2_TRAIL_LENGTH)

	// 2. Engines: one big central burner and two nacelle jets.
	flick := 0.8 + 0.2 * math.sin(t * 41) + 0.1 * math.sin(t * 67)
	big   := (6 + 24 * thr) * flick * s
	small := (4 + 17 * thr) * flick * s
	draw_plume(c, a, -u * 0.95, 0, u * 0.22, big, col, rl.Color{200, 255, 120, 255})
	for side in ([2]f32{-1, 1}) {
		draw_plume(c, a, -u * 0.72, side * u * 0.74, u * 0.12, small, amber, rl.Color{255, 230, 140, 255})
	}

	// 3. Geometry (local units, x = forward, y = sideways).
	pod_local := [7][2]f32{{1.0, 0}, {0.55, -0.40}, {-0.30, -0.48}, {-0.90, -0.30}, {-0.90, 0.30}, {-0.30, 0.48}, {0.55, 0.40}}
	pod: [7][2]f32
	for q, i in pod_local do pod[i] = at(c, a, u, q.x, q.y)

	boom: [2][5][2]f32
	for side, si in ([2]f32{-1, 1}) {
		boom[si] = {
			at(c, a, u, -0.65, side * 0.40),
			at(c, a, u, -0.65, side * 0.98),
			at(c, a, u,  0.45, side * 0.98),
			at(c, a, u,  1.20, side * 0.78),
			at(c, a, u,  0.35, side * 0.55),
		}
	}

	// Hull through the energy shader: booms first, then the central pod.
	set_ship_shader(g.shaders.ship, t, col)
	rl.BeginShaderMode(g.shaders.ship.shader)
	for si in 0 ..< 2 {
		side: f32 = -1 if si == 0 else 1
		draw_fan_ccw(at(c, a, u, 0.1, side * 0.75), boom[si][:], col)
	}
	draw_fan_ccw(c, pod[:], col)
	rl.EndShaderMode()

	// 4. Plating: dark armoured deck on the pod, shaded boom tops.
	deck := [5][2]f32{at(c, a, u, 0.72, 0), at(c, a, u, 0.35, -0.24), at(c, a, u, -0.25, -0.30), at(c, a, u, -0.25, 0.30), at(c, a, u, 0.35, 0.24)}
	draw_fan_ccw(at(c, a, u, 0.1, 0), deck[:], rl.Fade(steel, 0.88))
	for si in 0 ..< 2 {
		side: f32 = -1 if si == 0 else 1
		draw_quad_ccw(at(c, a, u, -0.55, side * 0.55), at(c, a, u, -0.55, side * 0.90), at(c, a, u, 0.35, side * 0.90), at(c, a, u, 0.25, side * 0.60), rl.Fade(shade(col, 0.35), 0.65))
		// Amber hazard stripes across each boom.
		for k in 0 ..< 3 {
			x := -0.42 + f32(k) * 0.34
			rl.DrawLineEx(at(c, a, u, x, side * 0.52), at(c, a, u, x + 0.14, side * 0.95), 1.7 * s, rl.Fade(amber, 0.9))
		}
	}

	// 5. Outlines.
	edge := rl.Fade(rl.WHITE, 0.5)
	draw_poly_outline(pod[:], edge)
	draw_poly_outline(boom[0][:], edge)
	draw_poly_outline(boom[1][:], edge)

	// 5b. Details: armour seams, rivets, boom nose plates, gun barrels, a chevron emblem on the
	//     nose, a blinking sensor mast and glowing rear heat vents.
	seam := rl.Fade(rl.BLACK, 0.55)
	rl.DrawLineV(at(c, a, u, -0.05, -0.30), at(c, a, u, -0.05, 0.30), seam)
	rl.DrawLineV(at(c, a, u, 0.48, -0.20), at(c, a, u, 0.48, 0.20), seam)
	rl.DrawLineV(at(c, a, u, 0.72, 0), at(c, a, u, -0.25, 0), rl.Fade(rl.BLACK, 0.35))
	for side in ([2]f32{-1, 1}) {
		rl.DrawLineV(at(c, a, u, -0.20, side * 0.55), at(c, a, u, -0.20, side * 0.98), seam)
		rl.DrawLineV(at(c, a, u, 0.20, side * 0.55), at(c, a, u, 0.20, side * 0.98), seam)
		for k in 0 ..< 5 {
			rl.DrawCircleV(at(c, a, u, -0.55 + f32(k) * 0.26, side * 0.90), max(0.7, u * 0.03), rl.Fade(rl.WHITE, 0.55))
		}
		draw_tri_ccw(at(c, a, u, 1.12, side * 0.78), at(c, a, u, 0.58, side * 0.95), at(c, a, u, 0.58, side * 0.62), rl.Fade(rl.Color{86, 100, 112, 255}, 0.9))
		rl.DrawLineEx(at(c, a, u, 0.95, side * 0.78), at(c, a, u, 1.27, side * 0.78), max(2.0, u * 0.16), rl.Color{18, 22, 26, 255})
		rl.DrawLineEx(at(c, a, u, 0.95, side * 0.78), at(c, a, u, 1.27, side * 0.78), max(1.0, u * 0.05), rl.Fade(amber, 0.65))
	}
	for k in 0 ..< 2 {
		x := 0.82 - f32(k) * 0.18
		rl.DrawLineEx(at(c, a, u, x - 0.10, -0.11), at(c, a, u, x + 0.05, 0), 1.5 * s, rl.Fade(amber, 0.9))
		rl.DrawLineEx(at(c, a, u, x + 0.05, 0), at(c, a, u, x - 0.10, 0.11), 1.5 * s, rl.Fade(amber, 0.9))
	}
	mast_tip := at(c, a, u, 1.22, 0)
	rl.DrawLineEx(at(c, a, u, 0.98, 0), mast_tip, max(1.0, 1.1 * s), rl.Fade(rl.WHITE, 0.8))
	rl.BeginBlendMode(.ADDITIVE)
	if math.sin(t * 6.5) > 0.2 do rl.DrawCircleV(mast_tip, max(1.5, u * 0.07), rl.Fade(rl.Color{255, 70, 70, 255}, 0.95))
	for y in ([3]f32{-0.16, 0, 0.16}) {
		rl.DrawLineEx(at(c, a, u, -0.74, y), at(c, a, u, -0.88, y), max(1.5, u * 0.06), rl.Fade(rl.Color{255, 120, 40, 255}, 0.25 + 0.55 * thr))
	}
	rl.EndBlendMode()

	// 6. Gun muzzles at the boom tips, pulsing.
	rl.BeginBlendMode(.ADDITIVE)
	for side in ([2]f32{-1, 1}) {
		m := 0.5 + 0.5 * math.sin(t * 9 + side * 1.4)
		rl.DrawCircleV(at(c, a, u, 1.17, side * 0.78), u * (0.10 + 0.04 * m), rl.Fade(amber, 0.55 + 0.4 * m))
	}
	for si in 0 ..< 2 {
		if p.muzzle_flash[si] <= 0 do continue
		side: f32 = -1 if si == 0 else 1
		k := p.muzzle_flash[si] / 0.09
		muzzle := at(c, a, u, 1.17, side * 0.78)
		draw_glow(muzzle, u * (0.35 + 0.4 * k), amber, 0.9)
		rl.DrawCircleV(muzzle, u * 0.16 * k, rl.WHITE)
	}
	rl.EndBlendMode()

	// 7. Reactor core with three orbiting lights.
	core := at(c, a, u, 0.12, 0)
	rl.DrawCircleV(core, u * 0.27, rl.Color{10, 16, 14, 255})
	rl.DrawCircleLines(i32(core.x), i32(core.y), u * 0.27, rl.Fade(col, 0.9))
	cpulse := 0.5 + 0.5 * math.sin(t * 5)
	rl.BeginBlendMode(.ADDITIVE)
	rl.DrawCircleV(core, u * (0.15 + 0.05 * cpulse), rl.Fade(col, 0.95))
	rl.DrawCircleV(core, u * 0.07, rl.Fade(rl.WHITE, 0.95))
	for i in 0 ..< 3 {
		ang := t * 3.2 + f32(i) * (2.0 * math.PI / 3.0)
		rl.DrawCircleV(core + rotate_vec({u * 0.36, 0}, ang), u * 0.06, rl.Fade(amber, 0.9))
	}
	rl.EndBlendMode()

	// 8. Radar dish: a short sweeping arm on the rear deck.
	dish := at(c, a, u, -0.55, 0)
	sweep := t * 5.0
	off := rotate_vec({u * 0.24, 0}, sweep)
	arm := ship_pt(dish, off.x, off.y, a)
	rl.DrawLineEx(dish, arm, 1.6 * s, rl.Fade(rl.WHITE, 0.85))
	rl.DrawCircleV(dish, u * 0.07, rl.Color{20, 24, 28, 255})
	rl.DrawCircleV(arm, u * 0.05, rl.Fade(amber, 0.95))

	// 9. Alternating nav lights on the boom rears.
	blink := math.sin(t * 5) > 0
	rl.BeginBlendMode(.ADDITIVE)
	rl.DrawCircleV(at(c, a, u, -0.65, -0.98), 2.2 * s, rl.Fade(rl.Color{255, 80, 80, 255}, 0.95 if blink else 0.2))
	rl.DrawCircleV(at(c, a, u, -0.65, 0.98), 2.2 * s, rl.Fade(rl.Color{90, 255, 170, 255}, 0.2 if blink else 0.95))
	rl.EndBlendMode()
}
