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

level_style :: proc(level: i32) -> LevelStyle {
	s := f32(level)

	bg_r := style_byte(s, 1.173, 0.7, 7, 32)
	bg_g := style_byte(s, 0.731, 2.1, 10, 38)
	bg_b := style_byte(s, 0.947, 4.4, 18, 55)

	alt_r := style_byte(s, 1.611, 3.2, 10, 48)
	alt_g := style_byte(s, 0.857, 0.4, 14, 54)
	alt_b := style_byte(s, 1.329, 5.0, 28, 72)

	accent := rl.Color{
		style_byte(s, 1.913, 1.2, 80, 255),
		style_byte(s, 1.271, 3.8, 70, 230),
		style_byte(s, 1.587, 5.4, 100, 255),
		255,
	}
	accent2 := rl.Color{
		style_byte(s, 1.447, 4.6, 90, 255),
		style_byte(s, 1.109, 1.7, 80, 245),
		style_byte(s, 1.821, 2.9, 90, 255),
		255,
	}

	pattern: i32 = i32(abs(math.sin(s * 0.917)) * 4.0)
	spacing := i32(28 + int(abs(math.cos(s * 0.643)) * 44.0))

	return LevelStyle{
		background     = rl.Color{bg_r, bg_g, bg_b, 255},
		background_alt = rl.Color{alt_r, alt_g, alt_b, 255},
		grid           = rl.Fade(accent, 0.23),
		accent         = accent,
		accent2        = accent2,
		grid_spacing   = spacing,
		pattern        = pattern,
	}
}

draw_procedural_background :: proc(style: LevelStyle, level: i32, t: f32) {
	// Broad animated bands give every level a different atmosphere.
	bands: i32 = 24
	band_h: i32 = SCREEN_H / bands
	for i in 0 ..< bands {
		k := f32(i) / f32(bands - 1)
		wave := 0.5 + 0.5 * math.sin(k * 8.0 + t * 0.35 + f32(level) * 0.71)
		col := style.background
		if i % 2 == 1 do col = style.background_alt
		shift := u8(clamp(wave * 18.0, 0.0, 18.0))
		col.r = min(u8(255), col.r + shift)
		col.g = min(u8(255), col.g + shift / 2)
		col.b = min(u8(255), col.b + shift)
		rl.DrawRectangle(0, i32(f32(i) * f32(band_h)), SCREEN_W, band_h + 2, rl.Fade(col, 0.92))
	}

	// Deterministic floating "stars" (reproducible per level).
	star_count := 45 + (level % 5) * 12
	for i in 0 ..< star_count {
		fi := f32(i + 1)
		x := 18.0 + (0.5 + 0.5 * math.sin(fi * 12.731 + f32(level) * 1.913)) * (f32(SCREEN_W) - 36.0)
		y := 112.0 + (0.5 + 0.5 * math.sin(fi * 7.317 + f32(level) * 2.271)) * (f32(SCREEN_H) - 130.0)
		pulse := 0.35 + 0.35 * math.sin(t * (0.8 + f32(i % 4) * 0.23) + fi)
		radius := 1.0 + f32(i % 3)
		rl.DrawCircleV({x, y}, radius, rl.Fade(style.accent2, pulse))
	}
}

draw_grid :: proc(style: LevelStyle, t: f32) {
	step := style.grid_spacing

	for x := i32(0); x <= SCREEN_W; x += step {
		phase := 0.45 + 0.25 * math.sin(t * 0.7 + f32(x) * 0.01)
		rl.DrawLine(x, 100, x, SCREEN_H, rl.Fade(style.grid, phase))
	}
	for y := i32(100); y <= SCREEN_H; y += step {
		phase := 0.35 + 0.25 * math.sin(t * 0.9 + f32(y) * 0.013)
		rl.DrawLine(0, y, SCREEN_W, y, rl.Fade(style.grid, phase))
	}

	// A second pattern that changes with the generated style.
	switch style.pattern {
	case 0:
		for x := i32(-SCREEN_H); x < SCREEN_W; x += step * 2 {
			rl.DrawLine(x, SCREEN_H, x + SCREEN_H, 100, rl.Fade(style.accent, 0.10))
		}
	case 1:
		for x := i32(0); x <= SCREEN_W; x += step * 2 {
			rl.DrawCircleLines(x, SCREEN_H / 2, f32(18 + step / 3), rl.Fade(style.accent2, 0.10))
		}
	case 2:
		for y := i32(120); y < SCREEN_H; y += step * 2 {
			rl.DrawLine(0, y, SCREEN_W, y, rl.Fade(style.accent2, 0.12))
		}
	case 3:
		for x := i32(0); x <= SCREEN_W; x += step * 2 {
			rl.DrawCircleV({f32(x), 110}, 3.0, rl.Fade(style.accent, 0.22))
		}
	}
}

draw_portal :: proc(style: LevelStyle, level: i32, open_progress, t: f32) {
	center := portal_center()
	pulse := 1.0 + 0.10 * math.sin(t * 7.0)
	rotation := t * (1.0 + f32(level % 5) * 0.18)
	base := 34.0 + open_progress * (PORTAL_RADIUS - 34.0)

	rl.BeginBlendMode(.ADDITIVE)
	for i in 0 ..< 5 {
		k := f32(i) / 5.0
		r := base * (1.0 + k * 0.65) * pulse
		col := style.accent if i % 2 == 0 else style.accent2
		rl.DrawCircleLines(i32(center.x), i32(center.y), r, rl.Fade(col, (0.24 - k * 0.035) * open_progress))
	}
	for i in 0 ..< 16 {
		ang := rotation * (1.0 + f32(i % 3) * 0.22) + f32(i) * (2.0 * math.PI / 16.0)
		r := base * (1.05 + 0.25 * math.sin(ang * 2.0 + rotation))
		pos := center + [2]f32{math.cos(ang), math.sin(ang)} * r
		ray := 3.0 + 2.0 * pulse + f32(i % 3)
		rl.DrawCircleV(pos, ray, rl.Fade(style.accent2, 0.75 * open_progress))
	}
	rl.EndBlendMode()

	// Dark core keeps the portal readable over every generated background.
	rl.DrawCircleV(center, base * 0.72, rl.Color{5, 5, 12, 235})
	rl.DrawCircleLines(i32(center.x), i32(center.y), base * 0.72, rl.Fade(style.accent, 0.95))
	rl.DrawCircleLines(i32(center.x), i32(center.y), base * 0.52, rl.Fade(style.accent2, 0.55))

	draw_centered("PORTAL", i32(center.y - 10), 22, rl.WHITE)
}
