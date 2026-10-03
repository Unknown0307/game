package main

import "core:fmt"
import "core:math"
import rl "vendor:raylib"

// =============================================================================
// render.odin - drawing of the world (everything inside the shaken camera).
// HUD / menus live in hud.odin.
// =============================================================================

rotate_ship_point :: proc(center: [2]f32, local: [2]f32, angle: f32) -> [2]f32 {
	return center + rotate_vec(local, angle)
}

draw_glows :: proc(g: ^Game) {
	t := g.time
	rl.BeginBlendMode(.ADDITIVE)

	for c in g.coins {
		if c.active do draw_glow(c.pos, 22, rl.GOLD, 0.35)
	}
	for a in g.allies {
		if !a.active do continue
		pulse := 0.5 + 0.5 * math.sin(a.pulse * 4)
		col := rl.LIME
		if a.kind == .Barrier do col = SHIELD_COLOR
		draw_glow(a.pos, 36 + pulse * 8, col, 0.35 + 0.15 * pulse)
	}
	for e in g.enemies {
		if !e.active do continue
		switch e.kind {
		case .Boss:
			pulse := 0.5 + 0.5 * math.sin(t * 8)
			draw_glow(e.pos, e.radius * 2.0 + pulse * 10, rl.Color{255, 60, 200, 255}, 0.45)
		case .Big:
			draw_glow(e.pos, e.radius * 1.6, rl.RED, 0.2)
		case .Sticky:
			scale: f32 = 1.3
			if e.stuck do scale = 1.8
			draw_glow(e.pos, e.radius * scale, rl.Color{255, 80, 210, 255}, 0.28)
		case .Normal, .Runner:
		}
	}
	for p in g.players {
		if !p.dead do draw_glow(player_center(p), 42, p.color, 0.3)
	}

	rl.EndBlendMode()
}

set_ship_shader :: proc(s: ShipShader, t: f32, col: rl.Color) {
	tt := t
	tint := [3]f32{f32(col.r) / 255.0, f32(col.g) / 255.0, f32(col.b) / 255.0}
	rl.SetShaderValue(s.shader, s.time_loc, &tt, .FLOAT)
	rl.SetShaderValue(s.shader, s.tint_loc, &tint, .VEC3)
}

draw_player :: proc(g: ^Game, p: Player) {
	if p.dead do return
	t := g.time

	col := p.color
	if p.hurt_flash > 0 && int(p.hurt_flash * 30) % 2 == 0 do col = rl.WHITE

	center := player_center(p)
	half_w := p.size.x * 0.5
	half_h := p.size.y * 0.5
	ship := g.shaders.ship

	switch p.ship {
	case .Fighter:
		// Pointed fighter/jet silhouette.
		nose     := rotate_ship_point(center, {half_w + 8, 0}, p.angle)
		wing_top := rotate_ship_point(center, {-half_w * 0.55, -half_h * 0.85}, p.angle)
		wing_bot := rotate_ship_point(center, {-half_w * 0.55, half_h * 0.85}, p.angle)
		tail_top := rotate_ship_point(center, {-half_w * 0.9, -half_h * 0.48}, p.angle)
		tail_bot := rotate_ship_point(center, {-half_w * 0.9, half_h * 0.48}, p.angle)

		set_ship_shader(ship, t, col)
		rl.BeginShaderMode(ship.shader)
		rl.DrawTriangle(nose, wing_top, tail_top, col)
		rl.DrawTriangle(nose, tail_bot, wing_bot, col)
		rl.DrawTriangle(nose, tail_top, tail_bot, col)
		rl.EndShaderMode()
		rl.DrawTriangleLines(nose, wing_top, tail_top, rl.Fade(rl.WHITE, 0.55))
		rl.DrawTriangleLines(nose, tail_bot, wing_bot, rl.Fade(rl.WHITE, 0.55))

		cockpit := rotate_ship_point(center, {half_w * 0.18, 0}, p.angle)
		engine  := rotate_ship_point(center, {-half_w * 0.85, 0}, p.angle)
		rl.DrawCircleV(cockpit, half_h * 0.25, rl.Fade(rl.WHITE, 0.72))
		rl.BeginBlendMode(.ADDITIVE)
		rl.DrawCircleV(engine, half_h * (0.28 + 0.06 * (0.5 + 0.5 * math.sin(t * 14))), rl.Fade(rl.SKYBLUE, 0.8))
		rl.EndBlendMode()

	case .Interceptor:
		// Broader square-like interceptor with a narrowed nose.
		front        := rotate_ship_point(center, {half_w + 5, 0}, p.angle)
		shoulder_top := rotate_ship_point(center, {half_w * 0.25, -half_h}, p.angle)
		rear_top     := rotate_ship_point(center, {-half_w, -half_h}, p.angle)
		rear_bot     := rotate_ship_point(center, {-half_w, half_h}, p.angle)
		shoulder_bot := rotate_ship_point(center, {half_w * 0.25, half_h}, p.angle)
		nose_top     := rotate_ship_point(center, {half_w * 0.78, -half_h * 0.62}, p.angle)
		nose_bot     := rotate_ship_point(center, {half_w * 0.78, half_h * 0.62}, p.angle)

		set_ship_shader(ship, t, col)
		rl.BeginShaderMode(ship.shader)
		rl.DrawTriangle(front, shoulder_top, nose_top, col)
		rl.DrawTriangle(front, nose_bot, shoulder_bot, col)
		rl.DrawTriangle(shoulder_top, rear_top, rear_bot, col)
		rl.DrawTriangle(shoulder_top, rear_bot, shoulder_bot, col)
		rl.EndShaderMode()
		rl.DrawTriangleLines(front, shoulder_top, nose_top, rl.Fade(rl.WHITE, 0.55))
		rl.DrawTriangleLines(front, nose_bot, shoulder_bot, rl.Fade(rl.WHITE, 0.55))

		cockpit := rotate_ship_point(center, {half_w * 0.15, 0}, p.angle)
		engine  := rotate_ship_point(center, {-half_w * 0.8, 0}, p.angle)
		rl.DrawCircleV(cockpit, half_h * 0.24, rl.Fade(rl.WHITE, 0.72))
		rl.BeginBlendMode(.ADDITIVE)
		rl.DrawCircleV(engine, half_h * (0.30 + 0.05 * (0.5 + 0.5 * math.sin(t * 12))), rl.Fade(rl.LIME, 0.8))
		rl.EndBlendMode()
	}

	// Shield shell around the ship.
	shields := shield_count(p)
	if shields > 0 {
		pulse := 0.9 + 0.1 * math.sin(t * 6.0)
		rl.DrawCircleLines(i32(center.x), i32(center.y), max(half_w, half_h) + 5 + f32(shields) * 2, rl.Fade(SHIELD_COLOR, 0.45 * pulse))
	}
}

draw_coins :: proc(g: ^Game) {
	for c in g.coins {
		if !c.active do continue
		if c.life < 3 && int(c.life * 8) % 2 == 0 do continue // blink before expiring
		w := max(abs(math.cos(c.spin)) * COIN_RADIUS, 1.5)
		cx := i32(c.pos.x)
		cy := i32(c.pos.y)
		rl.DrawEllipse(cx, cy, w, COIN_RADIUS, rl.GOLD)
		rl.DrawEllipse(cx, cy, w * 0.6, COIN_RADIUS * 0.6, rl.YELLOW)
	}
}

draw_allies :: proc(g: ^Game) {
	for a in g.allies {
		if !a.active do continue
		if a.life < 3 && int(a.life * 8) % 2 == 0 do continue

		col := rl.Color{60, 220, 100, 255}
		if a.kind == .Barrier do col = rl.Color{190, 198, 210, 255}
		if a.flash > 0 do col = rl.Color{255, 120, 120, 255}

		ax, ay := i32(a.pos.x), i32(a.pos.y)
		rl.DrawCircleV(a.pos, a.radius, col)
		rl.DrawCircleLines(ax, ay, a.radius, rl.WHITE)
		if a.kind == .Barrier {
			rl.DrawCircleLines(ax, ay, a.radius * 0.55, rl.WHITE)
			rl.DrawLine(ax - 5, ay, ax + 5, ay, rl.WHITE)
			rl.DrawLine(ax, ay - 5, ax, ay + 5, rl.WHITE)
		} else {
			arm := a.radius * 0.7
			th := a.radius * 0.28
			rl.DrawRectangleV(a.pos - [2]f32{arm, th}, [2]f32{arm * 2, th * 2}, rl.WHITE)
			rl.DrawRectangleV(a.pos - [2]f32{th, arm}, [2]f32{th * 2, arm * 2}, rl.WHITE)
		}
		for i in 0 ..< int(a.hp) {
			px := a.pos.x + (f32(i) - f32(a.hp - 1) / 2) * 8
			rl.DrawCircleV([2]f32{px, a.pos.y - a.radius - 8}, 2.5, rl.LIME)
		}
	}
}

draw_enhancement_pickups :: proc(g: ^Game) {
	t := g.time
	for pk in g.enh_pickups {
		if !pk.active do continue
		// Blink during the last 3 seconds before it vanishes.
		if pk.life < 3 && g.phase != .LevelComplete && int(pk.life * 8) % 2 == 0 do continue

		p := pk.pos
		pulse := 1.0 + 0.14 * math.sin(t * 6.0 + pk.pulse)
		col := enhancement_color(pk.kind)
		label := enhancement_label(pk.kind)

		rl.BeginBlendMode(.ADDITIVE)
		draw_glow(p, 36 * pulse, col, 0.55)
		rl.EndBlendMode()
		rl.DrawCircleV(p, 12 * pulse, rl.Color{24, 28, 40, 245})
		rl.DrawCircleLines(i32(p.x), i32(p.y), 12 * pulse, col)
		rl.DrawCircleLines(i32(p.x), i32(p.y), 7, rl.Fade(rl.WHITE, 0.55))
		rl.DrawText(label, i32(p.x) - rl.MeasureText(label, 11) / 2, i32(p.y) - 6, 11, rl.WHITE)
	}
}

draw_boss_extras :: proc(g: ^Game, e: Enemy) {
	// Health bar
	draw_bar(i32(e.pos.x) - 40, i32(e.pos.y - e.radius) - 18, 80, 10, f32(e.hp) / f32(e.max_hp), rl.RED)

	if !e.can_repel do return

	// Repel range is always faintly visible; while charging it fills in.
	ex, ey := i32(e.pos.x), i32(e.pos.y)
	rl.DrawCircleLines(ex, ey, BOSS_REPEL_RADIUS, rl.Fade(BOSS_PURPLE, 0.18))
	if e.charge > 0 {
		progress := 1.0 - e.charge / BOSS_REPEL_CHARGE
		blink := 0.5 + 0.5 * math.sin(g.time * 30)
		rl.DrawCircleV(e.pos, BOSS_REPEL_RADIUS * progress, rl.Fade(BOSS_PURPLE, 0.10 + 0.10 * blink))
		rl.DrawCircleLines(ex, ey, BOSS_REPEL_RADIUS, rl.Fade(rl.WHITE, 0.45 + 0.35 * blink))
	}
}

draw_enemies :: proc(g: ^Game) {
	for e in g.enemies {
		if !e.active do continue

		col := e.color
		if e.flash > 0 do col = rl.WHITE
		ex, ey := i32(e.pos.x), i32(e.pos.y)

		rl.DrawCircleV(e.pos, e.radius, col)
		rl.DrawCircleLines(ex, ey, e.radius, rl.Fade(rl.BLACK, 0.5))
		if e.kind == .Big || e.kind == .Boss {
			rl.DrawCircleV(e.pos, e.radius * 0.45, rl.Fade(rl.WHITE, 0.15))
		}
		if e.kind == .Sticky {
			if e.stuck {
				blink := 0.55 + 0.45 * math.sin(f32(e.stick_ticks) * 5.0)
				rl.DrawCircleLines(ex, ey, STICKY_EXPLOSION_RADIUS, rl.Fade(rl.Color{255, 90, 210, 255}, 0.35 + 0.25 * blink))
				rl.DrawText(fmt.ctprintf("%d", e.stick_ticks), ex - 4, ey - 6, 12, rl.WHITE)
			} else {
				rl.DrawCircleLines(ex, ey, e.radius + 5, rl.Fade(rl.Color{255, 210, 100, 255}, 0.65))
			}
		}
		if e.kind == .Boss do draw_boss_extras(g, e)
	}
}

draw_entities :: proc(g: ^Game) {
	draw_coins(g)
	draw_allies(g)
	draw_enhancement_pickups(g)
	draw_enemies(g)
	for p in g.players do draw_player(g, p)
}

draw_particles :: proc(g: ^Game) {
	rl.BeginBlendMode(.ADDITIVE)
	for p in g.fx.particles {
		if p.life > 0 {
			t := p.life / p.max_life
			rl.DrawCircleV(p.pos, p.size * (0.3 + 0.7 * t), rl.Fade(p.color, t))
		}
	}
	rl.EndBlendMode()
}

draw_floaters :: proc(g: ^Game) {
	for f in g.fx.floaters {
		if f.life <= 0 do continue

		text: cstring
		color := rl.WHITE
		size: i32 = 18
		switch f.kind {
		case .Score:
			text = fmt.ctprintf("+%d", f.value)
		case .Coin:
			text = fmt.ctprintf("+%d", f.value)
			color = rl.GOLD
			size = 16
		case .Heal:
			text = fmt.ctprintf("+%d HP", f.value)
			color = rl.LIME
		case .Shield:
			text = "SHIELD"
			color = SHIELD_COLOR
			size = 15
		case .Enhancement:
			text = fmt.ctprintf("ENH %d/%d", f.value, MAX_ENHANCEMENTS)
			color = rl.SKYBLUE
			size = 15
		case .Boss:
			text = fmt.ctprintf("+%d!", f.value)
			color = rl.GOLD
			size = 32
		}
		a := min(f.life / 0.5, 1.0)
		rl.DrawText(text, i32(f.pos.x) - rl.MeasureText(text, size) / 2, i32(f.pos.y), size, rl.Fade(color, a))
	}
}

// Shockwave shaders are drawn in screen space (after the camera), so they get
// the shake offset added manually.
draw_shockwaves :: proc(g: ^Game, shake_off: [2]f32) {
	for p in g.players {
		if p.visual_timer <= 0 do continue
		progress := (BLAST_VISUAL_TIME - p.visual_timer) / BLAST_VISUAL_TIME
		tint := [3]f32{f32(p.color.r) / 255.0, f32(p.color.g) / 255.0, f32(p.color.b) / 255.0}
		// Brighten the pure primary colours so the wave reads clearly.
		tint = {max(tint.x, 0.3), max(tint.y, 0.3), max(tint.z, 0.3)}
		draw_blast(g.shaders.blast, player_center(p) + shake_off, progress, REPULSION_RADIUS, tint)
	}
	for e in g.enemies {
		if !e.active || e.kind != .Boss || e.repel_visual <= 0 do continue
		progress := (BOSS_REPEL_VISUAL_TIME - e.repel_visual) / BOSS_REPEL_VISUAL_TIME
		draw_blast(g.shaders.blast, e.pos + shake_off, progress, BOSS_REPEL_RADIUS, {0.80, 0.35, 1.0})
	}
}

// Renders one complete frame of the game onto the fixed logical canvas.
render_world :: proc(g: ^Game) {
	rl.ClearBackground(g.style.background)
	draw_procedural_background(g.style, g.level, g.time)

	shake_off := [2]f32{rand_signed(), rand_signed()} * g.fx.shake
	camera := rl.Camera2D{offset = shake_off, zoom = 1.0}
	rl.BeginMode2D(camera)
	draw_grid(g.style, g.time)
	draw_glows(g)
	draw_entities(g)
	draw_particles(g)
	draw_floaters(g)
	rl.EndMode2D()

	draw_shockwaves(g, shake_off)
}
