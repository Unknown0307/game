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

// DrawTriangle culls clockwise triangles, so flip the winding when needed.
draw_tri_ccw :: proc(a, b, c: [2]f32, col: rl.Color) {
	cross := (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
	if cross > 0 {
		rl.DrawTriangle(a, c, b, col)
	} else {
		rl.DrawTriangle(a, b, c, col)
	}
}

shade :: proc(c: rl.Color, k: f32) -> rl.Color {
	return rl.Color{u8(f32(c.r) * k), u8(f32(c.g) * k), u8(f32(c.b) * k), c.a}
}

draw_glows :: proc(g: ^Game) {
	t := g.time
	frozen := g.freeze_ticks > 0
	rl.BeginBlendMode(.ADDITIVE)

	for c in g.coins {
		if c.active do draw_glow(c.pos, 22, rl.GOLD, 0.35)
	}
	for a in g.allies {
		if !a.active do continue
		pulse := 0.5 + 0.5 * math.sin(a.pulse * 4)
		draw_glow(a.pos, 36 + pulse * 8, ally_def(a.kind).glow_color, 0.35 + 0.15 * pulse)
	}
	for e in g.enemies {
		if !e.active do continue
		def := enemy_def(e.kind)
		if frozen {
			// Frozen things glow a steady icy blue instead of their own colour.
			draw_glow(e.pos, e.radius * (2.0 if def.is_boss else 1.7), rl.Color{140, 200, 255, 255}, 0.30)
			continue
		}
		if def.glow != nil do def.glow(g, e, t)
	}
	for p in g.players {
		if !p.dead do draw_glow(player_center(p), (42 + 8 * p.thrust) * (1 - p.shrink), p.color, 0.3)
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

	// shrink > 0 while the ship is being swallowed by / thrown out of the black hole.
	s := 1.0 - clamp(p.shrink, 0, 1)
	if s <= 0.02 do return
	center := player_center(p)

	// Invisibility: the ship phases in and out (shorter flickers when it is about to end).
	ghost := p.invis_ticks > 0
	visible := true
	if ghost {
		rate: f32 = 26 if p.invis_ticks > 60 else 48
		visible = math.sin(t * rate) > -0.3
	}
	if visible {
		switch p.ship {
		case .Fighter:     draw_ship_spear(g, p, col, s)
		case .Interceptor: draw_ship_hauler(g, p, col, s)
		}
	}
	if ghost {
		rl.BeginBlendMode(.ADDITIVE)
		pulse := 0.5 + 0.5 * math.sin(t * 9)
		draw_glow(center, 30 * s, skill_color(.Invisibility), 0.35 + 0.2 * pulse)
		rl.EndBlendMode()
		rl.DrawCircleLines(i32(center.x), i32(center.y), max(p.size.x, p.size.y) * 0.5 * s + 7, rl.Fade(skill_color(.Invisibility), 0.35 + 0.3 * pulse))
	}

	// Surprise: a reflective dome that spins and flares over its 40 ticks.
	if p.surprise_ticks > 0 {
		k := f32(p.surprise_ticks) / f32(SURPRISE_DURATION_TICKS)
		rad := max(p.size.x, p.size.y) * 0.5 * s + 12
		scol := skill_color(.Surprise)
		rl.BeginBlendMode(.ADDITIVE)
		rl.DrawCircleV(center, rad, rl.Fade(scol, 0.10 + 0.14 * k))
		for i in 0 ..< 6 {
			a0 := t * 5 + f32(i) * (math.PI / 3)
			rl.DrawLineEx(center + [2]f32{math.cos(a0), math.sin(a0)} * rad, center + [2]f32{math.cos(a0 + 0.55), math.sin(a0 + 0.55)} * rad, 3, rl.Fade(rl.WHITE, 0.55 + 0.4 * k))
		}
		rl.EndBlendMode()
		rl.DrawCircleLines(i32(center.x), i32(center.y), rad, rl.Fade(scol, 0.7))
	}

	// Freeze aftermath: a pale frost ring while the user is slowed.
	if player_slowed(p) {
		pulse := 0.5 + 0.5 * math.sin(t * 8)
		fc := skill_color(.Freeze)
		rad := max(p.size.x, p.size.y) * 0.5 * s + 9
		rl.BeginBlendMode(.ADDITIVE)
		draw_glow(center, rad + 8, fc, 0.18 + 0.12 * pulse)
		rl.EndBlendMode()
		rl.DrawCircleLines(i32(center.x), i32(center.y), rad, rl.Fade(fc, 0.35 + 0.35 * pulse))
	}

	// Shield shell around the ship.
	shields := shield_count(p)
	if shields > 0 {
		half := max(p.size.x, p.size.y) * 0.5 * s
		pulse := 0.9 + 0.1 * math.sin(t * 6.0)
		rl.DrawCircleLines(i32(center.x), i32(center.y), half + 5 + f32(shields) * 2, rl.Fade(SHIELD_COLOR, 0.45 * pulse))
	}
}

draw_coins :: proc(g: ^Game) {
	for c in g.coins {
		if !c.active do continue
		if c.life < 3 && int(c.life * 8) % 2 == 0 do continue // blink before expiring
		w := max(abs(math.cos(c.spin)) * COIN_RADIUS, 1.5)
		cx := i32(c.pos.x)
		cy := i32(c.pos.y)
		rl.DrawEllipse(cx, cy, w + 1.6, COIN_RADIUS + 1.6, TOON_LINE)
		rl.DrawEllipse(cx, cy, w, COIN_RADIUS, rl.GOLD)
		rl.DrawEllipse(cx, cy, w * 0.55, COIN_RADIUS * 0.55, rl.YELLOW)
	}
}

draw_allies :: proc(g: ^Game) {
	for a in g.allies {
		if !a.active do continue
		if a.life < 3 && int(a.life * 8) % 2 == 0 do continue

		def := ally_def(a.kind)
		col := def.body_color
		if a.flash > 0 do col = rl.Color{255, 120, 120, 255}

		toon_disc(a.pos, a.radius, col)
		if def.draw_icon != nil do def.draw_icon(a)
		for i in 0 ..< int(a.hp) {
			px := a.pos.x + (f32(i) - f32(a.hp - 1) / 2) * 8
			rl.DrawCircleV([2]f32{px, a.pos.y - a.radius - 8}, 2.5, rl.LIME)
		}
	}
}

draw_status_pickups :: proc(g: ^Game) {
	t := g.time
	for pk in g.status_pickups {
		if !pk.active do continue
		// Blink during the last 3 seconds before it vanishes.
		if pk.life < 3 && g.phase != .LevelComplete && g.phase != .Sucking && int(pk.life * 8) % 2 == 0 do continue

		p := pk.pos
		pulse := 1.0 + 0.14 * math.sin(t * 6.0 + pk.pulse)
		col := status_color(pk.kind)
		label := status_label(pk.kind)

		rl.BeginBlendMode(.ADDITIVE)
		draw_glow(p, 36 * pulse, col, 0.55)
		rl.EndBlendMode()
		rl.DrawCircleV(p, 14 * pulse, TOON_LINE)
		rl.DrawCircleV(p, 12 * pulse, col)
		rl.DrawCircleV(p, 9 * pulse, rl.Color{24, 28, 40, 255})
		rl.DrawText(label, i32(p.x) - rl.MeasureText(label, 11) / 2, i32(p.y) - 6, 11, rl.WHITE)
	}
}

draw_boss_extras :: proc(g: ^Game, e: Enemy) {
	// Health bar (segmented, turns red-hot when enraged)
	bx := i32(e.pos.x) - 50
	by := i32(e.pos.y - e.radius) - 20
	bar_col := rl.RED if !e.enraged else rl.Color{255, 140, 40, 255}
	draw_bar(bx, by, 100, 10, f32(e.hp) / f32(e.max_hp), bar_col)
	segs := min(e.max_hp, 20)
	for i in 1 ..< segs {
		x := bx + i32(f32(i) / f32(segs) * 100)
		rl.DrawLine(x, by, x, by + 10, rl.Fade(rl.BLACK, 0.55))
	}
	if e.enraged {
		rl.DrawText("ENRAGED", bx + 50 - rl.MeasureText("ENRAGED", 12) / 2, by - 15, 12, rl.Fade(rl.RED, 0.6 + 0.4 * math.sin(g.time * 14)))
	}

	// Lunge telegraph: a blinking lane toward the target, then a hot streak.
	if e.dash_windup > 0 {
		k := 1.0 - e.dash_windup / BOSS_DASH_WINDUP
		blink := 0.5 + 0.5 * math.sin(g.time * 40)
		far := e.pos + e.dash_dir * (BOSS_DASH_SPEED * BOSS_DASH_TIME + e.radius)
		perp := [2]f32{-e.dash_dir.y, e.dash_dir.x} * e.radius * 0.8
		rl.BeginBlendMode(.ADDITIVE)
		draw_tri_ccw(e.pos + perp, e.pos - perp, far, rl.Fade(rl.Color{255, 40, 40, 255}, 0.08 + 0.12 * k * blink))
		rl.DrawLineEx(e.pos, far, 2, rl.Fade(rl.Color{255, 90, 90, 255}, 0.3 + 0.4 * blink))
		rl.EndBlendMode()
	}
	if e.dash_t > 0 {
		rl.BeginBlendMode(.ADDITIVE)
		rl.DrawLineEx(e.pos, e.pos - e.dash_dir * 150, e.radius * 1.2, rl.Fade(rl.Color{255, 60, 120, 255}, 0.28))
		rl.DrawLineEx(e.pos, e.pos - e.dash_dir * 110, e.radius * 0.5, rl.Fade(rl.WHITE, 0.4))
		rl.EndBlendMode()
	}

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

draw_entities :: proc(g: ^Game) {
	draw_coins(g)
	draw_allies(g)
	draw_status_pickups(g)
	draw_enemies(g)
	if g.freeze_ticks <= 0 { // frozen weapons are switched off
		draw_lasers(g)
		draw_rayguns(g)
	}
	draw_player_minions(g)
	draw_minion_lasers(g)
	draw_skill_pickups(g)
	draw_bullets(g)
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
		case .Status:
			text = fmt.ctprintf("STATUS %d/%d", f.value, MAX_STATUSES)
			color = rl.SKYBLUE
			size = 15
		case .Skill:
			text = skill_name(SkillKind(f.value))
			color = skill_color(SkillKind(f.value))
			size = 17
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
		draw_explosion(g.shaders.explosion, player_center(p) + shake_off, progress, REPULSION_RADIUS, color_vec(skill_color(.Explosion)))
	}
	for p in g.players {
		if p.repel_visual <= 0 do continue
		progress := (REPEL_VISUAL_TIME - p.repel_visual) / REPEL_VISUAL_TIME
		rc := color_vec(skill_color(.Repel))
		draw_blast(g.shaders.blast, player_center(p) + shake_off, progress, repel_radius(p), rc)
	}
	for p in g.players {
		if p.freeze_visual <= 0 do continue
		progress := (FREEZE_VISUAL_TIME - p.freeze_visual) / FREEZE_VISUAL_TIME
		draw_blast(g.shaders.blast, player_center(p) + shake_off, progress, 650, color_vec(skill_color(.Freeze)))
	}
	for p in g.players {
		if p.rewind_visual <= 0 do continue
		progress := (COMEBACK_VISUAL_TIME - p.rewind_visual) / COMEBACK_VISUAL_TIME
		draw_blast(g.shaders.blast, player_center(p) + shake_off, progress, 150, color_vec(skill_color(.ComeBack)))
	}
	for e in g.enemies {
		if !e.active || e.kind != .Boss || e.repel_visual <= 0 do continue
		progress := (BOSS_REPEL_VISUAL_TIME - e.repel_visual) / BOSS_REPEL_VISUAL_TIME
		draw_blast(g.shaders.blast, e.pos + shake_off, progress, BOSS_REPEL_RADIUS, {0.80, 0.35, 1.0})
	}
}

// Renders one complete frame of the game onto the fixed logical canvas.
render_world :: proc(g: ^Game) {
	hs := hole_state(g)
	draw_space_background(g, hs)

	shake_off := [2]f32{rand_signed(), rand_signed()} * g.fx.shake * shake_scale(g.settings)
	g.shake_off = shake_off // the ship shaders work in framebuffer pixels and need it
	camera := rl.Camera2D{offset = shake_off, zoom = 1.0}
	rl.BeginMode2D(camera)
	draw_black_hole(g, hs, shake_off)
	draw_glows(g)
	draw_entities(g)
	draw_particles(g)
	draw_floaters(g)
	rl.EndMode2D()

	draw_shockwaves(g, shake_off)
}
