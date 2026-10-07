package main

import "core:math"
import rl "vendor:raylib"

// =============================================================================
// style.odin - procedural per-level look: palette, background, grid, portal.
// Every level gets a deterministic style generated from its number.
// =============================================================================

style_byte :: proc(seed: f32, frequency, phase, low, high: f32) -> u8 {
	x := 0.5 + 0.5 * math.sin(seed * frequency + phase)
	value := low + x * (high - low)
	return u8(clamp(value, 0.0, 255.0))
}

// Eight space palettes: {deep background, accent, accent2}. Levels cycle through
// them (5 is coprime to 8, so neighbouring levels never share a palette).
PALETTES :: [8][3]rl.Color {
	{{10, 12, 38, 255}, {110, 140, 255, 255}, {190, 120, 255, 255}}, // deep indigo
	{{26, 8, 40, 255}, {255, 110, 230, 255}, {130, 110, 255, 255}}, // violet nebula
	{{6, 28, 34, 255}, {70, 235, 210, 255}, {90, 170, 255, 255}}, // teal void
	{{36, 10, 12, 255}, {255, 120, 70, 255}, {255, 200, 90, 255}}, // ember
	{{6, 30, 22, 255}, {90, 255, 160, 255}, {80, 210, 230, 255}}, // emerald
	{{34, 6, 26, 255}, {255, 80, 140, 255}, {200, 90, 255, 255}}, // crimson-magenta
	{{6, 16, 44, 255}, {60, 200, 255, 255}, {120, 140, 255, 255}}, // cobalt
	{{30, 22, 8, 255}, {255, 200, 100, 255}, {255, 140, 120, 255}}, // golden dust
}

jitter_byte :: proc(c: u8, s, freq, phase: f32) -> u8 {
	return u8(clamp(f32(c) + f32(style_byte(s, freq, phase, 0, 24)) - 12, 0, 255))
}

level_style :: proc(level: i32) -> LevelStyle {
	s := f32(level)
	palettes := PALETTES
	pal := palettes[(level * 5 + level / 8) % 8]

	bg := rl.Color {
		jitter_byte(pal[0].r, s, 1.173, 0.7),
		jitter_byte(pal[0].g, s, 0.731, 2.1),
		jitter_byte(pal[0].b, s, 0.947, 4.4),
		255,
	}
	accent := rl.Color {
		jitter_byte(pal[1].r, s, 1.913, 1.2),
		jitter_byte(pal[1].g, s, 1.271, 3.8),
		jitter_byte(pal[1].b, s, 1.587, 5.4),
		255,
	}
	accent2 := rl.Color {
		jitter_byte(pal[2].r, s, 1.447, 4.6),
		jitter_byte(pal[2].g, s, 1.109, 1.7),
		jitter_byte(pal[2].b, s, 1.821, 2.9),
		255,
	}
	bg_alt := rl.Color {
		u8(min(f32(bg.r) * 1.5, 255)),
		u8(min(f32(bg.g) * 1.5, 255)),
		u8(min(f32(bg.b) * 1.5, 255)),
		255,
	}

	pattern: i32 = i32(abs(math.sin(s * 0.917)) * 4.0)
	spacing := i32(28 + int(abs(math.cos(s * 0.643)) * 44.0))

	return LevelStyle {
		background = bg,
		background_alt = bg_alt,
		grid = rl.Fade(accent, 0.23),
		accent = accent,
		accent2 = accent2,
		grid_spacing = spacing,
		pattern = pattern,
	}
}

// --- Deep space backdrop ---------------------------------------------------

color_vec :: proc(c: rl.Color) -> [3]f32 {
	return {f32(c.r) / 255.0, f32(c.g) / 255.0, f32(c.b) / 255.0}
}

star_hash :: proc(x: u32) -> u32 {
	h := x
	h = (h ~ 61) ~ (h >> 16)
	h *= 9
	h = h ~ (h >> 4)
	h *= 0x27d4eb2d
	h = h ~ (h >> 15)
	return h
}

star_rand :: proc(seed: u32) -> f32 {
	return f32(star_hash(seed) & 0xFFFFFF) / 16777216.0
}

// Everything the black hole needs to know this frame (drawing + star lensing).
HoleState :: struct {
	active: bool,
	radius: f32, // event-horizon radius in pixels
	boost:  f32, // 0 idle .. 1 feeding / spitting
	fade:   f32,
}

hole_state :: proc(g: ^Game) -> HoleState {
	ph := g.phase
	if ph == .Paused do ph = g.resume_phase

	if g.spit_t > 0 {
		s := clamp(g.spit_t / SPIT_TIME, 0, 1)
		sm := s * s * (3.0 - 2.0 * s)
		return HoleState{true, BLACK_HOLE_RADIUS * (1.0 + 0.35 * s) * sm, s, min(1.0, s * 2.5)}
	}
	#partial switch ph {
	case .Sucking:
		u := clamp(g.suck_t / SUCK_TIME, 0, 1)
		return HoleState{true, BLACK_HOLE_RADIUS * (1.0 + 0.35 * u), u, 1}
	case .LevelComplete:
		o := clamp(g.portal_open, 0, 1)
		sm := o * o * (3.0 - 2.0 * o)
		return HoleState{o > 0.01, BLACK_HOLE_RADIUS * sm, 0.12 * sm, 1}
	}
	return HoleState{}
}

// Tiny twinkling stars in three parallax layers. Near a black hole the whole
// field is twisted and pinched toward it (a cheap gravitational-lens look).
draw_starfield :: proc(style: LevelStyle, level: i32, t: f32, hs: HoleState) {
	counts := [3]int{130, 70, 28}
	speeds := [3]f32{6.0, 14.0, 30.0}
	dims := [3]f32{0.55, 0.78, 1.0}
	seed := u32(level) * 7919 + 17
	pc := portal_center()
	lens: f32 = 0
	if hs.active do lens = hs.fade * (0.3 * hs.radius / BLACK_HOLE_RADIUS + 0.8 * hs.boost)

	accent_tint := style.accent2
	idx: u32 = 0
	for layer in 0 ..< 3 {
		for _ in 0 ..< counts[layer] {
			x := star_rand(seed + idx * 4 + 0) * SCREEN_W
			y := star_rand(seed + idx * 4 + 1) * SCREEN_H
			br := star_rand(seed + idx * 4 + 2)
			tw := star_rand(seed + idx * 4 + 3)
			idx += 1

			x = math.mod(x - t * speeds[layer], f32(SCREEN_W))
			if x < 0 do x += SCREEN_W
			y = math.mod(y + t * speeds[layer] * 0.22, f32(SCREEN_H))

			pos := [2]f32{x, y}
			if lens > 0.001 {
				d := pos - pc
				r := math.sqrt(d.x * d.x + d.y * d.y)
				d = rotate_vec(d, lens * 3.0 * math.exp(-r / 150.0))
				d *= 1.0 - 0.5 * min(lens, 1.0) * math.exp(-r / 220.0)
				pos = pc + d
			}

			col := rl.Color{200, 220, 255, 255}
			if tw < 0.12 {
				col = accent_tint
			} else if tw < 0.30 {
				col = rl.Color{255, 232, 205, 255}
			}

			twinkle := 0.75 + 0.25 * math.sin(t * (0.7 + tw * 2.2) + tw * 40.0)
			alpha := (0.30 + 0.70 * br) * twinkle * dims[layer]
			size: i32 = 1
			if layer == 2 && br > 0.88 do size = 2
			rl.DrawRectangle(i32(pos.x), i32(pos.y), size, size, rl.Fade(col, alpha))
		}
	}
}

draw_space_background :: proc(g: ^Game, hs: HoleState) {
	st := g.style
	base := color_vec(st.background) * 0.60
	seed := [2]f32{f32(g.level) * 3.7, f32(g.level) * 1.3}
	draw_nebula(g.shaders.nebula, g.time, seed, base, color_vec(st.accent), color_vec(st.accent2))
	draw_starfield(st, g.level, g.time, hs)
	draw_backdrop(g) // planets, suns, pulsars, belts, comets (backdrop.odin)
}

// --- Black hole ------------------------------------------------------------
// Replaces the old portal. The glowing disc / horizon / jets are one fragment
// shader (shaders.odin); matter sparks and the infall are drawn around it.

draw_black_hole :: proc(g: ^Game, hs: HoleState, shake_off: [2]f32) {
	if !hs.active || hs.radius < 1 || hs.fade <= 0.001 do return
	t := g.time
	center := portal_center()
	st := g.style

	warm := [3]f32{1.0, 0.78, 0.45}
	hot := warm * 0.7 + color_vec(st.accent) * 0.3
	cool := color_vec(st.accent2)

	breathe := 1.0 + 0.03 * math.sin(t * 3.0)
	R := hs.radius * breathe
	draw_hole_shader(g.shaders.hole, center, shake_off, R, t, hs.boost, hs.fade, hot, cool)

	// Sparks of infalling matter spiralling along the disc plane.
	rl.BeginBlendMode(.ADDITIVE)
	for i in 0 ..< 48 {
		fi := f32(i)
		ph := math.mod(t * 0.14 * (1.0 + hs.boost) + fi * 0.618034, 1.0)
		rr := R * (4.4 - 3.3 * ph * ph)
		ang := fi * 2.39996 + t * 2.2 / math.pow(rr / R, 1.4)
		ox := math.cos(ang) * rr
		oy := math.sin(ang) * rr * 0.2
		if oy < 0 && abs(ox) < R do continue // hidden behind the horizon
		a := math.sin(ph * math.PI) * 0.9 * hs.fade
		col := rl.Color{255, 215, 160, 255} if ph > 0.55 else st.accent2
		rl.DrawCircleV(center + [2]f32{ox, oy}, 1.0 + (1.0 - ph) * 1.6, rl.Fade(col, a))
	}
	rl.EndBlendMode()
}
